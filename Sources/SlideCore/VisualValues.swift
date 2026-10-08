import Foundation

public enum ColorBase: Sendable, Equatable, Codable {
    case sRGB(String), scheme(String), system(name: String, fallback: String?)
    /// scRGBは線形成分。HSLのhueは度、sat/lumは0...1。
    case scRGB(red: Double, green: Double, blue: Double)
    case hsl(hue: Double, saturation: Double, luminance: Double)
    case preset(String)
}
/// XMLの操作名・値・名前空間を順番どおり保持。値はOOXMLの字句値。
public struct ColorTransform: Sendable, Equatable, Codable {
    public var name: String
    public var value: String?
    public var namespace: String
    public init(name: String, value: String? = nil, namespace: String = "http://schemas.openxmlformats.org/drawingml/2006/main") { self.name = name; self.value = value; self.namespace = namespace }
}
public struct ColorValue: Sendable, Equatable, Codable {
    public var base: ColorBase
    public var transforms: [ColorTransform]
    public init(base: ColorBase, transforms: [ColorTransform] = []) { self.base = base; self.transforms = transforms }
}
public struct ResolvedColor: Sendable, Equatable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) { self.red = red; self.green = green; self.blue = blue; self.alpha = alpha }
}
public struct ColorResolution: Sendable, Equatable, Codable {
    /// 未解決操作が一つでもあればnil。部分結果を実効色として返さない。
    public let color: ResolvedColor?
    public let diagnostics: [SlideDiagnostic]
}
public enum ColorResolver {
    /// テーマ定義側の変換を適用した後、使用箇所の変換をXML順で適用する。
    public static func resolve(_ color: Color, theme: [String: Color] = [:], colorMap: [String: String] = [:], placeholder: Color? = nil) -> ColorResolution {
        var issues: [SlideDiagnostic] = []
        func fail(_ message: String) -> ResolvedColor? {
            issues.append(.init(code: "colorUnresolved", feature: "PNT-002", stage: .read, action: .unresolved, location: .init(part: "", sourceElement: "color"), message: message)); return nil
        }
        func hex(_ value: String) -> ResolvedColor? {
            guard value.count == 6, let n = UInt32(value, radix: 16) else { return fail("不正なsRGB色") }
            return .init(red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255)
        }
        func evaluate(_ input: Color, seen: Set<String>, depth: Int) -> ResolvedColor? {
            guard depth < 32 else { return fail("色参照が深すぎます") }
            let value: ColorValue
            switch input { case .rgb(let s): value = .init(base: .sRGB(s)); case .theme(let s): value = .init(base: .scheme(s)); case .value(let v): value = v }
            var output: ResolvedColor?
            switch value.base {
            case .sRGB(let s): output = hex(s)
            case .scheme(let key):
                let mapped = colorMap[key] ?? key
                guard !seen.contains(mapped) else { return fail("循環したテーマ色参照") }
                guard let next = mapped == "phClr" ? placeholder : theme[mapped] else { return fail("未解決のテーマ色: \(mapped)") }
                output = evaluate(next, seen: seen.union([mapped]), depth: depth + 1)
            case .system: return fail("システム色はOS側で解決が必要です。fallbackは原本値として保持します")
            case .scRGB, .hsl, .preset: return fail("この基本色の解決は未対応です")
            }
            guard var result = output else { return nil }
            for operation in value.transforms {
                guard ["http://schemas.openxmlformats.org/drawingml/2006/main", "http://purl.oclc.org/ooxml/drawingml/main"].contains(operation.namespace),
                    let raw = operation.value, ["alpha", "alphaMod", "alphaOff"].contains(operation.name) else { return fail("未対応または不正な色変換: \(operation.name)") }
                let parsed = raw.hasSuffix("%") ? Double(raw.dropLast()).map { $0 / 100 } : Double(raw).map { $0 / 100_000 }
                guard let amount = parsed, amount.isFinite,
                    operation.name == "alphaOff" ? (-1...1).contains(amount) : amount >= 0,
                    operation.name != "alpha" || amount <= 1 else { return fail("色変換が範囲外です") }
                switch operation.name { case "alpha": result.alpha = amount; case "alphaMod": result.alpha *= amount; default: result.alpha += amount }
                result.alpha = min(1, max(0, result.alpha))
            }
            return result
        }
        let result = evaluate(color, seen: [], depth: 0)
        return .init(color: result, diagnostics: issues)
    }
}

