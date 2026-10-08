import Foundation

/// 文書順のスライドidentity。本文を含まない。
public struct SlideDescriptor: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let index: Int
    public init(id: String, name: String = "", index: Int) { self.id = id; self.name = name; self.index = index }
}
/// 一枚の読取結果。部分文書の誤保存を避けるためPresentationにはしない。
public struct SlideReadResult: Sendable {
    public let slide: Slide
    public let warnings: [SlideWarning]
    public var diagnostics: [SlideDiagnostic] { warnings.map { $0.diagnostic(stage:.read) } }
    public init(slide: Slide, warnings: [SlideWarning] = []) { self.slide = slide; self.warnings = warnings }
}
/// codecが所有する不変の索引。操作ごとに解析状態を所有する。
public protocol PresentationSlideSource: Sendable {
    var cacheStatistics: ReadingCacheStatistics? { get }
    var summary: PresentationSummary { get }
    var slideDescriptors: [SlideDescriptor] { get }
    func slide(at index: Int) throws -> SlideReadResult
    func asset(at path: String) throws -> Data
}
extension PresentationSlideSource { public var cacheStatistics: ReadingCacheStatistics? { nil } }
/// 選択読取を追加するcodecの能力。既存PresentationCodecの実装を変更しない。
public protocol SlideReadingCodec: PresentationCodec {
    func openSlides(_ data: Data, options: ReadOptions) throws -> any PresentationSlideSource
}
/// 読取対象。IDsの指定順を維持し、重複・欠落を拒否する。
public enum SlideSelection: Sendable { case all, ids([String]) }
/// memory snapshotと不変索引を共有する選択reader。元URLは監視しない。
public struct SlideReader: Sendable {
    private let source: any PresentationSlideSource
    private let indices: [String:Int]
    public var summary: PresentationSummary { source.summary }
    public var cacheStatistics: ReadingCacheStatistics? { source.cacheStatistics }
    public var slideDescriptors: [SlideDescriptor] { source.slideDescriptors }
    public init(data: Data, codecs: CodecSet, format: PresentationFormat? = nil, options: ReadOptions = .init()) throws {
        try Task.checkCancellation()
        let format = try format ?? PresentationFormat.detect(data,limits:options.limits)
        guard let codec = try codecs.codec(format) as? any SlideReadingCodec else { throw SlideError.unsupportedContainer("\(format.rawValue)の選択readerは未提供です") }
        source = try codec.openSlides(data,options:options)
        self.indices = try Self.index(source)
        try Task.checkCancellation()
    }
    public init(contentsOf url: URL, codecs: CodecSet, format: PresentationFormat? = nil, options: ReadOptions = .init()) throws {
        try Task.checkCancellation()
        try self.init(data:PackageInput.read(url,limits:options.limits),codecs:codecs,format:format,options:options)
    }
    /// URLの開いたdescriptorから部分読取。cache上限は圧縮bytesのcacheに適用する。
    public init(fileBackedURL url: URL, codecs: CodecSet, format: PresentationFormat? = nil, options: ReadOptions = .init(), cacheBytes: Int = 8 << 20) throws {
        try Task.checkCancellation()
        guard cacheBytes >= 0 else { throw SlideError.invalidModel("file-backed cache予算") }
        // Guardの索引用descriptorにはcacheを作らず、codec側だけに全予算を渡す。
        let archive = try PackageArchive(contentsOf: url, limits: options.limits, cacheBytes: 0)
        let detected: PresentationFormat
        if let format { detected = format }
        else if archive.entries["mimetype"] != nil, String(data: try archive.read("mimetype"), encoding: .utf8) == "application/vnd.oasis.opendocument.presentation" { detected = .odp }
        else if archive.entries["Index/Document.iwa"] != nil || archive.entries["Index.zip"] != nil { detected = .keynote }
        else { detected = try OPCPackage(archive: archive, limits: options.limits).format }
        guard let codec = try codecs.codec(detected) as? any FileSlideReadingCodec else { throw SlideError.unsupportedContainer("file-backed codecなし") }
        let opened = try codec.openSlides(contentsOf: url, options: options, cacheBytes: cacheBytes)
        try archive.validateFile()
        source = FileGuardedSource(source: opened, archive: archive)
        indices = try Self.index(source)
        try Task.checkCancellation()
    }
    private static func index(_ source: any PresentationSlideSource) throws -> [String: Int] {
        let descriptors = source.slideDescriptors
        guard descriptors.count == source.summary.slideCount else { throw SlideError.corruptedPackage("reader件数の不一致") }
        var indices: [String: Int] = [:]
        indices.reserveCapacity(descriptors.count)
        for (index, descriptor) in descriptors.enumerated() {
            try Task.checkCancellation()
            guard descriptor.index == index, !descriptor.id.isEmpty,
                  indices.updateValue(index, forKey: descriptor.id) == nil else {
                throw SlideError.corruptedPackage("readerのindex・IDが不正です")
            }
        }
        return indices
    }
    public init(fileBackedURL url: URL, codecs: CodecSet, format: PresentationFormat? = nil, options: ReadOptions = .init(), cacheBudget: ReaderCacheBudget) throws {
        guard cacheBudget.totalBytes >= 0 else { throw SlideError.invalidModel("共有cache予算") }
        let compressed = cacheBudget.totalBytes / 2
        var options = options; options.indexedCacheBytes = cacheBudget.totalBytes - compressed
        try self.init(fileBackedURL:url,codecs:codecs,format:format,options:options,cacheBytes:compressed)
    }
    public func slide(id: String) throws -> SlideReadResult {
        try Task.checkCancellation()
        guard let index = indices[id] else { throw SlideError.slideNotFound(id: id) }
        let result = try source.slide(at:index); try Task.checkCancellation(); return result
    }
    public func asset(at path: String) throws -> Data { try assetSync(at: path) }
    @concurrent public func asset(at path: String) async throws -> Data { try assetSync(at: path) }
    private func assetSync(at path: String) throws -> Data {
        try Task.checkCancellation()
        let result = try source.asset(at: path)
        try Task.checkCancellation()
        return result
    }
    @concurrent public func slide(id: String) async throws -> SlideReadResult { try slideSync(id:id) }
    private func slideSync(id: String) throws -> SlideReadResult { try slide(id:id) }
    /// next()ごとに一枚だけ読む。background producerや先読みはない。
    public func slides(selection: SlideSelection = .all) throws -> SlideSequence {
        try Task.checkCancellation()
        let ids: [String]
        switch selection { case .all: ids = slideDescriptors.map(\.id); case .ids(let selected): ids = selected }
        var seen: Set<String> = []
        for id in ids { guard indices[id] != nil, seen.insert(id).inserted else { throw SlideError.invalidModel("欠落または重複した選択ID: \(id)") } }
        return .init(reader:self,ids:ids)
    }
    /// 同一索引から指定件数だけ並列に読み、結果は選択順で返す。失敗時は残りを取り消す。
    @concurrent public func readSlides(selection: SlideSelection = .all, maxConcurrentReads: Int = 4) async throws -> [SlideReadResult] {
        let ids = try slides(selection:selection).ids
        return try await boundedMap(ids, maxConcurrent: maxConcurrentReads) { id in
            try await self.slide(id: id)
        }
    }
    public struct SlideSequence: AsyncSequence, Sendable {
        public typealias Element = SlideReadResult
        fileprivate let reader: SlideReader
        fileprivate let ids: [String]
        public func makeAsyncIterator() -> AsyncIterator { .init(reader:reader,ids:ids) }
        public struct AsyncIterator: AsyncIteratorProtocol {
            private let reader: SlideReader
            private let ids: [String]
            private var index = 0
            fileprivate init(reader: SlideReader, ids: [String]) { self.reader = reader; self.ids = ids }
            public mutating func next() async throws -> SlideReadResult? {
                try Task.checkCancellation()
                guard index < ids.count else { return nil }
                let result = try await reader.slide(id:ids[index]); index += 1; return result
            }
        }
    }
}

