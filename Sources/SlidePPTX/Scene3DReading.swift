import Foundation
import SlideCore

extension PPTXReader {
    private func dimension3D(_ node: MarkupNode, _ name: String, part: String, nonnegative: Bool = true) throws -> Double? {
        guard let raw = node.attr(name) else { return nil }
        guard let number = Int64(raw), !nonnegative || number >= 0 else { throw SlideError.corruptedPackage("不正な3D寸法\(name): \(part)") }
        return Double(number) / 12_700
    }
    private func angle3D(_ node: MarkupNode, _ name: String, part: String) throws -> Double? {
        guard let raw = node.attr(name) else { return nil }
        guard let number = UInt32(raw), number < 21_600_000 else { throw SlideError.corruptedPackage("不正な3D角度\(name): \(part)") }
        return Double(number) / 60_000
    }
    private func rotation3D(_ node: MarkupNode?, part: String) throws -> Rotation3D? {
        guard let node else { return nil }
        return try .init(latitude: angle3D(node, "lat", part: part), longitude: angle3D(node, "lon", part: part), revolution: angle3D(node, "rev", part: part))
    }
    func scene3D(_ node: MarkupNode?, part: String) throws -> Scene3D? {
        guard let node else { return nil }
        guard node.children.filter({ $0.isA && $0.name == "camera" }).count == 1,
              node.children.filter({ $0.isA && $0.name == "lightRig" }).count == 1 else { throw SlideError.corruptedPackage("3D sceneのcamera/lightRigが不在または重複: \(part)") }
        guard let camera = drawingChild(node, "camera"), let preset = camera.attr("prst"), !preset.isEmpty,
              let light = drawingChild(node, "lightRig"), let rig = light.attr("rig"), !rig.isEmpty, let direction = light.attr("dir"), !direction.isEmpty else {
            throw SlideError.corruptedPackage("3D sceneのcamera/lightRigが不正: \(part)")
        }
        let zoom: Double?
        if let raw = camera.attr("zoom") {
            guard let number = percentage(raw), number.isFinite, number >= 0 else { throw SlideError.corruptedPackage("不正な3D zoom: \(part)") }; zoom = number
        } else { zoom = nil }
        let fieldOfView = try angle3D(camera, "fov", part: part)
        guard fieldOfView.map({ $0 <= 180 }) ?? true else { throw SlideError.corruptedPackage("3D FOVが範囲外: \(part)") }
        warn(part, node, .uninterpretedFormatting, "3D sceneの直接camera/lightを読みます。継承・透視変換・描画は行いません", feature: "GEO-012")
        return try .init(cameraPreset: preset, fieldOfView: fieldOfView, zoom: zoom,
                         cameraRotation: rotation3D(drawingChild(camera, "rot"), part: part), lightRig: rig, lightDirection: direction,
                         lightRotation: rotation3D(drawingChild(light, "rot"), part: part), source: SourceXMLNode(node))
    }
    func shape3D(_ node: MarkupNode?, part: String) throws -> Shape3D? {
        guard let node else { return nil }
        func bevel(_ node: MarkupNode?) throws -> Bevel3D? {
            guard let node else { return nil }
            return try .init(width: dimension3D(node, "w", part: part), height: dimension3D(node, "h", part: part), preset: node.attr("prst"))
        }
        warn(part, node, .uninterpretedFormatting, "3D図形の直接寸法・bevel・材質・色を読みます。既定値・描画は補いません", feature: "GEO-012")
        return try .init(depth: dimension3D(node, "z", part: part, nonnegative: false), extrusionHeight: dimension3D(node, "extrusionH", part: part),
                         contourWidth: dimension3D(node, "contourW", part: part), material: node.attr("prstMaterial"),
                         topBevel: bevel(drawingChild(node, "bevelT")), bottomBevel: bevel(drawingChild(node, "bevelB")),
                         extrusionColor: color(drawingChild(node, "extrusionClr"), part: part), contourColor: color(drawingChild(node, "contourClr"), part: part),
                         source: SourceXMLNode(node))
    }
}
