import Foundation
import SlideCore

/// IWA位置索引。本文は選択時に解析し、展開partだけを予算内で共有する。
struct KeynoteObjectLocation: Sendable {
    let id: UInt64, type: UInt32, part: String, range: Range<Int>
    let version: [UInt64], objectReferences: [UInt64], dataReferences: [UInt64]
    let archiveHeader: Data, messageInfo: Data
}
final class KeynoteObjectIndex: Sendable {
    var cacheStatistics: ReadingCacheStatistics { cache.statistics }
    let locations: [KeynoteObjectLocation]
    let byID: [UInt64: [KeynoteObjectLocation]]
    private let archive: PackageArchive, limits: PackageLimits, cache: ReadingDataCache
    init(archive: PackageArchive, options: ReadOptions) throws {
        guard options.indexedCacheBytes >= 0 else { throw SlideError.invalidModel("Keynote索引cache予算") }
        self.archive = archive; limits = options.limits; cache = .init(limit:options.indexedCacheBytes)
        var all: [KeynoteObjectLocation] = [], expanded = 0, fields = 0
        for part in archive.paths.sorted() where part.hasPrefix("Index/") && part.hasSuffix(".iwa") {
            let bytes = try IWAFraming.iwa(archive.read(part),limit:min(limits.maxPartBytes,limits.maxExpandedBytes-expanded)); expanded += bytes.count
            let locations = try Wire.locations(bytes,part:part,limits:limits,fieldCount:&fields)
            guard locations.count <= limits.maxXMLNodes - all.count else { throw SlideError.limitExceeded("Keynote総object数") }
            all += locations
            cache.insert(bytes,for:part)
        }
        locations = all; byID = Dictionary(grouping:all,by:\.id)
    }
    func object(_ location: KeynoteObjectLocation) throws -> KeynoteObject {
        try archive.validateFile()
        let bytes: Data
        if let hit = cache.value(for:location.part) { bytes = hit }
        else { bytes = try IWAFraming.iwa(archive.read(location.part),limit:limits.maxPartBytes); cache.insert(bytes,for:location.part) }
        guard location.range.upperBound <= bytes.count else { throw SlideError.corruptedPackage("Keynote位置索引が無効") }
        let raw = bytes.subdata(in:location.range), fields = try Wire.fields(raw,limit:limits.maxXMLNodes)
        try archive.validateFile()
        return .init(id:location.id,type:location.type,part:location.part,version:location.version,objectReferences:location.objectReferences,dataReferences:location.dataReferences,fields:fields,rawData:raw,archiveHeader:location.archiveHeader,messageInfo:location.messageInfo)
    }
    func object(_ id: UInt64) throws -> KeynoteObject {
        guard let candidates = byID[id], candidates.count == 1 else { throw SlideError.corruptedPackage("Keynote object参照不在/merge未対応: \(id)") }
        return try object(candidates[0])
    }
}
extension Wire {
    /// 本文のwireを検証するが、fieldのDataコピーやモデルを全件保持しない。
    static func locations(_ payload: Data, part: String, limits: PackageLimits, fieldCount: inout Int) throws -> [KeynoteObjectLocation] {
        let b = [UInt8](payload); var offset = 0, result: [KeynoteObjectLocation] = []
        while offset < b.count {
            try Task.checkCancellation()
            let size = try IWAFraming.varint(b,&offset)
            guard size <= UInt64(b.count-offset) else { throw SlideError.corruptedPackage("IWA header切断") }
            let header = Data(b[offset..<offset+Int(size)]); offset += Int(size)
            let fields = try fields(header,limit:limits.maxXMLNodes-fieldCount), id = try scalar(fields,1); fieldCount += fields.count
            let infos = fields.filter { $0.number == 2 }; guard !infos.isEmpty else { throw SlideError.corruptedPackage("IWA messageInfoなし") }
            for info in infos {
                guard result.count < limits.maxXMLNodes, info.wireType == 2, let message = info.bytes else { throw SlideError.limitExceeded("IWA object数/wire") }
                let values = try self.fields(message,limit:limits.maxXMLNodes-fieldCount), type = try scalar(values,1), length = try scalar(values,3); fieldCount += values.count
                guard type <= UInt32.max, length <= UInt64(b.count-offset) else { throw SlideError.corruptedPackage("IWA object長/type") }
                let range = offset..<offset+Int(length)
                while offset < range.upperBound {
                    try Task.checkCancellation(); fieldCount += 1; guard fieldCount <= limits.maxXMLNodes else { throw SlideError.limitExceeded("Keynote総field数") }
                    let key = try IWAFraming.varint(b,&offset), number = key >> 3, wire = key & 7
                    guard number > 0, number < 1 << 29 else { throw SlideError.corruptedPackage("IWA field番号") }
                    if wire == 0 { _ = try IWAFraming.varint(b,&offset) }
                    else if [1,2,5].contains(wire) {
                        let size = try wire == 2 ? IWAFraming.varint(b,&offset) : wire == 1 ? 8 : 4
                        guard offset <= range.upperBound, size <= UInt64(range.upperBound-offset) else { throw SlideError.corruptedPackage("IWA field切断") }; offset += Int(size)
                    } else { throw SlideError.unsupportedContainer("Protobuf group wire \(wire)") }
                    guard offset <= range.upperBound else { throw SlideError.corruptedPackage("IWA field境界") }
                }
                result.append(try .init(id:id,type:UInt32(type),part:part,range:range,version:packed(values,2),objectReferences:packed(values,5),dataReferences:packed(values,6),archiveHeader:header,messageInfo:message))
            }
        }
        return result
    }
}
