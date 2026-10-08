import Foundation

public struct Vector3: Sendable, Equatable, Codable {
    public let x: Double
    public let y: Double
    public let z: Double
    public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }
}
/// ODFの3D要素。単位付き位置/長さはpt、方向は無次元、角度は度。
public final class SpatialGeometry: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable { case scene, cube, sphere, extrude, rotate, light, extrusion }
    public let kind: Kind
    public let vectors: [String: Vector3]
    public let values: [String: Double]
    public let flags: [String: Bool]
    public let tokens: [String: String]
    /// 原本の3D affine matrix。ODFの列優先12成分を維持する。
    public let matrix: [Double]?
    public let source: SourceXMLNode
    public init(kind: Kind, vectors: [String: Vector3] = [:], values: [String: Double] = [:], flags: [String: Bool] = [:], tokens: [String: String] = [:], matrix: [Double]? = nil, source: SourceXMLNode) { self.kind = kind; self.vectors = vectors; self.values = values; self.flags = flags; self.tokens = tokens; self.matrix = matrix; self.source = source }
    public static func == (a: SpatialGeometry, b: SpatialGeometry) -> Bool { a === b || (a.kind == b.kind && a.vectors == b.vectors && a.values == b.values && a.flags == b.flags && a.tokens == b.tokens && a.matrix == b.matrix && a.source == b.source) }
}
