import Foundation
import SlideCore

struct ODPPageLocation: Sendable {
    let range: Range<Int>
    let namespaces: [String:String]
}
final class ODPPageIndex: Sendable {
    var cacheStatistics: ReadingCacheStatistics { cache.statistics }
    private let archive: PackageArchive, cache: ReadingDataCache
    init(archive: PackageArchive, initial: Data, cacheBytes: Int) throws {
        guard cacheBytes >= 0 else { throw SlideError.invalidModel("ODP索引cache予算") }
        self.archive = archive; cache = .init(limit:cacheBytes); cache.insert(initial,for:"content.xml")
    }
    func page(_ location: ODPPageLocation, limits: PackageLimits) throws -> MarkupNode {
        try archive.validateFile()
        let bytes: Data
        if let hit = cache.value(for:"content.xml") { bytes = hit }
        else { bytes = try XMLSubtreeIndex.utf8(archive.read("content.xml")); cache.insert(bytes,for:"content.xml") }
        guard location.range.upperBound <= bytes.count else { throw SlideError.corruptedPackage("ODP位置索引が無効") }
        let namespaces = location.namespaces.filter { $0.key != "xml" }.sorted { $0.key < $1.key }.map { key,value in " xmlns\(key.isEmpty ? "" : ":"+key)=\"\(escapeXML(value))\"" }.joined()
        var xml = Data("<ss-index\(namespaces)>".utf8); xml.append(bytes.subdata(in:location.range)); xml.append(Data("</ss-index>".utf8))
        // ラッパーは入力に含まれない1要素・1階層。
        var bounded = limits
        if bounded.maxXMLDepth < Int.max { bounded.maxXMLDepth += 1 }; if bounded.maxXMLNodes < Int.max { bounded.maxXMLNodes += 1 }
        let root = try MarkupNode.parse(xml,part:"content.xml",limits:bounded)
        guard root.children.count == 1, let page = root.children.first else { throw SlideError.corruptedPackage("ODPページ索引の境界") }
        try archive.validateFile(); return page
    }
}
