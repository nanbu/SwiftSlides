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
    var summary: PresentationSummary { get }
    var slideDescriptors: [SlideDescriptor] { get }
    func slide(at index: Int) throws -> SlideReadResult
    func asset(at path: String) throws -> Data
}
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
    public var slideDescriptors: [SlideDescriptor] { source.slideDescriptors }
    public init(data: Data, codecs: CodecSet, format: PresentationFormat? = nil, options: ReadOptions = .init()) throws {
        try Task.checkCancellation()
        let format = try format ?? PresentationFormat.detect(data,limits:options.limits)
        guard let codec = try codecs.codec(format) as? any SlideReadingCodec else { throw SlideError.unsupportedContainer("\(format.rawValue)の選択readerは未提供です") }
        source = try codec.openSlides(data,options:options)
        var indices: [String:Int] = [:]
        for (index,descriptor) in source.slideDescriptors.enumerated() {
            guard !descriptor.id.isEmpty, indices[descriptor.id] == nil else { throw SlideError.corruptedPackage("空または重複reader slide ID") }
            indices[descriptor.id] = index
        }
        self.indices = indices
        try Task.checkCancellation()
    }
    public init(contentsOf url: URL, codecs: CodecSet, options: ReadOptions = .init()) throws {
        try Task.checkCancellation()
        try self.init(data:Data(contentsOf:url),codecs:codecs,options:options)
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
        let ids: [String]
        switch selection { case .all: ids = slideDescriptors.map(\.id); case .ids(let selected): ids = selected }
        var seen: Set<String> = []
        for id in ids { guard indices[id] != nil, seen.insert(id).inserted else { throw SlideError.invalidModel("欠落または重複した選択ID: \(id)") } }
        return .init(reader:self,ids:ids)
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
    public func slideReader(_ data: Data, format: PresentationFormat? = nil, options: ReadOptions = .init()) throws -> SlideReader {
        try SlideReader(data: data, codecs: self, format: format, options: options)
    }
    public func slideReader(contentsOf url: URL, options: ReadOptions = .init()) throws -> SlideReader {
        try SlideReader(contentsOf: url, codecs: self, options: options)
    }
    @concurrent public func slideReader(_ data: Data, format: PresentationFormat? = nil, options: ReadOptions = .init()) async throws -> SlideReader {
        try SlideReader(data: data, codecs: self, format: format, options: options)
    }
    @concurrent public func slideReader(contentsOf url: URL, options: ReadOptions = .init()) async throws -> SlideReader {
        try SlideReader(contentsOf: url, codecs: self, options: options)
    }
}
