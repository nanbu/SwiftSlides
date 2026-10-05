import Foundation

/// 対応候補の形式。Keynoteのコーデックは未提供。ODPは読取専用。
public enum PresentationFormat: String, Sendable, Codable {
    case pptx, pptm, odp, keynote

    /// 標準拡張子。対応codecの有無とは独立した形式名。
    public var fileExtension: String { self == .keynote ? "key" : rawValue }
    public init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "pptx": self = .pptx
        case "pptm": self = .pptm
        case "odp": self = .odp
        case "key": self = .keynote
        default: return nil
        }
    }
}
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
    case slideNotFound(id: String)
    case elementNotFound(id: String)
    case outputFormatMismatch(format: PresentationFormat, fileExtension: String)
    case unsafeEdit(String)
    case stalePlan
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
        case .slideNotFound(let id): "スライドがありません: \(id)"
        case .elementNotFound(let id): "要素がありません: \(id)"
        case .outputFormatMismatch(let format, let ext): "保存形式 \(format.rawValue) と保存先の拡張子 .\(ext) が一致しません。"
        case .unsafeEdit(let s): "安全に保存できない編集: \(s)"
        case .stalePlan: "保存計画の作成後に原本・モデル・保存条件・コーデック登録が変わりました。再計画してください。"
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
    public var maxTableCells: Int
    public init(maxEntries: Int = 10_000, maxExpandedBytes: Int = 512 << 20, maxPartBytes: Int = 128 << 20, maxXMLDepth: Int = 128, maxXMLNodes: Int = 2_000_000, maxTableCells: Int = 1_000_000) {
        self.maxEntries = maxEntries; self.maxExpandedBytes = maxExpandedBytes; self.maxPartBytes = maxPartBytes; self.maxXMLDepth = maxXMLDepth; self.maxXMLNodes = maxXMLNodes; self.maxTableCells = maxTableCells
    }
}
public struct ReadOptions: Sendable {
    public var limits: PackageLimits
    public var includeNotes: Bool
    public init(limits: PackageLimits = .init(), includeNotes: Bool = true) { self.limits = limits; self.includeNotes = includeNotes }
}
/// 保存に伴う警告を許容するか。strictは変更に伴う警告があればthrow。
public struct WriteOptions: Sendable, Equatable, Codable {
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
    public var feature: FeatureID?
    public var slideID: String?
    public var elementID: String?
    public init(code: Code, part: String, element: String, message: String, count: Int = 1,
                feature: FeatureID? = nil, slideID: String? = nil, elementID: String? = nil) {
        self.code = code; self.part = part; self.element = element; self.message = message; self.count = count
        self.feature = feature; self.slideID = slideID; self.elementID = elementID
    }
}
package final class WarningCollector {
    private struct Key: Hashable {
        let code: SlideWarning.Code
        let part: String
        let element: String
        let feature: FeatureID?
        let slideID: String?
        let elementID: String?
    }
    private var warnings: [SlideWarning] = []
    private var indices: [Key: Int] = [:]
    package init() {}
    package func add(_ code: SlideWarning.Code, part: String, element: String, message: String,
                     feature: FeatureID? = nil, slideID: String? = nil, elementID: String? = nil) {
        let key = Key(code: code, part: part, element: element, feature: feature, slideID: slideID, elementID: elementID)
        if let i = indices[key] { warnings[i].count += 1 } else {
            indices[key] = warnings.count
            warnings.append(.init(code: code, part: part, element: element, message: message,
                                  feature: feature, slideID: slideID, elementID: elementID))
        }
    }
    package var result: [SlideWarning] { warnings }
}
public struct ReadResult: Sendable {
    public var presentation: Presentation
    public var warnings: [SlideWarning] { presentation.readWarnings }
    public var preservationSummary: PreservationSummary { presentation.preservationSummary }
    public var diagnostics: [SlideDiagnostic] { presentation.readDiagnostics }
    public init(presentation: Presentation) { self.presentation = presentation }
}
/// 保存結果のbytesと編集に伴う警告。
public struct WriteResult: Sendable {
    public var data: Data
    public var warnings: [SlideWarning]
    public var diagnostics: [SlideDiagnostic] { warnings.map { $0.diagnostic(stage: .write) } }
    public init(data: Data, warnings: [SlideWarning] = []) { self.data = data; self.warnings = warnings }
}
/// 全スライドをモデル化せずに取得する情報。
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
/// writeの設定を変更するときは新しいCodec値へ登録し直す。同じ選択内の共有状態の変化はSavePlanで追跡しない。
public protocol PresentationCodec: Sendable {
    var format: PresentationFormat { get }
    var capabilities: CodecCapabilities { get }
    func read(_ data: Data, options: ReadOptions) throws -> ReadResult
    func inspect(_ data: Data, limits: PackageLimits) throws -> PresentationSummary
    func write(_ presentation: Presentation, options: WriteOptions) throws -> WriteResult
}
extension PresentationCodec {
    /// 従来の第三者codecは能力を宣言しなくても利用できる。
    public var capabilities: CodecCapabilities { .init(format: format) }
}
public struct Codec: Sendable {
    package let implementation: any PresentationCodec
    package let identity = UUID()
    public var format: PresentationFormat { implementation.format }
    public init(_ implementation: any PresentationCodec) { self.implementation = implementation }
}
/// アプリがリンクする形式を明示的に選ぶ。
public struct CodecSet: Sendable {
    private let codecs: [PresentationFormat: Codec]
    /// 最初の登録順。再登録では実装だけを置き換える。
    public let formats: [PresentationFormat]
    public init(_ codecs: [Codec]) {
        var implementations: [PresentationFormat: Codec] = [:]
        var formats: [PresentationFormat] = []
        for codec in codecs {
            if implementations.updateValue(codec, forKey: codec.format) == nil { formats.append(codec.format) }
        }
        self.codecs = implementations
        self.formats = formats
    }
    public func contains(_ format: PresentationFormat) -> Bool { codecs[format] != nil }
    public func codec(for format: PresentationFormat) throws -> Codec {
        guard let codec = codecs[format] else { throw SlideError.noCodec(format) }
        return codec
    }
    package func codec(_ format: PresentationFormat) throws -> any PresentationCodec { try codec(for: format).implementation }
    public func capabilities(for format: PresentationFormat) throws -> CodecCapabilities { try codec(format).capabilities }
    public func read(_ data: Data, format: PresentationFormat? = nil, options: ReadOptions = .init()) throws -> ReadResult { try readSync(data, format: format, options: options) }
    public func read(contentsOf url: URL, options: ReadOptions = .init()) throws -> ReadResult { try readURLSync(url, options: options) }
    public func inspect(_ data: Data, format: PresentationFormat? = nil, limits: PackageLimits = .init()) throws -> PresentationSummary { try inspectSync(data, format: format, limits: limits) }
    public func inspect(contentsOf url: URL, limits: PackageLimits = .init()) throws -> PresentationSummary { try inspectURLSync(url, limits: limits) }
    public func write(_ presentation: Presentation, as format: PresentationFormat? = nil, options: WriteOptions = .init()) throws -> WriteResult { try writeSync(presentation, format: format, options: options) }
    /// atomicでbytesを保存する。警告を戻り値に含める。
    public func write(_ presentation: Presentation, to url: URL, as format: PresentationFormat? = nil, options: WriteOptions = .init()) throws -> WriteResult { try writeURLSync(presentation, to: url, format: format, options: options) }