extension CodecSet {
    public func fileSlideReader(contentsOf url: URL, format: PresentationFormat? = nil, options: ReadOptions = .init(), cacheBudget: ReaderCacheBudget) throws -> SlideReader {
        try SlideReader(fileBackedURL: url, codecs: self, format: format, options: options, cacheBudget: cacheBudget)
    }
    @concurrent public func fileSlideReader(contentsOf url: URL, format: PresentationFormat? = nil, options: ReadOptions = .init(), cacheBudget: ReaderCacheBudget) async throws -> SlideReader {
        try SlideReader(fileBackedURL: url, codecs: self, format: format, options: options, cacheBudget: cacheBudget)
    }
    public func slideReader(_ data: Data, format: PresentationFormat? = nil, options: ReadOptions = .init()) throws -> SlideReader {
        try SlideReader(data: data, codecs: self, format: format, options: options)
    }
    public func slideReader(contentsOf url: URL, format: PresentationFormat? = nil, options: ReadOptions = .init()) throws -> SlideReader {
        try SlideReader(contentsOf: url, codecs: self, format: format, options: options)
    }
    @concurrent public func slideReader(_ data: Data, format: PresentationFormat? = nil, options: ReadOptions = .init()) async throws -> SlideReader {
        try SlideReader(data: data, codecs: self, format: format, options: options)
    }
    @concurrent public func slideReader(contentsOf url: URL, format: PresentationFormat? = nil, options: ReadOptions = .init()) async throws -> SlideReader {
        try SlideReader(contentsOf: url, codecs: self, format: format, options: options)
    }
}


public protocol FileSlideReadingCodec: SlideReadingCodec {
    func openSlides(contentsOf url: URL, options: ReadOptions, cacheBytes: Int) throws -> any PresentationSlideSource
}
private struct FileGuardedSource: PresentationSlideSource {
    let source: any PresentationSlideSource
    let archive: PackageArchive
    var summary: PresentationSummary { source.summary }
    var cacheStatistics: ReadingCacheStatistics? { source.cacheStatistics }
    var slideDescriptors: [SlideDescriptor] { source.slideDescriptors }
    func slide(at index: Int) throws -> SlideReadResult { try archive.validateFile(); let result = try source.slide(at: index); try archive.validateFile(); return result }
    func asset(at path: String) throws -> Data { try archive.validateFile(); let result = try source.asset(at: path); try archive.validateFile(); return result }
}
extension CodecSet {
    public func fileSlideReader(contentsOf url: URL, format: PresentationFormat? = nil, options: ReadOptions = .init(), cacheBytes: Int = 8 << 20) throws -> SlideReader { try .init(fileBackedURL: url, codecs: self, format: format, options: options, cacheBytes: cacheBytes) }
    @concurrent public func fileSlideReader(contentsOf url: URL, format: PresentationFormat? = nil, options: ReadOptions = .init(), cacheBytes: Int = 8 << 20) async throws -> SlideReader { try SlideReader(fileBackedURL: url, codecs: self, format: format, options: options, cacheBytes: cacheBytes) }
}
