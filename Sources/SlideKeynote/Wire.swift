import Foundation
import SlideCore

/// fieldの順序・wire値・原本bytes。bytesを未確認の子messageと推測しない。
public struct KeynoteField: Sendable, Equatable, Codable {
    public let number: UInt32
    public let wireType: UInt8
    public let integer: UInt64?
    public let bytes: Data?
    public let rawData: Data
    public var utf8: String? { bytes.flatMap { String(data:$0,encoding:.utf8) } }
    public var float32: Float? {
        guard wireType == 5,let bytes,bytes.count == 4 else { return nil }
        return Float(bitPattern:bytes.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8*$1.offset) })
    }
    public var float64: Double? {
        guard wireType == 1,let bytes,bytes.count == 8 else { return nil }
        return Double(bitPattern:bytes.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8*$1.offset) })
    }
    /// schemaで子messageと確認したfieldだけ明示的に解釈する。
    public func message(maxFields:Int = 1_000_000) throws -> [KeynoteField] {
        guard wireType == 2,let bytes else { throw SlideError.corruptedPackage("子message以外のKeynote field") }
        return try Wire.fields(bytes,limit:maxFields)
    }
}
public struct KeynoteObject: Sendable, Equatable, Codable {
    public let id: UInt64
    public let type: UInt32
    public let part: String
    public let version: [UInt64]
    public let objectReferences: [UInt64]
    public let dataReferences: [UInt64]
    public let fields: [KeynoteField]
    public let rawData: Data
    public let archiveHeader: Data
    public let messageInfo: Data
}
public struct KeynoteInventory: Sendable {
    public let objects: [KeynoteObject]
    public let dataReferences: [KeynoteDataReference]
    public let warnings: [SlideWarning]
    public var diagnostics: [SlideDiagnostic] { warnings.map { $0.diagnostic(stage:.read) } }
    /// merge/diffがあるidentityは複数messageを順序どおり返す。
    public func objects(id:UInt64) -> [KeynoteObject] { objects.filter { $0.id == id } }
    package init(objects:[KeynoteObject],dataReferences:[KeynoteDataReference] = [],warnings:[SlideWarning]) { self.objects=objects;self.dataReferences=dataReferences;self.warnings=warnings }
}
public struct KeynoteDataReference: Sendable, Equatable, Codable {
    public let id:UInt64
    public let path:String?
    public let remoteURL:String?
    public let fields:[KeynoteField]
    public let rawData:Data
}
package enum Wire {
    static func fields(_ data: Data, limit: Int) throws -> [KeynoteField] {
        let b=[UInt8](data); var offset=0, result:[KeynoteField]=[]
        while offset < b.count {
            try Task.checkCancellation()
            guard result.count < limit else { throw SlideError.limitExceeded("Protobuf field数") }
            let start=offset, key=try IWAFraming.varint(b,&offset), number=key>>3, wire=UInt8(key&7)
            guard number > 0, number < 1<<29 else { throw SlideError.corruptedPackage("Protobuf field番号不正") }
            var integer:UInt64?, bytes:Data?
            if wire == 0 { integer=try IWAFraming.varint(b,&offset) }
            else if [1,2,5].contains(wire) {
                let size:UInt64 = wire == 2 ? try IWAFraming.varint(b,&offset) : wire == 1 ? 8 : 4
                guard size <= UInt64(b.count-offset) else { throw SlideError.corruptedPackage("Protobuf field切断") }
                bytes=Data(b[offset..<offset+Int(size)]); offset += Int(size)
            } else { throw SlideError.unsupportedContainer("Protobuf group wire \(wire)") }
            result.append(.init(number:UInt32(number),wireType:wire,integer:integer,bytes:bytes,rawData:Data(b[start..<offset])))
        }
        return result
    }
    static func scalar(_ fields: [KeynoteField], _ number: UInt32) throws -> UInt64 {
        let matches=fields.filter { $0.number == number }
        guard matches.count == 1, let value=matches[0].integer else { throw SlideError.corruptedPackage("Protobuf scalar \(number)不在/重複") }; return value
    }
    static func packed(_ fields: [KeynoteField], _ number: UInt32) throws -> [UInt64] {
        var result:[UInt64]=[]
        for f in fields where f.number == number {
            if let n=f.integer { result.append(n) }
            else if f.wireType == 2, let data=f.bytes {
                let b=[UInt8](data);var offset=0
                while offset < b.count { try Task.checkCancellation(); result.append(try IWAFraming.varint(b,&offset)) }
            } else { throw SlideError.corruptedPackage("Protobuf packed wire不正") }
        };return result
    }
    static func objects(_ payload: Data, part: String, limits: PackageLimits, fieldCount:inout Int) throws -> [KeynoteObject] {
        let b=[UInt8](payload);var offset=0,result:[KeynoteObject]=[]
        while offset < b.count {
            try Task.checkCancellation()
            let size=try IWAFraming.varint(b,&offset)
            guard size <= UInt64(b.count-offset) else { throw SlideError.corruptedPackage("IWA archive header切断") }
            let header=Data(b[offset..<offset+Int(size)]);offset += Int(size)
            let fields=try fields(header,limit:limits.maxXMLNodes-fieldCount),id=try scalar(fields,1)
            fieldCount += fields.count
            let infos=fields.filter { $0.number == 2 }
            guard !infos.isEmpty else { throw SlideError.corruptedPackage("IWA messageInfoなし") }
            for info in infos {
                guard result.count < limits.maxXMLNodes, info.wireType == 2, let bytes=info.bytes else { throw SlideError.limitExceeded("IWA object数/wire") }
                let f=try self.fields(bytes,limit:limits.maxXMLNodes-fieldCount),type=try scalar(f,1),length=try scalar(f,3)
                fieldCount += f.count
                guard type <= UInt32.max, length <= UInt64(b.count-offset) else { throw SlideError.corruptedPackage("IWA object長/type不正") }
                let raw=Data(b[offset..<offset+Int(length)]);offset += Int(length)
                let body=try self.fields(raw,limit:limits.maxXMLNodes-fieldCount);fieldCount += body.count
                result.append(try .init(id:id,type:UInt32(type),part:part,version:packed(f,2),objectReferences:packed(f,5),dataReferences:packed(f,6),fields:body,rawData:raw,archiveHeader:header,messageInfo:bytes))
            }
        };return result
    }
}
