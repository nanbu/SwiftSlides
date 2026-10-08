import Foundation

/// 追加文字書式。文字間隔はpt、baselineは文字サイズに対する比率。
public final class TextAppearance: Sendable, Equatable, Codable {
    public let spacing: Double?
    public let baseline: Double?
    /// Named superscript/subscript position when the source leaves its numeric offset to layout.
    public let script: String?
    public let baselinePoints: Double?
    public let capitalization: String?
    public let strike: String?
    public let underlineStyle: String?
    public let kerning: Double?
    public let fill: Fill?
    public let outline: Stroke?
    public let outlineIsNone: Bool?
    public let effects: ElementEffects?
    public let scene3D: Scene3D?
    public let shape3D: Shape3D?
    public let flatTextDepth: Double?
    public init(spacing: Double? = nil, baseline: Double? = nil, script: String? = nil, baselinePoints: Double? = nil, capitalization: String? = nil, strike: String? = nil, underlineStyle: String? = nil, kerning: Double? = nil, fill: Fill? = nil, outline: Stroke? = nil, outlineIsNone: Bool? = nil, effects: ElementEffects? = nil, scene3D: Scene3D? = nil, shape3D: Shape3D? = nil, flatTextDepth: Double? = nil) {
        self.spacing = spacing; self.baseline = baseline; self.script = script; self.baselinePoints = baselinePoints; self.capitalization = capitalization; self.strike = strike; self.underlineStyle = underlineStyle; self.kerning = kerning; self.fill = fill; self.outline = outline; self.outlineIsNone = outlineIsNone; self.effects = effects; self.scene3D = scene3D; self.shape3D = shape3D; self.flatTextDepth = flatTextDepth
    }
    public static func == (a: TextAppearance, b: TextAppearance) -> Bool { a === b || (a.spacing == b.spacing && a.baseline == b.baseline && a.script == b.script && a.baselinePoints == b.baselinePoints && a.capitalization == b.capitalization && a.strike == b.strike && a.underlineStyle == b.underlineStyle && a.kerning == b.kerning && a.fill == b.fill && a.outline == b.outline && a.outlineIsNone == b.outlineIsNone && a.effects == b.effects && a.scene3D == b.scene3D && a.shape3D == b.shape3D && a.flatTextDepth == b.flatTextDepth) }
    public func overlaying(_ b: TextAppearance) -> TextAppearance {
        let spacing = b.spacing ?? self.spacing, baseline = b.baseline ?? self.baseline
        let capitalization = b.capitalization ?? self.capitalization, strike = b.strike ?? self.strike
        let underline = b.underlineStyle ?? self.underlineStyle, kerning = b.kerning ?? self.kerning
        let fill = b.fill ?? self.fill, outline = b.outlineIsNone == true ? nil : b.outline ?? self.outline
        let outlineIsNone = b.outline != nil ? false : b.outlineIsNone ?? self.outlineIsNone
        let effects = b.effects ?? self.effects, scene = b.scene3D ?? self.scene3D, shape = b.flatTextDepth != nil ? nil : b.shape3D ?? self.shape3D
        return .init(spacing: spacing, baseline: baseline, script: b.script ?? self.script, baselinePoints: b.baselinePoints ?? self.baselinePoints, capitalization: capitalization, strike: strike, underlineStyle: underline, kerning: kerning, fill: fill, outline: outline, outlineIsNone: outlineIsNone, effects: effects, scene3D: scene, shape3D: shape, flatTextDepth: b.shape3D != nil ? nil : b.flatTextDepth ?? self.flatTextDepth)
    }
}
/// DrawingML効果。lengthはpt、angleは度、percentageは倍率。合成順序を維持する。
public struct DrawingEffect: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        case alphaBiLevel, alphaCeiling, alphaFloor, alphaInv, alphaMod, alphaModFix, alphaOutset, alphaRepl
        case biLevel, blend, blur, clrChange, clrRepl, duotone, effect, fill, fillOverlay, glow, grayscl, hsl, innerShdw, lum, outerShdw, prstShdw, reflection, relOff, softEdge, tint, xfrm, cont, effectDag
    }
    public let kind: Kind
    public let values: [String: Double]
    public let attributes: [String: String]
    public let colors: [Color]
    public let fill: Fill?
    public let children: [DrawingEffect]
    public let source: SourceXMLNode
    public init(kind: Kind, values: [String: Double] = [:], attributes: [String: String] = [:], colors: [Color] = [], fill: Fill? = nil, children: [DrawingEffect] = [], source: SourceXMLNode) { self.kind = kind; self.values = values; self.attributes = attributes; self.colors = colors; self.fill = fill; self.children = children; self.source = source }
}
/// 外部URLを内部資源へ置き換えずに保持する3Dモデル参照。
public final class Model3DReference: Sendable, Equatable, Codable {
    public let model: PartReference
    public let source: SourceXMLNode
    public init(model: PartReference, source: SourceXMLNode) { self.model = model; self.source = source }
    public static func == (a: Model3DReference, b: Model3DReference) -> Bool { a === b || (a.model == b.model && a.source == b.source) }
}
