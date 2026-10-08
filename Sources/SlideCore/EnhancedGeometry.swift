import Foundation

/// 独自座標領域の数値、modifier添字、guide参照。式を評価した値ではない。
public enum GeometryOperand: Sendable, Equatable, Codable {
    case number(Double), modifier(Int), formula(String)
}

/// ODF enhanced pathの一命令と全引数。反復は引数列内の組で区別する。
public struct EnhancedPathCommand: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        case move = "M", line = "L", cubic = "C", quadratic = "Q", close = "Z", end = "N"
        case noFill = "F", noStroke = "S", arcTo = "A", arc = "B"
        case angleEllipseTo = "T", angleEllipse = "U", clockwiseArc = "V", clockwiseArcTo = "W"
        case ellipticalQuadrantX = "X", ellipticalQuadrantY = "Y"
    }
    public let kind: Kind
    public let arguments: [GeometryOperand]
    public init(kind: Kind, arguments: [GeometryOperand] = []) { self.kind = kind; self.arguments = arguments }
}

/// 四辺を独自座標領域のoperandで保持する。文字計測・配置結果ではない。
public struct EnhancedTextArea: Sendable, Equatable, Codable {
    public let left: GeometryOperand
    public let top: GeometryOperand
    public let right: GeometryOperand
    public let bottom: GeometryOperand
    public init(left: GeometryOperand, top: GeometryOperand, right: GeometryOperand, bottom: GeometryOperand) {
        self.left = left; self.top = top; self.right = right; self.bottom = bottom
    }
}

/// 読取専用のODF高度図形。nilのpathは省略または未解決。字句と全属性はsourceに保持する。
public struct EnhancedGeometry: Sendable, Equatable, Codable {
    private struct Value: Sendable, Equatable, Codable {
        let shapeType: String?
        let viewBox: Rect?
        let modifiers: [Double]?
        let equations: [GeometryGuide]
        let path: [EnhancedPathCommand]?
        let textAreas: [EnhancedTextArea]?
        let mirrorHorizontal: Bool?
        let mirrorVertical: Bool?
        let handles: [SourceXMLNode]
        let source: SourceXMLNode
    }
    private final class Storage: Sendable {
        let value: Value
        init(_ value: Value) { self.value = value }
    }
    private let storage: Storage
    public var shapeType: String? { storage.value.shapeType }
    public var viewBox: Rect? { storage.value.viewBox }
    public var modifiers: [Double]? { storage.value.modifiers }
    public var equations: [GeometryGuide] { storage.value.equations }
    public var path: [EnhancedPathCommand]? { storage.value.path }
    public var textAreas: [EnhancedTextArea]? { storage.value.textAreas }
    public var mirrorHorizontal: Bool? { storage.value.mirrorHorizontal }
    public var mirrorVertical: Bool? { storage.value.mirrorVertical }
    public var handles: [SourceXMLNode] { storage.value.handles }
    public var source: SourceXMLNode { storage.value.source }
    public init(shapeType: String? = nil, viewBox: Rect? = nil, modifiers: [Double]? = nil,
                equations: [GeometryGuide] = [], path: [EnhancedPathCommand]? = nil, textAreas: [EnhancedTextArea]? = nil,
                mirrorHorizontal: Bool? = nil, mirrorVertical: Bool? = nil, handles: [SourceXMLNode] = [], source: SourceXMLNode) {
        storage = Storage(.init(shapeType: shapeType, viewBox: viewBox, modifiers: modifiers, equations: equations,
                                path: path, textAreas: textAreas, mirrorHorizontal: mirrorHorizontal, mirrorVertical: mirrorVertical,
                                handles: handles, source: source))
    }
    public init(from decoder: any Decoder) throws { storage = try Storage(Value(from: decoder)) }
    public func encode(to encoder: any Encoder) throws { try storage.value.encode(to: encoder) }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.storage === rhs.storage || lhs.storage.value == rhs.storage.value }
}