    /// 呼出元Actorを占有せず解析する。キャンセルは協調的。
    @concurrent public func read(_ data: Data, format: PresentationFormat? = nil, options: ReadOptions = .init()) async throws -> ReadResult { try readSync(data, format: format, options: options) }
    @concurrent public func read(contentsOf url: URL, options: ReadOptions = .init()) async throws -> ReadResult { try readURLSync(url, options: options) }
    @concurrent public func inspect(_ data: Data, format: PresentationFormat? = nil, limits: PackageLimits = .init()) async throws -> PresentationSummary { try inspectSync(data, format: format, limits: limits) }
    @concurrent public func inspect(contentsOf url: URL, limits: PackageLimits = .init()) async throws -> PresentationSummary { try inspectURLSync(url, limits: limits) }
    @concurrent public func write(_ presentation: Presentation, as format: PresentationFormat? = nil, options: WriteOptions = .init()) async throws -> WriteResult { try writeSync(presentation, format: format, options: options) }
    /// 一時fileへの分割書込境界とatomic確定直前にキャンセル確認。確定後には確認しない。
    @concurrent public func write(_ presentation: Presentation, to url: URL, as format: PresentationFormat? = nil, options: WriteOptions = .init()) async throws -> WriteResult { try writeURLSync(presentation, to: url, format: format, options: options) }
    @concurrent public func readAll(contentsOf urls: [URL], options: ReadOptions = .init(), maxConcurrentReads: Int = 4) async throws -> [ReadResult] {
        try await boundedMap(urls, maxConcurrent: maxConcurrentReads) { url in
            try await self.read(contentsOf: url, options: options)
        }
    }

    private func readSync(_ data: Data, format: PresentationFormat?, options: ReadOptions) throws -> ReadResult {
        try Task.checkCancellation()
        let result = try codec(format ?? PresentationFormat.detect(data, limits: options.limits)).read(data, options: options)
        try Task.checkCancellation(); return result
    }
    private func readURLSync(_ url: URL, options: ReadOptions) throws -> ReadResult {
        try Task.checkCancellation()
        return try readSync(Data(contentsOf: url, options: .mappedIfSafe), format: nil, options: options)
    }
    private func inspectSync(_ data: Data, format: PresentationFormat?, limits: PackageLimits) throws -> PresentationSummary {
        try Task.checkCancellation()
        let result = try codec(format ?? PresentationFormat.detect(data, limits: limits)).inspect(data, limits: limits)
        try Task.checkCancellation(); return result
    }
    private func inspectURLSync(_ url: URL, limits: PackageLimits) throws -> PresentationSummary {
        try Task.checkCancellation()
        return try inspectSync(Data(contentsOf: url, options: .mappedIfSafe), format: nil, limits: limits)
    }
    private func writeSync(_ presentation: Presentation, format: PresentationFormat?, options: WriteOptions) throws -> WriteResult {
        try Task.checkCancellation()
        let result = try codec(format ?? presentation.sourceFormat ?? .pptx).write(presentation, options: options)
        try Task.checkCancellation(); return result
    }
    private func writeURLSync(_ presentation: Presentation, to url: URL, format: PresentationFormat?, options: WriteOptions) throws -> WriteResult {
        try Task.checkCancellation()
        let destination = format ?? presentation.sourceFormat ?? .pptx
        try validateDestination(url, format: destination)
        let result = try writeSync(presentation, format: destination, options: options)
        try Task.checkCancellation()
        try FileTarget(url).write(result.data)
        return result
    }
}

/// 保存入口共通の検査。拡張子から暗黙の変換をしない。
package func validateDestination(_ url: URL, format: PresentationFormat) throws {
    if let named = PresentationFormat(fileExtension: url.pathExtension), named != format {
        throw SlideError.outputFormatMismatch(format: format, fileExtension: url.pathExtension)
    }
}
