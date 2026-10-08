import Foundation
@_exported import SwiftSlides

/// OOXML Agile/Standard・ODF AES・Keynote iwpv2の復号専用入口。入力は変更せず、結果は平文。
public func decrypt(_ data: Data, password: String, limits: PackageLimits = .init()) throws -> Data {
    try Task.checkCancellation()
    if data.prefix(8) == CompoundFile.signature {
        return try OOXMLEncryption.decrypt(data,password:password,limits:limits)
    }
    if data.prefix(2) == Data([0x50,0x4B]) {
        let archive = try PackageArchive(data,limits:limits)
        if archive.entries[".iwpv2"] != nil { return try KeynoteEncryption.decrypt(archive,password:password,limits:limits) }
        if archive.paths.contains(where: { $0 == ".iwpv2" || $0.hasSuffix("/.iwpv2") || $0 == ".iwph" || $0.hasSuffix("/.iwph") }) { throw SlideError.unsupportedEncryption(detail: "Keynote .iwpv2保護") }
        if archive.entries["mimetype"] != nil, String(data:try archive.read("mimetype"),encoding:.utf8) == "application/vnd.oasis.opendocument.presentation" {
            return try ODPEncryption.decrypt(archive,password:password,limits:limits) ?? data
        }
    }
    return data
}
@concurrent public func decrypt(_ data: Data, password: String, limits: PackageLimits = .init()) async throws -> Data { try decryptSync(data,password:password,limits:limits) }
private func decryptSync(_ data: Data, password: String, limits: PackageLimits) throws -> Data { try decrypt(data,password:password,limits:limits) }
public func decrypt(contentsOf url: URL, password: String, limits: PackageLimits = .init()) throws -> Data { try decrypt(PackageInput.read(url,limits:limits),password:password,limits:limits) }
@concurrent public func decrypt(contentsOf url: URL, password: String, limits: PackageLimits = .init()) async throws -> Data { try decryptSync(PackageInput.read(url,limits:limits),password:password,limits:limits) }

extension CodecSet {
    public func read(_ data: Data, password: String, format: PresentationFormat? = nil, options: ReadOptions = .init()) throws -> ReadResult {
        let plain = try decrypt(data,password:password,limits:options.limits)
        var result = try read(plain,format:format,options:options)
        if plain != data { result.presentation.addReadWarning(.init(code:.unsupportedContent,part:"",element:"encryption",message:"復号した原本を平文として保持します。通常保存は暗号化されません",feature:"SEC-001")) }
        if plain != data, result.presentation.sourceFormat == .keynote { result.presentation.addReadWarning(.init(code:.unsupportedContent,part:".iwpv2",element:"encryption",message:"Keynote暗号streamの末尾20bytesは未解釈です。暗号文全体の認証は保証しません",feature:"SEC-003")) }
        return result
    }
    public func inspect(_ data: Data, password: String, format: PresentationFormat? = nil, options: InspectOptions = .init()) throws -> PresentationSummary { try inspect(decrypt(data,password:password,limits:options.limits),format:format,options: options) }
    @concurrent public func read(_ data: Data, password: String, format: PresentationFormat? = nil, options: ReadOptions = .init()) async throws -> ReadResult { try readPasswordSync(data,password:password,format:format,options:options) }
    fileprivate func readPasswordSync(_ data: Data, password: String, format: PresentationFormat?, options: ReadOptions) throws -> ReadResult { try read(data,password:password,format:format,options:options) }
}
extension Presentation {
    public init(data: Data, password: String, format: PresentationFormat? = nil, options: ReadOptions = .init()) throws { self = try CodecSet.all.read(data,password:password,format:format,options:options).presentation }
    public init(contentsOf url: URL, password: String, format: PresentationFormat? = nil, options: ReadOptions = .init()) throws { try self.init(data:PackageInput.read(url,limits:options.limits),password:password,format:format,options:options) }
    public static func read(_ data: Data, password: String, format: PresentationFormat? = nil, options: ReadOptions = .init()) throws -> ReadResult { try CodecSet.all.read(data,password:password,format:format,options:options) }
    @concurrent public static func read(_ data: Data, password: String, format: PresentationFormat? = nil, options: ReadOptions = .init()) async throws -> ReadResult { try CodecSet.all.readPasswordSync(data,password:password,format:format,options:options) }
}
extension SlideReader {
    public init(data: Data, password: String, codecs: CodecSet = .all, format: PresentationFormat? = nil, options: ReadOptions = .init()) throws { try self.init(data:decrypt(data,password:password,limits:options.limits),codecs:codecs,format:format,options:options) }
    public init(contentsOf url: URL, password: String, codecs: CodecSet = .all, format: PresentationFormat? = nil, options: ReadOptions = .init()) throws { try self.init(data:PackageInput.read(url,limits:options.limits),password:password,codecs:codecs,format:format,options:options) }
}

