import Foundation

/// 対応候補の形式。odp/keynoteのコーデックは初期版では提供しない。
public enum PresentationFormat: String, Sendable, Codable { case pptx, pptm, odp, keynote }
/// 解析・保存が成功できない理由。
public enum SlideError: Error, Sendable, Equatable, CustomStringConvertible {
    case unknownFormat
    case noCodec(PresentationFormat)
    case unsupportedContainer(String)
    case corruptedPackage(String)
    case invalidXML(part: String, detail: String)
    case missingPart(String)
    case invalidRelationship(part: String, detail: String)
    case limitExceeded(String)
    case invalidModel(String)
    case unsafeEdit(String)
    public var description: String {
        switch self {
        case .unknownFormat: "プレゼンテーションの形式を判定できません。"
        case .noCodec(let f): "\(f.rawValue) のコーデックは登録されていません。"
        case .unsupportedContainer(let s): "未対応のコンテナ: \(s)"
        case .corruptedPackage(let s): "破損したパッケージ: \(s)"
        case .invalidXML(let p,let s): "XMLの解析失敗 (\(p)): \(s)"
        case .missingPart(let p): "パーツがありません: \(p)"
        case .invalidRelationship(let p,let s): "不正な参照 (\(p)): \(s)"
        case .limitExceeded(let s): "制限を超えました: \(s)"
        case .invalidModel(let s): "モデルが不正です: \(s)"
        case .unsafeEdit(let s): "安全に保存できない編集: \(s)"
        }
    }
}
/// 宣言サイズとXML解析量の上限。プロセスメモリ予算ではない。
public struct PackageLimits: Sendable {
    public var maxEntries: Int
    public var maxExpandedBytes: Int
    public var maxPartBytes: Int
    public var maxXMLDepth: Int
    public var maxXMLNodes: Int
    public init(maxEntries: Int = 10_000, maxExpandedBytes: Int = 512 << 20, maxPartBytes: Int = 128 << 20, maxXMLDepth: Int = 128, maxXMLNodes: Int = 2_000_000) {
        self.maxEntries = maxEntries; self.maxExpandedBytes = maxExpandedBytes; self.maxPartBytes = maxPartBytes; self.maxXMLDepth = maxXMLDepth; self.maxXMLNodes = maxXMLNodes
    }
}
public struct ReadOptions: Sendable {
    public var limits: PackageLimits
    public var includeNotes: Bool
    public init(limits: PackageLimits = .init(), includeNotes: Bool = true) { self.limits = limits; self.includeNotes = includeNotes }
}
/// 保存に伴う警告を許容するか。strictは変更に伴う警告があればthrow。
public struct WriteOptions: Sendable {
    public var strict: Bool
    public var compress: Bool
    public init(strict: Bool = false, compress: Bool = true) { self.strict = strict; self.compress = compress }
}
/// 機械的に判定できる警告。part/element単位に件数を集約する。
public struct SlideWarning: Sendable, Equatable, Codable {
    public enum Code: String, Sendable, Codable { case unsupportedContent, uninterpretedFormatting, unsupportedPart, notesOmitted, macrosPreserved, rewrittenContent, orphanedParts }
    public var code: Code
    public var part: String
    public var element: String
    public var message: String
    public var count: Int
    public init(code: Code, part: String, element: String, message: String, count: Int = 1) { self.code = code; self.part = part; self.element = element; self.message = message; self.count = count }
}
package final class WarningCollector {
    private var warnings: [SlideWarning] = []
    private var indices: [String: Int] = [:]
    package init() {}
    package func add(_ code: SlideWarning.Code, part: String, element: String, message: String) {
        let key = "\(code.rawValue)|\(part)|\(element)"
        if let i = indices[key] { warnings[i].count += 1 } else { indices[key] = warnings.count; warnings.append(.init(code: code, part: part, element: element, message: message)) }
    }
    package var result: [SlideWarning] { warnings }
}
public struct ReadResult: Sendable {
    public var presentation: Presentation
    public var warnings: [SlideWarning] { presentation.readWarnings }
    public init(presentation: Presentation) { self.presentation = presentation }
}
/// 保存結果のbytesと編集に伴う警告。
public struct WriteResult: Sendable {
    public var data: Data
    public var warnings: [SlideWarning]
    public init(data: Data, warnings: [SlideWarning] = []) { self.data = data; self.warnings = warnings }
}
/// 全スライド本文を読まずに取得する情報。
public struct PresentationSummary: Sendable, Codable {
    public var format: PresentationFormat
    public var size: Size
    public var slideCount: Int
    public var metadata: Metadata
    public var parts: [PackagePart]
    public var expandedBytes: Int { parts.reduce(0) { $0 + $1.expandedSize } }
    public init(format: PresentationFormat, size: Size, slideCount: Int, metadata: Metadata, parts: [PackagePart]) { self.format = format; self.size = size; self.slideCount = slideCount; self.metadata = metadata; self.parts = parts }
}
/// 一つの形式の同期的な読み取り・検査・保存契約。操作ごとに解析状態を所有する。
public protocol PresentationCodec: Sendable {
    var format: PresentationFormat { get }
    func read(_ data: Data, options: ReadOptions) throws -> ReadResult
    func inspect(_ data: Data, limits: PackageLimits) throws -> PresentationSummary
    func write(_ presentation: Presentation, options: WriteOptions) throws -> WriteResult
}
public struct Codec: Sendable {
    package var implementation: any PresentationCodec
    public init(_ implementation: any PresentationCodec) { self.implementation = implementation }
}
/// アプリがリンクする形式を明示的に選ぶ。
public struct CodecSet: Sendable {
    private let codecs: [PresentationFormat: any PresentationCodec]
    public init(_ codecs: [Codec]) { self.codecs = Dictionary(codecs.map { ($0.implementation.format, $0.implementation) }, uniquingKeysWith: { _, last in last }) }
    private func codec(_ format: PresentationFormat) throws -> any PresentationCodec { guard let c = codecs[format] else { throw SlideError.noCodec(format) }; return c }
    public func read(_ data: Data, format: PresentationFormat? = nil, options: ReadOptions = .init()) throws -> ReadResult { try codec(format ?? PresentationFormat.detect(data, limits: options.limits)).read(data, options: options) }
    public func read(contentsOf url: URL, options: ReadOptions = .init()) throws -> ReadResult { try read(Data(contentsOf: url, options: .mappedIfSafe), options: options) }
    public func inspect(_ data: Data, limits: PackageLimits = .init()) throws -> PresentationSummary { try codec(PresentationFormat.detect(data, limits: limits)).inspect(data, limits: limits) }
    public func inspect(contentsOf url: URL, limits: PackageLimits = .init()) throws -> PresentationSummary { try inspect(Data(contentsOf: url, options: .mappedIfSafe), limits: limits) }
    public func write(_ presentation: Presentation, as format: PresentationFormat? = nil, options: WriteOptions = .init()) throws -> WriteResult { try codec(format ?? presentation.sourceFormat ?? .pptx).write(presentation, options: options) }
    /// atomicでbytesを保存する。警告を戻り値に含める。
    @discardableResult public func write(_ presentation: Presentation, to url: URL, as format: PresentationFormat? = nil, options: WriteOptions = .init()) throws -> WriteResult { let result = try write(presentation, as: format, options: options); try result.data.write(to: url, options: .atomic); return result }
}
