import Foundation

/// DrawingMLの直接回転。角度は度、省略はnil。
public struct Rotation3D: Sendable, Equatable, Codable {
    public let latitude: Double?
    public let longitude: Double?
    public let revolution: Double?
    public init(latitude: Double? = nil, longitude: Double? = nil, revolution: Double? = nil) {
        self.latitude = latitude; self.longitude = longitude; self.revolution = revolution
    }
}
/// 図形の3D scene直接値。透視変換・継承・描画は行わない。
public struct Scene3D: Sendable, Equatable, Codable {
    private struct Value: Sendable, Equatable, Codable {
        let cameraPreset: String
        let fieldOfView: Double?
        let zoom: Double?
        let cameraRotation: Rotation3D?
        let lightRig: String
        let lightDirection: String
        let lightRotation: Rotation3D?
        let source: SourceXMLNode
    }
    private final class Storage: Sendable { let value: Value; init(_ value: Value) { self.value = value } }
    private let storage: Storage
    public var cameraPreset: String { storage.value.cameraPreset }
    public var fieldOfView: Double? { storage.value.fieldOfView }
    public var zoom: Double? { storage.value.zoom }
    public var cameraRotation: Rotation3D? { storage.value.cameraRotation }
    public var lightRig: String { storage.value.lightRig }
    public var lightDirection: String { storage.value.lightDirection }
    public var lightRotation: Rotation3D? { storage.value.lightRotation }
    public var source: SourceXMLNode { storage.value.source }
    public init(cameraPreset: String, fieldOfView: Double? = nil, zoom: Double? = nil, cameraRotation: Rotation3D? = nil,
                lightRig: String, lightDirection: String, lightRotation: Rotation3D? = nil, source: SourceXMLNode) {
        storage = Storage(.init(cameraPreset: cameraPreset, fieldOfView: fieldOfView, zoom: zoom, cameraRotation: cameraRotation, lightRig: lightRig, lightDirection: lightDirection, lightRotation: lightRotation, source: source))
    }
    public init(from decoder: any Decoder) throws { storage = try Storage(Value(from: decoder)) }
    public func encode(to encoder: any Encoder) throws { try storage.value.encode(to: encoder) }
    public static func == (a: Self, b: Self) -> Bool { a.storage === b.storage || a.storage.value == b.storage.value }
}
/// bevelの直接指定。幅・高さはpt。
public struct Bevel3D: Sendable, Equatable, Codable {
    public let width: Double?
    public let height: Double?
    public let preset: String?
    public init(width: Double? = nil, height: Double? = nil, preset: String? = nil) { self.width = width; self.height = height; self.preset = preset }
}
/// 図形の3D直接値。寸法はpt、省略はnil。未知内容はsourceを参照する。
public struct Shape3D: Sendable, Equatable, Codable {
    private struct Value: Sendable, Equatable, Codable {
        let depth: Double?
        let extrusionHeight: Double?
        let contourWidth: Double?
        let material: String?
        let topBevel: Bevel3D?
        let bottomBevel: Bevel3D?
        let extrusionColor: Color?
        let contourColor: Color?
        let source: SourceXMLNode
    }
    private final class Storage: Sendable { let value: Value; init(_ value: Value) { self.value = value } }
    private let storage: Storage
    public var depth: Double? { storage.value.depth }
    public var extrusionHeight: Double? { storage.value.extrusionHeight }
    public var contourWidth: Double? { storage.value.contourWidth }
    public var material: String? { storage.value.material }
    public var topBevel: Bevel3D? { storage.value.topBevel }
    public var bottomBevel: Bevel3D? { storage.value.bottomBevel }
    public var extrusionColor: Color? { storage.value.extrusionColor }
    public var contourColor: Color? { storage.value.contourColor }
    public var source: SourceXMLNode { storage.value.source }
    public init(depth: Double? = nil, extrusionHeight: Double? = nil, contourWidth: Double? = nil, material: String? = nil,
                topBevel: Bevel3D? = nil, bottomBevel: Bevel3D? = nil, extrusionColor: Color? = nil, contourColor: Color? = nil, source: SourceXMLNode) {
        storage = Storage(.init(depth: depth, extrusionHeight: extrusionHeight, contourWidth: contourWidth, material: material, topBevel: topBevel, bottomBevel: bottomBevel, extrusionColor: extrusionColor, contourColor: contourColor, source: source))
    }
    public init(from decoder: any Decoder) throws { storage = try Storage(Value(from: decoder)) }
    public func encode(to encoder: any Encoder) throws { try storage.value.encode(to: encoder) }
    public static func == (a: Self, b: Self) -> Bool { a.storage === b.storage || a.storage.value == b.storage.value }
}
