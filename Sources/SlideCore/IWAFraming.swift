import Foundation

package enum IWAFraming {
    package static func varint(_ b: [UInt8], _ offset: inout Int) throws -> UInt64 {
        var value:UInt64=0
        for shift in stride(from:0,through:63,by:7) {
            guard offset < b.count else { throw SlideError.corruptedPackage("Protobuf varint切断") }
            let byte=b[offset]; offset += 1
            guard shift != 63 || byte <= 1 else { throw SlideError.corruptedPackage("Protobuf整数overflow") }
            value |= UInt64(byte & 127) << shift
            if byte & 128 == 0 { return value }
        }
        throw SlideError.corruptedPackage("Protobuf varint不正")
    }
    package static func snappy(_ input: [UInt8], limit: Int) throws -> [UInt8] {
        var offset=0;let declared=try varint(input,&offset)
        guard limit >= 0, declared <= UInt64(limit) else { throw SlideError.limitExceeded("Snappy展開量") }
        let expected=Int(declared);var out:[UInt8]=[];out.reserveCapacity(expected)
        while offset < input.count {
            try Task.checkCancellation()
            let tag=input[offset];offset += 1;let kind=tag&3
            if kind == 0 {
                var length=Int(tag>>2)+1
                if length > 60 {
                    let bytes=length-60;guard offset+bytes <= input.count else { throw SlideError.corruptedPackage("Snappy literal長切断") }
                    var n:UInt32=0;for i in 0..<bytes { n |= UInt32(input[offset+i]) << (8*i) };offset += bytes;length=Int(n)+1
                }
                guard length <= input.count-offset, length <= expected-out.count else { throw SlideError.corruptedPackage("Snappy literal範囲外") }
                out += input[offset..<offset+length];offset += length
            } else {
                let size=kind == 1 ? 1 : kind == 2 ? 2 : 4
                guard offset+size <= input.count else { throw SlideError.corruptedPackage("Snappy copy切断") }
                var distance:UInt32=0;for i in 0..<size { distance |= UInt32(input[offset+i]) << (8*i) };offset += size
                let length=kind == 1 ? Int((tag>>2)&7)+4 : Int(tag>>2)+1
                if kind == 1 { distance |= UInt32(tag&224)<<3 }
                guard distance > 0, UInt64(distance) <= UInt64(out.count), length <= expected-out.count else { throw SlideError.corruptedPackage("Snappy copy範囲外") }
                for _ in 0..<length { out.append(out[out.count-Int(distance)]) }
            }
        }
        guard out.count == expected else { throw SlideError.corruptedPackage("Snappy展開長不一致") };return out
    }
    package static func iwa(_ data: Data, limit: Int) throws -> Data {
        let b=[UInt8](data);var offset=0,out=Data()
        guard !b.isEmpty else { throw SlideError.corruptedPackage("空IWA") }
        while offset < b.count {
            try Task.checkCancellation()
            guard offset+4 <= b.count, b[offset] == 0 else { throw SlideError.corruptedPackage("IWA chunk header不正") }
            let size=Int(b[offset+1]) | Int(b[offset+2])<<8 | Int(b[offset+3])<<16;offset += 4
            guard size > 0, size <= b.count-offset else { throw SlideError.corruptedPackage("IWA chunk切断") }
            out.append(contentsOf:try snappy(Array(b[offset..<offset+size]),limit:limit-out.count));offset += size
        };return out
    }
    package static func isKeynote(_ data: Data, limit: Int) throws -> Bool {
        let b = [UInt8](try iwa(data, limit: limit)); var offset = 0
        while offset < b.count {
            let length = try varint(b, &offset)
            guard length <= UInt64(b.count-offset) else { throw SlideError.corruptedPackage("IWA header切断") }
            let end = offset+Int(length); var messages: [[UInt8]] = []
            while offset < end {
                let key = try varint(b, &offset)
                if key & 7 == 0 { _ = try varint(b, &offset) }
                else if key & 7 == 2 {
                    let size = try varint(b, &offset); guard offset <= end, size <= UInt64(end-offset) else { throw SlideError.corruptedPackage("IWA field切断") }
                    if key >> 3 == 2 { messages.append(Array(b[offset..<offset+Int(size)])) }; offset += Int(size)
                } else { throw SlideError.corruptedPackage("IWA archive wire不正") }
            }
            guard offset == end else { throw SlideError.corruptedPackage("IWA header境界不正") }
            for info in messages {
                var p = 0; var type: UInt64?, size: UInt64?
                while p < info.count {
                    let key = try varint(info, &p)
                    switch key & 7 {
                    case 0: let value = try varint(info, &p); if key >> 3 == 1 { type=value }; if key >> 3 == 3 { size=value }
                    case 2: let n = try varint(info, &p); guard n <= UInt64(info.count-p) else { throw SlideError.corruptedPackage("IWA info切断") }; p += Int(n)
                    default: throw SlideError.corruptedPackage("IWA info wire不正")
                    }
                }
                guard let size, size <= UInt64(b.count-offset) else { throw SlideError.corruptedPackage("IWA object切断") }
                if type == 1 {
                    let body=Array(b[offset..<offset+Int(size)]); var p=0, fields=Set<UInt64>()
                    while p < body.count {
                        let key=try varint(body,&p); fields.insert(key>>3)
                        switch key & 7 {
                        case 0: _ = try varint(body,&p)
                        case 1,5: let n=key&7 == 1 ? 8 : 4;guard n <= body.count-p else { throw SlideError.corruptedPackage("IWA body切断") };p += n
                        case 2: let n=try varint(body,&p);guard n <= UInt64(body.count-p) else { throw SlideError.corruptedPackage("IWA body切断") };p += Int(n)
                        default: throw SlideError.corruptedPackage("IWA body wire不正")
                        }
                    }
                    if fields.contains(2),fields.contains(3),!fields.contains(8) { return true }
                };offset += Int(size)
            }
        }
        return false
    }
}
