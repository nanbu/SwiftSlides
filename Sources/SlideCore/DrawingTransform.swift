import Foundation

/// 列優先の2D affine変換。translationの単位はpt。
public struct AffineTransform2D: Sendable, Equatable, Codable {
    public let a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double
    public init(a: Double = 1, b: Double = 0, c: Double = 0, d: Double = 1, tx: Double = 0, ty: Double = 0) { self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty }
    public static let identity = AffineTransform2D()
    public func applying(to p: PathPoint) -> PathPoint { .init(x: a * p.x + c * p.y + tx, y: b * p.x + d * p.y + ty) }
    /// selfを適用後にnextを適用する。
    public func followed(by n: AffineTransform2D) -> AffineTransform2D {
        .init(a: n.a * a + n.c * b, b: n.b * a + n.d * b, c: n.a * c + n.c * d, d: n.b * c + n.d * d, tx: n.a * tx + n.c * ty + n.tx, ty: n.b * tx + n.d * ty + n.ty)
    }
    public var isFinite: Bool { [a, b, c, d, tx, ty].allSatisfy(\.isFinite) }
}
public struct TransformOperation: Sendable, Equatable, Codable {
    public let name: String
    public let arguments: [Double]
    public let matrix: AffineTransform2D
    public init(name: String, arguments: [Double], matrix: AffineTransform2D) { self.name = name; self.arguments = arguments; self.matrix = matrix }
}
public final class DrawingTransform: Sendable, Equatable, Codable {
    public let rawValue: String
    public let operations: [TransformOperation]
    public let matrix: AffineTransform2D
    public init(rawValue: String, operations: [TransformOperation], matrix: AffineTransform2D) { self.rawValue = rawValue; self.operations = operations; self.matrix = matrix }
    public static func == (a: DrawingTransform, b: DrawingTransform) -> Bool { a === b || (a.rawValue == b.rawValue && a.operations == b.operations && a.matrix == b.matrix) }
}
/// ODF 1.4と主要producerはradians。1.2/1.3の旧規定に従う入力にはdegreesを指定する。
public enum ODFTransformAngleUnit: String, Sendable, Codable { case radians, degrees }
public struct CustomGeometryRequest: Sendable {
    public let engine: String
    public let source: SourceXMLNode
    public init(engine: String, source: SourceXMLNode) { self.engine = engine; self.source = source }
}
/// text-pathの配置指示。glyphの配置や文字計測は行わない。
public final class TextPathProperties: Sendable, Equatable, Codable {
    public let enabled: Bool?
    public let mode: String?
    public let scale: String?
    public let sameLetterHeights: Bool?
    public let rotateAngle: Double?
    public let source: SourceXMLNode
    public init(enabled: Bool? = nil, mode: String? = nil, scale: String? = nil, sameLetterHeights: Bool? = nil, rotateAngle: Double? = nil, source: SourceXMLNode) { self.enabled = enabled; self.mode = mode; self.scale = scale; self.sameLetterHeights = sameLetterHeights; self.rotateAngle = rotateAngle; self.source = source }
    public static func == (a: TextPathProperties, b: TextPathProperties) -> Bool { a === b || (a.enabled == b.enabled && a.mode == b.mode && a.scale == b.scale && a.sameLetterHeights == b.sameLetterHeights && a.rotateAngle == b.rotateAngle && a.source == b.source) }
}
