import Foundation

/// 数式の構造。OMMLの引数wrapperとMathMLの位置による引数を原本順に保つ。
public struct EquationNode: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        case math, paragraph, run, text, fraction, numerator, denominator, radical, degree, base
        case superscript, subscriptExpression, subSuperscript, preSubSuperscript, subscriptArgument, superscriptArgument
        case nary, delimiter, matrix, matrixRow, equationArray, function, functionName
        case accent, bar, groupCharacter, lowerLimit, upperLimit, limit, box, borderBox, phantom
        case properties, property, native
        case application, binding, boundVariable, qualifier, contentSymbol, contentOperator, contentConstant
        case lambda, set, list, interval, vector, piecewise, piece, otherwise, declaration, share, separator
        case identifier, number, operatorToken, stringLiteral, row, style, space, padded, enclosed
        case tableCell, under, over, underOver, multiscripts, prescripts, none, semantics, annotation, action, error
    }
    public let kind: Kind
    public let name: String
    public let namespace: String
    public let attributes: [String: String]
    /// OMMLのtextまたはMathML tokenの字句値。未知ノードの混在内容はEquation.sourceで取得する。
    public let text: String?
    /// cnの有理数/複素数/e-notationなどのsepで区切られた字句。
    public let tokenParts: [String]?
    public let children: [EquationNode]
    public init(kind: Kind, name: String, namespace: String, attributes: [String: String] = [:], text: String? = nil, tokenParts: [String]? = nil, children: [EquationNode] = []) {
        self.kind = kind; self.name = name; self.namespace = namespace; self.attributes = attributes; self.text = text; self.tokenParts = tokenParts; self.children = children
    }
    /// apply/bindの先頭にある関数または演算子。未知の内容辞書も元の記号を返す。
    public var appliedOperator: EquationNode? { [.application, .binding].contains(kind) ? children.first : nil }
    public var boundVariables: [EquationNode] { children.filter { $0.kind == .boundVariable } }
    /// 式の構造を線形式へ変換せずtokenを連結する。注釈は含めない。
    public var lexicalText: String {
        guard kind != .annotation else { return "" }
        let token = [.text, .identifier, .number, .operatorToken, .stringLiteral].contains(kind)
        return (token ? text ?? "" : "") + children.map(\.lexicalText).joined()
    }
}
/// 読取専用の数式。sourceはAlternateContentの未選択分岐・未知書式も保持する。
public struct Equation: Sendable, Equatable, Codable {
    public enum Dialect: String, Sendable, Codable { case omml, mathML }
    private struct Value: Sendable, Equatable, Codable {
        let dialect: Dialect
        let root: EquationNode
        let source: SourceXMLNode
        let part: String
    }
    private final class Storage: Sendable {
        let value: Value
        init(_ value: Value) { self.value = value }
    }
    // 原本を含む大きな値をElement/TextRunのstack frameへ展開しない。不変snapshotを共有する。
    private let storage: Storage
    public var dialect: Dialect { storage.value.dialect }
    public var root: EquationNode { storage.value.root }
    public var source: SourceXMLNode { storage.value.source }
    public var part: String { storage.value.part }
    public init(dialect: Dialect = .omml, root: EquationNode, source: SourceXMLNode, part: String) {
        storage = Storage(.init(dialect: dialect, root: root, source: source, part: part))
    }
    public init(from decoder: any Decoder) throws { storage = try Storage(Value(from: decoder)) }
    public func encode(to encoder: any Encoder) throws { try storage.value.encode(to: encoder) }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.storage === rhs.storage || lhs.storage.value == rhs.storage.value }
    public var lexicalText: String { root.lexicalText }
}
