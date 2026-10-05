/// 表示文言によらず判定できる診断コード。未知コードも保持する。
public struct DiagnosticCode: RawRepresentable, Sendable, Hashable, Codable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: any Encoder) throws { var value = encoder.singleValueContainer(); try value.encode(rawValue) }
}

public enum DiagnosticStage: String, Sendable, Codable { case read, write }
public enum DiagnosticSeverity: String, Sendable, Codable { case information, warning, error }
/// 未解釈の原本保持と意味の解決・書換えを区別する。
public enum DiagnosticAction: String, Sendable, Codable {
    case preserved, unresolved, omitted, rewritten, retainedUnreferenced, unverified
}

/// 判明した位置だけを記録する。sourceElementはXML名等でありモデルIDではない。
public struct DiagnosticLocation: Sendable, Equatable, Codable {
    public var part: String
    public var sourceElement: String
    public var slideID: String?
    public var elementID: String?
    public init(part: String, sourceElement: String, slideID: String? = nil, elementID: String? = nil) {
        self.part = part; self.sourceElement = sourceElement; self.slideID = slideID; self.elementID = elementID
    }
}

/// 読み書きの警告を機能・位置・処理内容とともに示す。
public struct SlideDiagnostic: Sendable, Equatable, Codable {
    public var code: DiagnosticCode
    public var feature: FeatureID?
    public var severity: DiagnosticSeverity
    public var stage: DiagnosticStage
    public var action: DiagnosticAction
    public var location: DiagnosticLocation
    public var count: Int
    public var message: String
    public init(code: DiagnosticCode, feature: FeatureID? = nil, severity: DiagnosticSeverity = .warning,
                stage: DiagnosticStage, action: DiagnosticAction, location: DiagnosticLocation, count: Int = 1, message: String) {
        self.code = code; self.feature = feature; self.severity = severity; self.stage = stage; self.action = action
        self.location = location; self.count = count; self.message = message
    }
}

extension SlideWarning {
    /// 警告の文言やsourceElementから機能を推測せず、明示された位置を投影する。
    public func diagnostic(stage: DiagnosticStage) -> SlideDiagnostic {
        let action: DiagnosticAction
        switch code {
        case .unsupportedContent, .macrosPreserved: action = .preserved
        case .unsupportedPart: action = feature == "SEC-006" ? .unverified : .preserved
        case .uninterpretedFormatting: action = .unresolved
        case .notesOmitted: action = .omitted
        case .rewrittenContent: action = .rewritten
        case .orphanedParts: action = .retainedUnreferenced
        }
        return .init(code: .init(rawValue: code.rawValue), feature: feature, stage: stage, action: action,
                     location: .init(part: part, sourceElement: element, slideID: slideID, elementID: elementID),
                     count: count, message: message)
    }
}

extension Presentation {
    /// 読取時の警告。現在の編集内容に対する保存計画ではない。
    public var readDiagnostics: [SlideDiagnostic] { readWarnings.map { $0.diagnostic(stage: .read) } }
}