extension CodecSet {
    public func read(contentsOf url:URL,password:String,format: PresentationFormat? = nil, options:ReadOptions = .init()) throws -> ReadResult { try read(PackageInput.read(url,limits:options.limits),password:password,format:format,options:options) }
    public func inspect(contentsOf url:URL,password:String,format: PresentationFormat? = nil, options: InspectOptions = .init()) throws -> PresentationSummary { try inspect(PackageInput.read(url,limits:options.limits),password:password,format:format,options: options) }
    @concurrent public func read(contentsOf url:URL,password:String,format: PresentationFormat? = nil, options:ReadOptions = .init()) async throws -> ReadResult { try readPasswordSync(PackageInput.read(url,limits:options.limits),password:password,format:format,options:options) }
    @concurrent public func inspect(_ data:Data,password:String,format:PresentationFormat? = nil,options: InspectOptions = .init()) async throws -> PresentationSummary { try inspectPasswordSync(data,password:password,format:format,options: options) }
    @concurrent public func inspect(contentsOf url:URL,password:String,format: PresentationFormat? = nil, options: InspectOptions = .init()) async throws -> PresentationSummary { try inspectPasswordSync(PackageInput.read(url,limits:options.limits),password:password,format:format,options: options) }
    fileprivate func inspectPasswordSync(_ data:Data,password:String,format:PresentationFormat?,options: InspectOptions) throws -> PresentationSummary { try inspect(data,password:password,format:format,options: options) }
    public func slideReader(_ data:Data,password:String,format:PresentationFormat? = nil,options:ReadOptions = .init()) throws -> SlideReader { try SlideReader(data:data,password:password,codecs:self,format:format,options:options) }
    @concurrent public func slideReader(_ data:Data,password:String,format:PresentationFormat? = nil,options:ReadOptions = .init()) async throws -> SlideReader { try SlideReader(data:data,password:password,codecs:self,format:format,options:options) }
    public func slideReader(contentsOf url:URL,password:String,format: PresentationFormat? = nil, options:ReadOptions = .init()) throws -> SlideReader { try SlideReader(contentsOf:url,password:password,codecs:self,format:format,options:options) }
    @concurrent public func slideReader(contentsOf url:URL,password:String,format: PresentationFormat? = nil, options:ReadOptions = .init()) async throws -> SlideReader { try SlideReader(contentsOf:url,password:password,codecs:self,format:format,options:options) }
}
extension Presentation {
    public static func read(contentsOf url:URL,password:String,format: PresentationFormat? = nil, options:ReadOptions = .init()) throws -> ReadResult { try CodecSet.all.read(contentsOf:url,password:password,format:format,options:options) }
    @concurrent public static func read(contentsOf url:URL,password:String,format: PresentationFormat? = nil, options:ReadOptions = .init()) async throws -> ReadResult { try CodecSet.all.readPasswordSync(PackageInput.read(url,limits:options.limits),password:password,format:format,options:options) }
    public static func inspect(_ data:Data,password:String,format:PresentationFormat? = nil,options: InspectOptions = .init()) throws -> PresentationSummary { try CodecSet.all.inspect(data,password:password,format:format,options: options) }
    @concurrent public static func inspect(_ data:Data,password:String,format:PresentationFormat? = nil,options: InspectOptions = .init()) async throws -> PresentationSummary { try CodecSet.all.inspectPasswordSync(data,password:password,format:format,options: options) }
    public static func inspect(contentsOf url:URL,password:String,format: PresentationFormat? = nil, options: InspectOptions = .init()) throws -> PresentationSummary { try CodecSet.all.inspect(contentsOf:url,password:password,format:format,options: options) }
    @concurrent public static func inspect(contentsOf url:URL,password:String,format: PresentationFormat? = nil, options: InspectOptions = .init()) async throws -> PresentationSummary { try CodecSet.all.inspectPasswordSync(PackageInput.read(url,limits:options.limits),password:password,format:format,options: options) }
}

/// 復号製品をリンクした場合の能力。通常codecの能力とは別に照会する。
public enum Decryption {
    public static func capabilities(for format:PresentationFormat) -> [FeatureCapability] { DecryptFeatureCapabilities.features(for:format) }
}