public struct GeometryPoint: Sendable, Equatable, Codable {
    /// 数値またはguide参照。独自座標領域の値で、ポイントへ早期換算しない。
    public var x: String
    public var y: String
    public init(x: String, y: String) { self.x = x; self.y = y }
}
public enum PathCommand: Sendable, Equatable, Codable {
    case move(GeometryPoint), line(GeometryPoint)
    case quadratic(control: GeometryPoint, end: GeometryPoint)
    case cubic(control1: GeometryPoint, control2: GeometryPoint, end: GeometryPoint)
    case arc(widthRadius: String, heightRadius: String, startAngle: String, sweepAngle: String)
    case close
    case unsupported(String)
}
public struct GeometryPath: Sendable, Equatable, Codable {
    public var width: Double?
    public var height: Double?
    public var fillMode: String?
    public var stroke: Bool?
    public var extrusionOK: Bool?
    public var commands: [PathCommand]
    public init(width: Double? = nil, height: Double? = nil, fillMode: String? = nil, stroke: Bool? = nil, extrusionOK: Bool? = nil, commands: [PathCommand] = []) { self.width = width; self.height = height; self.fillMode = fillMode; self.stroke = stroke; self.extrusionOK = extrusionOK; self.commands = commands }
}
public struct GeometryGuide: Sendable, Equatable, Codable {
    public var name: String
    public var formula: String
    public init(name: String, formula: String) { self.name = name; self.formula = formula }
}
public struct CustomGeometry: Sendable, Equatable, Codable {
    public var paths: [GeometryPath]
    public var guides: [GeometryGuide]
    public var adjustments: [GeometryGuide]
    public var rawXML: String
    public init(paths: [GeometryPath] = [], guides: [GeometryGuide] = [], adjustments: [GeometryGuide] = [], rawXML: String = "") { self.paths = paths; self.guides = guides; self.adjustments = adjustments; self.rawXML = rawXML }
}
public struct StyleReference: Sendable, Equatable, Codable {
    public var index: Int?
    public var color: Color?
    public init(index: Int? = nil, color: Color? = nil) { self.index = index; self.color = color }
}
/// 外側の影の直接値。nilは属性未指定。長さはpt、角度は度、scaleは倍率。
public struct OuterShadow: Sendable, Equatable, Codable {
    private enum CodingKeys: String, CodingKey {
        case blurRadius
        case distance
        case direction
        case scaleX
        case scaleY
        case skewX
        case skewY
        case alignment
        case rotatesWithShape = "rotateWithShape"
        case color
    }

    public var blurRadius: Double?
    public var distance: Double?
    public var direction: Double?
    public var scaleX: Double?
    public var scaleY: Double?
    public var skewX: Double?
    public var skewY: Double?
    public var alignment: String?
    public var rotatesWithShape: Bool?
    public var color: Color?
    public init(blurRadius: Double? = nil, distance: Double? = nil, direction: Double? = nil, scaleX: Double? = nil, scaleY: Double? = nil, skewX: Double? = nil, skewY: Double? = nil, alignment: String? = nil, rotatesWithShape: Bool? = nil, color: Color? = nil) {
        self.blurRadius = blurRadius; self.distance = distance; self.direction = direction; self.scaleX = scaleX; self.scaleY = scaleY; self.skewX = skewX; self.skewY = skewY; self.alignment = alignment; self.rotatesWithShape = rotatesWithShape; self.color = color
    }
}
public enum VisualEffect: Sendable, Equatable, Codable { case outerShadow(OuterShadow), drawing(DrawingEffect), unsupported(name: String, xml: String) }
public struct ElementEffects: Sendable, Equatable, Codable {
    public var direct: [VisualEffect]?
    public var reference: StyleReference?
    public init(direct: [VisualEffect]? = nil, reference: StyleReference? = nil) { self.direct = direct; self.reference = reference }
}
