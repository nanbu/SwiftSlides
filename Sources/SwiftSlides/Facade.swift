import Foundation
@_exported import SlideCore
@_exported import SlidePPTX

extension CodecSet {
    public static let all = CodecSet([.pptx, .pptm])
}
extension Presentation {
    public init(data: Data, options: ReadOptions = .init()) throws { self = try CodecSet.all.read(data,options:options).presentation }
    public init(contentsOf url: URL, options: ReadOptions = .init()) throws { self = try CodecSet.all.read(contentsOf:url,options:options).presentation }
    public static func read(_ data: Data, options: ReadOptions = .init()) throws -> ReadResult { try CodecSet.all.read(data,options:options) }
    public static func read(contentsOf url: URL, options: ReadOptions = .init()) throws -> ReadResult { try CodecSet.all.read(contentsOf:url,options:options) }
    public static func inspect(_ data: Data, limits: PackageLimits = .init()) throws -> PresentationSummary { try CodecSet.all.inspect(data,limits:limits) }
    public static func inspect(contentsOf url: URL, limits: PackageLimits = .init()) throws -> PresentationSummary { try CodecSet.all.inspect(contentsOf:url,limits:limits) }
    public func data(as format: PresentationFormat? = nil, options: WriteOptions = .init()) throws -> Data { try CodecSet.all.write(self,as:format,options:options).data }
    public func encoded(as format: PresentationFormat? = nil, options: WriteOptions = .init()) throws -> WriteResult { try CodecSet.all.write(self,as:format,options:options) }
    @discardableResult public func write(to url: URL, as format: PresentationFormat? = nil, options: WriteOptions = .init()) throws -> WriteResult { try CodecSet.all.write(self,to:url,as:format,options:options) }
}
