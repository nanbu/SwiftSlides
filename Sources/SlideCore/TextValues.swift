import Foundation

/// percentageは100%=1。測定後の行高へ換算するのはレンダラーの責務。
public enum TextSpacing: Sendable, Equatable, Codable {
    case points(Double)
    case percentage(Double)
}

extension ParagraphStyle {
    public var effectiveLineSpacing: TextSpacing? { lineSpacingValue ?? lineSpacing.map(TextSpacing.percentage) }
    public var effectiveSpaceBefore: TextSpacing? { spaceBeforeValue ?? spaceBefore.map(TextSpacing.points) }
    public var effectiveSpaceAfter: TextSpacing? { spaceAfterValue ?? spaceAfter.map(TextSpacing.points) }
    /// 指定された属性だけで上書きする。明示的な0・false・noneも維持する。
    public func overlaying(_ direct: ParagraphStyle) -> ParagraphStyle {
        var result = self
        result.alignment = direct.alignment ?? alignment; result.level = direct.level ?? level
        result.leftMargin = direct.leftMargin ?? leftMargin; result.indent = direct.indent ?? indent
        result.bullet = direct.bullet ?? bullet
        if let value = direct.effectiveLineSpacing { result.lineSpacingValue = value; result.lineSpacing = nil }
        if let value = direct.effectiveSpaceBefore { result.spaceBeforeValue = value; result.spaceBefore = nil }
        if let value = direct.effectiveSpaceAfter { result.spaceAfterValue = value; result.spaceAfter = nil }
        return result
    }
}

/// 一段階の既定段落書式。継承前の直接値。
public struct TextStyleLevel: Sendable, Equatable, Codable {
    public var paragraph: ParagraphStyle
    public var text: TextStyle
    public init(paragraph: ParagraphStyle = .init(), text: TextStyle = .init()) { self.paragraph = paragraph; self.text = text }
}
public struct TextListStyle: Sendable, Equatable, Codable {
    public var defaultStyle: TextStyleLevel?
    /// 0から8の段落レベル。
    public var levels: [Int: TextStyleLevel]
    public init(defaultStyle: TextStyleLevel? = nil, levels: [Int: TextStyleLevel] = [:]) { self.defaultStyle = defaultStyle; self.levels = levels }
}

/// フィールドの原本キャッシュ。runの書式と段落内の境界はTextRunに保持する。
public struct TextField: Sendable, Equatable, Codable {
    public var id: String
    public var type: String
    public var cachedText: String
    public var paragraphStyle: TextStyleLevel?
    public init(id: String, type: String, cachedText: String, paragraphStyle: TextStyleLevel? = nil) {
        self.id = id; self.type = type; self.cachedText = cachedText; self.paragraphStyle = paragraphStyle
    }
}
public struct TextFieldContext: Sendable, Equatable, Codable {
    public var slideNumber: Int
    public var date: Date
    public var localeIdentifier: String
    public var timeZoneIdentifier: String
    public init(slideNumber: Int, date: Date, localeIdentifier: String, timeZoneIdentifier: String) {
        self.slideNumber = slideNumber; self.date = date; self.localeIdentifier = localeIdentifier; self.timeZoneIdentifier = timeZoneIdentifier
    }
}
public struct TextFieldEvaluation: Sendable, Equatable, Codable {
    public let text: String
    public let diagnostics: [SlideDiagnostic]
}
public enum TextFieldEvaluator {
    package static let supportedTypes: Set<String> = Set(["slidenum", "datetime", "datetimeFigureOut"] + (1...13).map { "datetime\($0)" })
    /// 評価は原本・モデルを変更しない。保存する更新は呼出側で明示する。
    public static func evaluate(_ field: TextField, context: TextFieldContext) -> TextFieldEvaluation {
        func fallback(_ reason: String) -> TextFieldEvaluation {
            .init(text: field.cachedText, diagnostics: [.init(code: "fieldNotEvaluated", feature: "TXT-020", stage: .read, action: .unresolved,
                location: .init(part: "", sourceElement: "fld"), message: reason)])
        }
        guard UUID(uuidString: field.id.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))) != nil, !field.type.isEmpty else { return fallback("不正なフィールドのキャッシュを使用します") }
        if field.type == "slidenum" { return .init(text: String(context.slideNumber), diagnostics: []) }
        let formats = ["datetime1":"MM/dd/yyyy", "datetime2":"EEEE, MMMM dd, yyyy", "datetime3":"dd MMMM yyyy",
            "datetime4":"MMMM dd, yyyy", "datetime5":"dd-MMM-yy", "datetime6":"MMMM yy", "datetime7":"MMM-yy",
            "datetime8":"MM/dd/yyyy h:mm a", "datetime9":"MM/dd/yyyy h:mm:ss a", "datetime10":"HH:mm",
            "datetime11":"HH:mm:ss", "datetime12":"h:mm a", "datetime13":"h:mm:ss a", "datetimeFigureOut":"MM/dd/yyyy"]
        guard field.type == "datetime" || formats[field.type] != nil else { return fallback("未知のフィールド種別のキャッシュを使用します: \(field.type)") }
        let locale = Locale(identifier: context.localeIdentifier)
        guard !context.localeIdentifier.isEmpty, locale.calendar.identifier == .gregorian,
              context.date.timeIntervalSince1970.isFinite, let zone = TimeZone(identifier: context.timeZoneIdentifier) else { return fallback("日時・言語・暦・タイムゾーンを評価できません") }
        let formatter = DateFormatter(); formatter.locale = locale; formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = zone
        if let format = formats[field.type] { formatter.dateFormat = format }
        else { formatter.dateStyle = .short; formatter.timeStyle = .short }
        return .init(text: formatter.string(from: context.date), diagnostics: [])
    }
}
extension Presentation {
    /// 非表示も含む現在の文書順。重複IDや整数overflowを拒否する。
    public func slideNumber(for id: String) throws -> Int {
        let indices = slides.indices.filter { slides[$0].id == id }
        guard indices.count == 1, let index = indices.first else { throw SlideError.invalidModel("番号対象のスライドIDが不在または重複しています") }
        let (number, overflow) = (firstSlideNumber ?? 1).addingReportingOverflow(index)
        guard !overflow else { throw SlideError.invalidModel("スライド番号の範囲外") }; return number
    }
}
