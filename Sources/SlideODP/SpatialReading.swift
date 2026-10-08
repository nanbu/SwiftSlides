import Foundation
import SlideCore

private let dr3d = "urn:oasis:names:tc:opendocument:xmlns:dr3d:1.0"
extension ODPPageParser {
    func spatialGeometry(_ node: MarkupNode, extrusion: Bool = false) throws -> SpatialGeometry {
        guard let kind = SpatialGeometry.Kind(rawValue: extrusion ? "extrusion" : node.name) else { throw SlideError.corruptedPackage("未知のODF 3D要素") }
        var attrs = node.attributes
        if let style = node.odf(ODF.draw, "style-name") { let inherited = try styles.resolve(name: style, family: "graphic").properties; attrs.merge(inherited) { direct, _ in direct } }
        func scalar(_ raw: String) throws -> Double {
            if let n = Double(raw), n.isFinite { return n }
            if raw.hasSuffix("%"), let n = Double(raw.dropLast()), n.isFinite { return n / 100 }
            return try ODF.length(raw)
        }
        func components(_ raw: String) -> [String] { raw.trimmingCharacters(in: CharacterSet(charactersIn: "() ")).split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init) }
        var vectors: [String: Vector3] = [:], values: [String: Double] = [:], flags: [String: Bool] = [:], tokens: [String: String] = [:], matrix: [Double]?
        let vectorNames = Set(["vrp", "vpn", "vup", "min-edge", "max-edge", "center", "size", "direction", "extrusion-viewpoint", "extrusion-first-light-direction", "extrusion-second-light-direction", "extrusion-rotation-center"])
        let scalarNames = Set(["distance", "focal-length", "shadow-slant", "depth", "back-scale", "end-angle", "horizontal-segments", "vertical-segments", "edge-rounding", "shininess", "extrusion-brightness", "extrusion-diffusion", "extrusion-first-light-level", "extrusion-second-light-level", "extrusion-shininess", "extrusion-specularity", "extrusion-number-of-line-segments"])
        let flagNames = Set(["enabled", "specular", "lighting-mode", "double-sided", "close-front", "close-back", "extrusion", "extrusion-color", "extrusion-first-light-harsh", "extrusion-second-light-harsh", "extrusion-light-face", "extrusion-metal"])
        for (key, raw) in attrs where key.hasPrefix(dr3d + "|") || key.hasPrefix(ODF.draw + "|extrusion") {
            let name = String(key.split(separator: "|").last!)
            if vectorNames.contains(name) {
                let parts = components(raw); guard parts.count == 3 else { throw SlideError.corruptedPackage("ODF 3D vector引数数: \(name)") }
                let n = try parts.map(scalar); vectors[name] = .init(x: n[0], y: n[1], z: n[2])
            } else if scalarNames.contains(name) { values[name] = try scalar(raw) }
            else if flagNames.contains(name) {
                guard ["true", "false", "1", "0"].contains(raw) else { throw SlideError.corruptedPackage("ODF 3D真偽値: \(name)") }; flags[name] = raw == "true" || raw == "1"
            }
            else if name == "transform" {
                matrix = try ODPTransformReader.read3D(raw,maxOperations:options.limits.maxXMLNodes).values
            } else { tokens[name] = raw }
        }
        return try .init(kind: kind, vectors: vectors, values: values, flags: flags, tokens: tokens, matrix: matrix, source: SourceXMLNode(node))
    }
    func spatialElement(_ node: MarkupNode, id: String, name: String) throws -> Element? {
        guard node.namespace == dr3d else { return nil }
        guard SpatialGeometry.Kind(rawValue: node.name) != nil else { return nil }
        var e = Element(id: id, name: name, kind: node.name == "scene" ? .group : .shape, geometry: nil)
        e.spatialGeometry = try spatialGeometry(node); e.sourceProperties = try SourceXMLNode(node)
        if node.name == "scene" { e.children = try node.children.filter { $0.namespace == dr3d }.map(element) }
        e.setRawXML(node.xml); return e
    }
    func odfTextAppearance(_ attrs: [String: String]) throws -> TextAppearance? {
        func attr(_ ns: String, _ key: String) -> String? { attrs[ODF.key(ns, key)] }
        let spacing = try attr(ODF.fo, "letter-spacing").flatMap { $0 == "normal" ? 0 : try ODF.length($0) }
        let position = attr(ODF.style, "text-position")?.split(separator: " ").first.map(String.init)
        var baseline: Double?, script: String?
        if let position, position.hasSuffix("%"), let n = Double(position.dropLast()), n.isFinite { baseline = n / 100 }
        else if position == "super" { script = "super" } else if position == "sub" { script = "sub" }
        let cap = attr(ODF.fo, "text-transform") ?? attr(ODF.fo, "font-variant")
        let strike = attr(ODF.style, "text-line-through-style"), underline = attr(ODF.style, "text-underline-style")
        guard spacing != nil || baseline != nil || script != nil || cap != nil || strike != nil || underline != nil else { return nil }
        return .init(spacing: spacing, baseline: baseline, script: script, capitalization: cap, strike: strike, underlineStyle: underline)
    }
}
