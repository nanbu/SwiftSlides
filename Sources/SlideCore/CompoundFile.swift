import Foundation

package enum LE {
    package static func u16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i+1]) << 8 }
    package static func u32(_ b: [UInt8], _ i: Int) -> UInt32 { UInt32(u16(b,i)) | UInt32(u16(b,i+2)) << 16 }
    package static func u64(_ b: [UInt8], _ i: Int) -> UInt64 { UInt64(u32(b,i)) | UInt64(u32(b,i+4)) << 32 }
}
// MS-CFB v3/v4。鎖・木・サイズを検査し、循環や切断を拒否する。
package struct CompoundFile: Sendable {
    package static let signature = Data([0xD0,0xCF,0x11,0xE0,0xA1,0xB1,0x1A,0xE1])
    private struct Entry: Sendable { let name: String; let type: UInt8; let start: UInt32; let size: Int; let left: UInt32; let right: UInt32; let child: UInt32 }
    private let bytes: [UInt8], sectorSize: Int, fat: [UInt32], miniFat: [UInt32], entries: [Entry], miniStream: Data, limit: Int
    package init(data: Data, limits: PackageLimits) throws {
        try Task.checkCancellation()
        guard data.count >= 512, data.prefix(8) == Self.signature, limits.maxExpandedBytes >= 0, limits.maxEntries > 0,
              data.count <= limits.maxExpandedBytes else { throw SlideError.limitExceeded("CFB入力サイズ") }
        let b = [UInt8](data), version = LE.u16(b,26), shift = LE.u16(b,30)
        guard LE.u16(b,28) == 0xFFFE, (version == 3 && shift == 9) || (version == 4 && shift == 12), LE.u16(b,32) == 6, LE.u32(b,56) == 4096 else { throw SlideError.corruptedPackage("CFB header不正") }
        let ss = 1 << Int(shift)
        guard b.count >= ss, b.count % ss == 0 else { throw SlideError.corruptedPackage("CFB sector切断") }
        let sectorCount = b.count / ss - 1
        func sector(_ n: UInt32) throws -> [UInt8] {
            try Task.checkCancellation()
            guard UInt64(n) < UInt64(sectorCount) else { throw SlideError.corruptedPackage("CFB sector範囲外") }
            let start = (Int(n)+1)*ss; return Array(b[start..<start+ss])
        }
        let fatCount = Int(LE.u32(b,44)), difatCount = Int(LE.u32(b,72))
        guard fatCount <= sectorCount, difatCount <= sectorCount else { throw SlideError.corruptedPackage("CFB FAT数不正") }
        var fatSectors = (0..<109).map { LE.u32(b,76+$0*4) }.filter { $0 != UInt32.max }
        var next = LE.u32(b,68), seen = Set<UInt32>()
        for _ in 0..<difatCount {
            guard seen.insert(next).inserted else { throw SlideError.corruptedPackage("CFB DIFAT循環") }
            let s = try sector(next)
            fatSectors += (0..<ss/4-1).map { LE.u32(s,$0*4) }.filter { $0 != UInt32.max }; next = LE.u32(s,ss-4)
        }
        guard next == 0xFFFFFFFE || (difatCount == 0 && next == UInt32.max), fatSectors.count == fatCount, Set(fatSectors).count == fatCount else { throw SlideError.corruptedPackage("CFB DIFAT不整合") }
        var table: [UInt32] = []
        for n in fatSectors { let s = try sector(n); table += (0..<ss/4).map { LE.u32(s,$0*4) } }
        func chain(_ start: UInt32, _ table: [UInt32]) throws -> [UInt32] {
            var n = start, seen = Set<UInt32>(), result: [UInt32] = []
            while n != 0xFFFFFFFE {
                try Task.checkCancellation()
                guard Int(n) < table.count, seen.insert(n).inserted, result.count < sectorCount else { throw SlideError.corruptedPackage("CFB鎖の切断/循環") }
                result.append(n); n = table[Int(n)]
            }
            return result
        }
        let directorySectors = try chain(LE.u32(b,48),table)
        guard directorySectors.count <= limits.maxEntries / (ss/128) + 1 else { throw SlideError.limitExceeded("CFB directory数") }
        var dir: [UInt8] = []
        for n in directorySectors { dir += try sector(n) }
        var list: [Entry] = [], activeCount = 0
        for i in stride(from:0,to:dir.count,by:128) {
            let type = dir[i+66], length = Int(LE.u16(dir,i+64))
            guard type == 0 || ([1,2,5].contains(type) && length >= 2 && length <= 64 && length % 2 == 0 && LE.u16(dir,i+length-2) == 0) else { throw SlideError.corruptedPackage("CFB directory entry不正") }
            if type != 0 {
                guard activeCount < limits.maxEntries else { throw SlideError.limitExceeded("CFB有効entry数") }
                activeCount += 1
            }
            let units = type == 0 ? [] : stride(from:i,to:i+length-2,by:2).map { LE.u16(dir,$0) }
            let size = version == 3 ? UInt64(LE.u32(dir,i+120)) : LE.u64(dir,i+120)
            guard size <= UInt64(limits.maxExpandedBytes) else { throw SlideError.limitExceeded("CFB streamサイズ") }
            list.append(.init(name:String(decoding:units,as:UTF16.self),type:type,start:LE.u32(dir,i+116),size:Int(size),left:LE.u32(dir,i+68),right:LE.u32(dir,i+72),child:LE.u32(dir,i+76)))
        }
        guard let root = list.first, root.type == 5 else { throw SlideError.corruptedPackage("CFB rootなし") }
        let miniCount = Int(LE.u32(b,64))
        var mt: [UInt32] = []
        if miniCount > 0 {
            let ms = try chain(LE.u32(b,60),table)
            guard ms.count == miniCount else { throw SlideError.corruptedPackage("CFB miniFAT数不一致") }
            for n in ms { let s = try sector(n); mt += (0..<ss/4).map { LE.u32(s,$0*4) } }
        }
        var mini = Data()
        if root.size > 0 {
            for n in try chain(root.start,table) { mini.append(contentsOf:try sector(n)) }
            guard mini.count >= root.size, mini.count-root.size < ss else { throw SlideError.corruptedPackage("CFB miniStreamサイズ不整合") }
            mini = Data(mini.prefix(root.size))
        }
        bytes=b; sectorSize=ss; fat=table; miniFat=mt; entries=list; miniStream=mini; limit=limits.maxPartBytes
    }
    package func stream(_ name: String) throws -> Data {
        var stack = [entries[0].child], seen = Set<UInt32>(), found: Entry?
        while let n = stack.popLast() {
            try Task.checkCancellation()
            if n == UInt32.max { continue }
            guard Int(n) < entries.count, seen.insert(n).inserted else { throw SlideError.corruptedPackage("CFB directory木不正/循環") }
            let e = entries[Int(n)]
            if e.type == 2, e.name == name { guard found == nil else { throw SlideError.corruptedPackage("CFB stream重複") }; found=e }
            stack += [e.left,e.right]
        }
        guard let e = found else { throw SlideError.missingPart(name) }
        guard e.size <= limit else { throw SlideError.limitExceeded("CFB partサイズ") }
        var out=Data(), n=e.start, visited=Set<UInt32>()
        let small=e.size < 4096, table=small ? miniFat : fat, chunk=small ? 64 : sectorSize
        while out.count < e.size {
            try Task.checkCancellation()
            guard Int(n) < table.count, visited.insert(n).inserted else { throw SlideError.corruptedPackage("CFB stream鎖不正") }
            let start = small ? Int(n)*64 : (Int(n)+1)*sectorSize
            if small { guard start+chunk <= miniStream.count else { throw SlideError.corruptedPackage("CFB miniSector切断") }; out.append(miniStream[start..<start+chunk]) }
            else { guard start+chunk <= bytes.count else { throw SlideError.corruptedPackage("CFB sector切断") }; out.append(contentsOf:bytes[start..<start+chunk]) }
            n=table[Int(n)]
        }
        guard n == 0xFFFFFFFE else { throw SlideError.corruptedPackage("CFB余分なstream鎖") }
        return Data(out.prefix(e.size))
    }
}
