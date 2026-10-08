import Foundation
import SlideCore

extension PPTXReader {
    func drawingEffect(_ node: MarkupNode, part: String) -> DrawingEffect? {
        guard node.isA, let kind = DrawingEffect.Kind(rawValue: node.name) else { return nil }
        let lengths = Set(["blurRad", "dist", "rad"] + (kind == .xfrm ? ["tx", "ty"] : [])), angles = Set(["dir", "fadeDir", "kx", "ky", "hue"])
        let percentages = Set(["sx", "sy", "stA", "endA", "stPos", "endPos", "thresh", "amt", "a", "hueMod", "sat", "lum", "bright", "contrast"] + (kind == .relOff ? ["tx", "ty"] : []))
        var values: [String: Double] = [:]
        for (key, raw) in node.attributes where lengths.contains(key) || angles.contains(key) || percentages.contains(key) {
            let value = percentages.contains(key) ? percentage(raw) : Double(raw).map { $0 / (lengths.contains(key) ? 12_700 : 60_000) }
            if let value, value.isFinite { values[key] = value } else { warn(part, node, .uninterpretedFormatting, "不正な効果値を原本に保持します: \(key)", feature: "PNT-009") }
        }
        var children: [DrawingEffect] = [], colors: [Color] = []
        for child in node.children {
            if let value = drawingEffect(child, part: part) { children.append(value) }
            else if ["clrFrom", "clrTo"].contains(child.name) { if let c = color(child, part: part) { colors.append(c) } }
            else {
                let wrapper = MarkupNode(name: "color", namespace: NS.a, qualifiedName: "a:color"); wrapper.content = [.node(child)]
                if let c = color(wrapper, part: part) { colors.append(c) }
            }
        }
        do { return try .init(kind: kind, values: values, attributes: node.attributes, colors: colors, fill: fill(node, part: part), children: children, source: SourceXMLNode(node)) }
        catch { warn(part, node, .uninterpretedFormatting, "効果を解釈できません: \(error)", feature: "PNT-009"); return nil }
    }
    func textAppearance(_ node: MarkupNode, part: String) -> TextAppearance? {
        let attributeNames = ["spc", "baseline", "cap", "strike", "kern"] + (node.attr("u").map { !["none", "sng"].contains($0) } == true ? ["u"] : [])
        let childNames = ["ln", "effectLst", "effectDag", "scene3d", "sp3d", "flatTx", "gradFill", "noFill", "pattFill", "blipFill"]
        guard attributeNames.contains(where: { node.attr($0) != nil }) || node.children.contains(where: { childNames.contains($0.name) }) else { return nil }
        func number(_ key: String, _ divisor: Double) -> Double? { guard let raw = node.attr(key) else { return nil }; guard let n = Double(raw), n.isFinite else { warn(part, node, .uninterpretedFormatting, "不正な文字外観属性: \(key)"); return nil }; return n / divisor }
        do { return try .init(spacing: number("spc", 100), baseline: percentage(node.attr("baseline")), capitalization: node.attr("cap"), strike: node.attr("strike"), underlineStyle: node.attr("u"), kerning: number("kern", 100), fill: fill(node, part: part), outline: stroke(node.child("ln"), part: part), outlineIsNone: node.child("ln")?.child("noFill") != nil ? true : nil, effects: effects(node, style: nil, part: part), scene3D: scene3D(drawingChild(node, "scene3d"), part: part), shape3D: shape3D(drawingChild(node, "sp3d"), part: part), flatTextDepth: finite(node.child("flatTx")?.attr("z"), part: part, name: "flatTx z").map { $0 / 12_700 }) }
        catch { warn(part, node, .uninterpretedFormatting, "文字外観を解釈できません: \(error)"); return nil }
    }
    func model3D(_ graphic: MarkupNode?, rels: [String: Relationship], part: String) throws -> Model3DReference? {
        guard let model = graphic?.children.first(where: { $0.name == "model3d" && $0.namespace == "http://schemas.microsoft.com/office/drawing/2017/model3d" }) else { return nil }
        guard let id = model.rel("embed") ?? model.rel("link") else { throw SlideError.invalidRelationship(part: part, detail: "3D modelの参照不在") }
        return try .init(model: partReference(id, rels: rels, part: part), source: SourceXMLNode(model))
    }
}

extension Presentation {
    /// model参照の内部資源を読み、glTF/GLBの構造とaccessorへアクセスする。
    public func readModel3D(_ reference: Model3DReference, limits: PackageLimits = .init(), resourceProvider: (@Sendable (String) throws -> Data?)? = nil) throws -> Model3DDocument {
        let data: Data
        if let path = reference.model.path { data = try asset(at: path) }
        else if let target = reference.model.externalTarget, let supplied = try resourceProvider?(target) { data = supplied }
        else { throw SlideError.missingPart("3D model資源") }
        return try Model3DReader.read(data, limits: limits) { uri in
            if let path = reference.model.path, !uri.contains(":"), !uri.hasPrefix("/") {
                return try asset(at: OPCPackage.resolve(uri, from: path))
            }
            return try resourceProvider?(uri)
        }
    }
}
