import Foundation
@_exported import SlideCore
@_exported import SlidePPTX
@_exported import SlideODP
@_exported import SlideKeynote
@_exported import SlideLegacy

extension CodecSet {
    public static let all = CodecSet([.pptx, .pptm, .odp, .keynote, .ppt, .keynoteLegacy, .sxi])
}
extension Presentation {
    public func write(as format: PresentationFormat? = nil, options: WriteOptions = .init()) throws -> WriteResult {
        try CodecSet.all.write(self, as: format, options: options)
    }
    public func write(as format: PresentationFormat? = nil, options: WriteOptions = .init()) async throws -> WriteResult {
        try await CodecSet.all.write(self, as: format, options: options)
    }
    public func write(using plan: SavePlan, options: WriteOptions? = nil) throws -> WriteResult {
        try CodecSet.all.write(self, using: plan, options: options)
    }
    public func write(using plan: SavePlan, options: WriteOptions? = nil) async throws -> WriteResult {
        try await CodecSet.all.write(self, using: plan, options: options)
    }
    public func write(to url: URL, using plan: SavePlan, options: WriteOptions? = nil) throws -> WriteResult {
        try CodecSet.all.write(self, to: url, using: plan, options: options)
    }
    public func write(to url: URL, using plan: SavePlan, options: WriteOptions? = nil) async throws -> WriteResult {
        try await CodecSet.all.write(self, to: url, using: plan, options: options)
    }
    @discardableResult public mutating func duplicateSlide(id: String, at index: Int? = nil) throws -> String {
        try CodecSet.all.duplicateSlide(id: id, in: &self, at: index)
    }
    @discardableResult public mutating func importSlide(id: String, from source: Presentation, at index: Int? = nil, options: SlideImportOptions = .init()) throws -> String {
        try CodecSet.all.importSlide(id: id, from: source, into: &self, at: index, options: options)
    }
    public func inspectPreservation() throws -> PackageGraph { try CodecSet.all.inspectPreservation(self) }
    public func planWrite(as format: PresentationFormat? = nil, options: WriteOptions = .init()) throws -> SavePlan { try CodecSet.all.planWrite(self, as: format, options: options) }
    public func planWrite(as format: PresentationFormat? = nil, options: WriteOptions = .init()) async throws -> SavePlan { try await CodecSet.all.planWrite(self, as: format, options: options) }
    public init(data: Data, format: PresentationFormat? = nil, options: ReadOptions = .init()) throws { self = try CodecSet.all.read(data,format:format,options:options).presentation }
    public init(contentsOf url: URL, format: PresentationFormat? = nil, options: ReadOptions = .init()) throws { self = try CodecSet.all.read(contentsOf:url,format:format,options:options).presentation }
    public static func read(_ data: Data, format: PresentationFormat? = nil, options: ReadOptions = .init()) throws -> ReadResult { try CodecSet.all.read(data,format:format,options:options) }
    public static func read(contentsOf url: URL, format: PresentationFormat? = nil, options: ReadOptions = .init()) throws -> ReadResult { try CodecSet.all.read(contentsOf:url,format:format,options:options) }
    public static func inspect(_ data: Data, format: PresentationFormat? = nil, options: InspectOptions = .init()) throws -> PresentationSummary { try CodecSet.all.inspect(data,format:format,options: options) }
    public static func inspect(contentsOf url: URL, format: PresentationFormat? = nil, options: InspectOptions = .init()) throws -> PresentationSummary { try CodecSet.all.inspect(contentsOf:url,format:format,options: options) }
    public func write(to url: URL, as format: PresentationFormat? = nil, options: WriteOptions = .init()) throws -> WriteResult { try CodecSet.all.write(self,to:url,as:format,options:options) }

    /// writerで検査できた変更だけを反映する。戻り値の警告を確認してから保存する。
    public mutating func transaction(options: WriteOptions = .init(strict: true), _ body: (inout Presentation) throws -> Void) throws -> WriteResult {
        try CodecSet.all.transaction(&self, options: options, body)
    }

    public static func read(_ data: Data, format: PresentationFormat? = nil, options: ReadOptions = .init()) async throws -> ReadResult { try await CodecSet.all.read(data, format: format, options: options) }
    public static func read(contentsOf url: URL, format: PresentationFormat? = nil, options: ReadOptions = .init()) async throws -> ReadResult { try await CodecSet.all.read(contentsOf: url, format: format, options: options) }
    public static func inspect(_ data: Data, format: PresentationFormat? = nil, options: InspectOptions = .init()) async throws -> PresentationSummary { try await CodecSet.all.inspect(data, format: format, options: options) }
    public static func inspect(contentsOf url: URL, format: PresentationFormat? = nil, options: InspectOptions = .init()) async throws -> PresentationSummary { try await CodecSet.all.inspect(contentsOf: url, format: format, options: options) }
    public static func readAll(contentsOf urls: [URL], format: PresentationFormat? = nil, options: ReadOptions = .init(), maxConcurrentReads: Int = 4) async throws -> [ReadResult] { try await CodecSet.all.readAll(contentsOf: urls, format: format, options: options, maxConcurrentReads: maxConcurrentReads) }
    public func write(to url: URL, as format: PresentationFormat? = nil, options: WriteOptions = .init()) async throws -> WriteResult { try await CodecSet.all.write(self, to: url, as: format, options: options) }
}

extension SlideReader {
    public init(data: Data, format: PresentationFormat? = nil, options: ReadOptions = .init()) throws {
        try self.init(data: data, codecs: .all, format: format, options: options)
    }
    public init(contentsOf url: URL, format: PresentationFormat? = nil, options: ReadOptions = .init()) throws {
        try self.init(contentsOf: url, codecs: .all, format: format, options: options)
    }
}


extension SlideReader {
    public init(fileBackedURL url: URL, format: PresentationFormat? = nil, options: ReadOptions = .init(), cacheBytes: Int = 8 << 20) throws { try self.init(fileBackedURL: url, codecs: .all, format: format, options: options, cacheBytes: cacheBytes) }
    public init(fileBackedURL url: URL, format: PresentationFormat? = nil, options: ReadOptions = .init(), cacheBudget: ReaderCacheBudget) throws { try self.init(fileBackedURL: url, codecs: .all, format: format, options: options, cacheBudget: cacheBudget) }
}
