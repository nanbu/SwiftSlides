import Foundation

/// ネイティブ式のpostfix token。node順と関数IDを維持し、別の式言語へ変換しない。
public struct FormulaToken: Sendable, Equatable, Codable {
    public let kind: String
    public let number: Double?
    public let text: String?
    public let boolean: Bool?
    public let functionID: UInt64?
    public let argumentCount: UInt64?
    public let row: Int?
    public let column: Int?
    public let absoluteRow: Bool?
    public let absoluteColumn: Bool?
    public var details: FormulaTokenDetails?
    public let source: Data
    public init(kind: String, number: Double? = nil, text: String? = nil, boolean: Bool? = nil, functionID: UInt64? = nil, argumentCount: UInt64? = nil, row: Int? = nil, column: Int? = nil, absoluteRow: Bool? = nil, absoluteColumn: Bool? = nil, source: Data) { self.kind = kind; self.number = number; self.text = text; self.boolean = boolean; self.functionID = functionID; self.argumentCount = argumentCount; self.row = row; self.column = column; self.absoluteRow = absoluteRow; self.absoluteColumn = absoluteColumn; self.source = source }
}
public final class CellFormula: Sendable, Equatable, Codable {
    public let dialect: String
    public let tokens: [FormulaToken]
    public let source: Data
    public let context: [String: NativeValue]?
    public init(dialect: String, tokens: [FormulaToken], source: Data, context: [String: NativeValue]? = nil) { self.dialect = dialect; self.tokens = tokens; self.source = source; self.context = context }
    public static func == (a: CellFormula, b: CellFormula) -> Bool { a === b || (a.dialect == b.dialect && a.tokens == b.tokens && a.source == b.source && a.context == b.context) }
}
