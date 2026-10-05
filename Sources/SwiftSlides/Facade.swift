import Foundation
@_exported import SlideCore
@_exported import SlidePPTX
@_exported import SlideODP

extension CodecSet {
    public static let all = CodecSet([.pptx, .pptm, .odp])
}
extension Presentation {
    @discardableResult public mutating func duplicateSlide(id: String, at index: Int? = nil) throws -> String {
        try CodecSet.all.duplicateSlide(id: id, in: &self, at: index)
    }
    @discardableResult public mutating func importSlide(id: String, from source: Presentation, at index: Int? = nil, options: SlideImportOptions = .init()) throws -> String {
        try CodecSet.all.importSlide(id: id, from: source, into: &self, at: index, options: options)
    }
    public func inspectPreservation() throws -> PackageGraph { try CodecSet.all.inspectPreservation(self) }
    public func planWrite(as format: PresentationFormat? = nil, options: WriteOptions = .init()) throws -> SavePlan { try CodecSet.all.planWrite(self, as: format, options: options) }
    public func encoded(using plan: SavePlan, options: WriteOptions? = nil) throws -> WriteResult { try CodecSet.all.encoded(self, using: plan, options: options) }
    public func save(to url: URL, using plan: SavePlan, options: WriteOptions? = nil) throws -> WriteResult { try CodecSet.all.save(self, to: url, using: plan, options: options) }
    public func planWrite(as format: PresentationFormat? = nil, options: WriteOptions = .init()) async throws -> SavePlan { try await CodecSet.all.planWrite(self, as: format, options: options) }
    public func encoded(using plan: SavePlan, options: WriteOptions? = nil) async throws -> WriteResult { try await CodecSet.all.encoded(self, using: plan, options: options) }
    public func save(to url: URL, using plan: SavePlan, options: WriteOptions? = nil) async throws -> WriteResult { try await CodecSet.all.save(self, to: url, using: plan, options: options) }
    public init(data: Data, format: PresentationFormat? = nil, options: ReadOptions = .init()) throws { self = try CodecSet.all.read(data,format:format,options:options).presentation }
    public init(contentsOf url: URL, options: ReadOptions = .init()) throws { self = try CodecSet.all.read(contentsOf:url,options:options).presentation }
    public static func read(_ data: Data, format: PresentationFormat? = nil, options: ReadOptions = .init()) throws -> ReadResult { try CodecSet.all.read(data,format:format,options:options) }
    public static func read(contentsOf url: URL, options: ReadOptions = .init()) throws -> ReadResult { try CodecSet.all.read(contentsOf:url,options:options) }
    public static func inspect(_ data: Data, format: PresentationFormat? = nil, limits: PackageLimits = .init()) throws -> PresentationSummary { try CodecSet.all.inspect(data,format:format,limits:limits) }
    public static func inspect(contentsOf url: URL, limits: PackageLimits = .init()) throws -> PresentationSummary { try CodecSet.all.inspect(contentsOf:url,limits:limits) }
    public func data(as format: PresentationFormat? = nil, options: WriteOptions = .init()) throws -> Data { try CodecSet.all.write(self,as:format,options:options).data }
    public func encoded(as format: PresentationFormat? = nil, options: WriteOptions = .init()) throws -> WriteResult { try CodecSet.all.write(self,as:format,options:options) }
    public func write(to url: URL, as format: PresentationFormat? = nil, options: WriteOptions = .init()) throws -> WriteResult { try CodecSet.all.write(self,to:url,as:format,options:options) }

    /// writerで検査できた変更だけを反映する。戻り値の警告を確認してから保存する。
    public mutating func transaction(options: WriteOptions = .init(strict: true), _ body: (inout Presentation) throws -> Void) throws -> WriteResult {
        try CodecSet.all.transaction(&self, options: options, body)
    }

    public static func read(_ data: Data, format: PresentationFormat? = nil, options: ReadOptions = .init()) async throws -> ReadResult { try await CodecSet.all.read(data, format: format, options: options) }
    public static func read(contentsOf url: URL, options: ReadOptions = .init()) async throws -> ReadResult { try await CodecSet.all.read(contentsOf: url, options: options) }
    public static func inspect(_ data: Data, format: PresentationFormat? = nil, limits: PackageLimits = .init()) async throws -> PresentationSummary { try await CodecSet.all.inspect(data, format: format, limits: limits) }
    public static func inspect(contentsOf url: URL, limits: PackageLimits = .init()) async throws -> PresentationSummary { try await CodecSet.all.inspect(contentsOf: url, limits: limits) }
    public static func readAll(contentsOf urls: [URL], options: ReadOptions = .init(), maxConcurrentReads: Int = 4) async throws -> [ReadResult] { try await CodecSet.all.readAll(contentsOf: urls, options: options, maxConcurrentReads: maxConcurrentReads) }
    public func data(as format: PresentationFormat? = nil, options: WriteOptions = .init()) async throws -> Data { try await encoded(as: format, options: options).data }
    public func encoded(as format: PresentationFormat? = nil, options: WriteOptions = .init()) async throws -> WriteResult { try await CodecSet.all.write(self, as: format, options: options) }
    public func write(to url: URL, as format: PresentationFormat? = nil, options: WriteOptions = .init()) async throws -> WriteResult { try await CodecSet.all.write(self, to: url, as: format, options: options) }
}

extension SlideReader {
    public init(data: Data, format: PresentationFormat? = nil, options: ReadOptions = .init()) throws {
        try self.init(data: data, codecs: .all, format: format, options: options)
    }
    public init(contentsOf url: URL, options: ReadOptions = .init()) throws {
        try self.init(contentsOf: url, codecs: .all, options: options)
    }
}
