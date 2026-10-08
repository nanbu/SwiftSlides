import Foundation

/// 元形式の追加内容。xmlは説明用の投影であり、編集用APIではない。
public struct NativeFeatureDescriptor: Sendable, Equatable, Codable {
    public var part: String
    public var name: String
    public var namespace: String
    public var xml: String
    public var references: [PartReference]
    public init(part: String, name: String, namespace: String, xml: String, references: [PartReference] = []) {
        self.part = part; self.name = name; self.namespace = namespace; self.xml = xml; self.references = references
    }
}

/// 画像の切り抜き。100%=1。負値は画像の外への拡張を表す。
public struct ImageCrop: Sendable, Equatable, Codable {
    public var top: Double?
    public var left: Double?
    public var bottom: Double?
    public var right: Double?
    public init(top: Double? = nil, left: Double? = nil, bottom: Double? = nil, right: Double? = nil) {
        self.top = top; self.left = left; self.bottom = bottom; self.right = right
    }
}
public struct GradientStop: Sendable, Equatable, Codable {
    public var position: Double
    public var color: Color
    public init(position: Double, color: Color) { self.position = position; self.color = color }
}
/// 線形/経路gradientの直接値。角度は度、stop位置は倍率。pathの詳細はXMLに保持する。
public struct GradientFill: Sendable, Equatable, Codable {
    private enum CodingKeys: String, CodingKey {
        case stops
        case angle
        case scaled
        case path
        case flip
        case rotatesWithShape = "rotateWithShape"
        case rawXML
    }

    public var stops: [GradientStop]
    public var angle: Double?
    public var scaled: Bool?
    public var path: String?
    public var flip: String?
    public var rotatesWithShape: Bool?
    public var rawXML: String
    public init(stops: [GradientStop], angle: Double? = nil, scaled: Bool? = nil, path: String? = nil, flip: String? = nil, rotatesWithShape: Bool? = nil, rawXML: String = "") {
        self.stops = stops; self.angle = angle; self.scaled = scaled; self.path = path; self.flip = flip; self.rotatesWithShape = rotatesWithShape; self.rawXML = rawXML
    }
}
public struct PatternFill: Sendable, Equatable, Codable {
    public var preset: String?
    public var foreground: Color?
    public var background: Color?
    public var rawXML: String
    public init(preset: String? = nil, foreground: Color? = nil, background: Color? = nil, rawXML: String = "") {
        self.preset = preset; self.foreground = foreground; self.background = background; self.rawXML = rawXML
    }
}
/// 画像塗り。内部assetと外部URLを区別し、tile/stretchの詳細はXMLに保持する。
public struct PictureFill: Sendable, Equatable, Codable {
    private enum CodingKeys: String, CodingKey {
        case part
        case image
        case crop
        case isTiled
        case rotatesWithShape = "rotateWithShape"
        case rawXML
    }

    public var part: String
    /// 省略されたblip参照はnil。継承元を推測して埋めない。
    public var image: PartReference?
    public var crop: ImageCrop?
    public var isTiled: Bool
    public var rotatesWithShape: Bool?
    public var rawXML: String
    public init(part: String, image: PartReference? = nil, crop: ImageCrop? = nil, isTiled: Bool = false, rotatesWithShape: Bool? = nil, rawXML: String = "") {
        self.part = part; self.image = image; self.crop = crop; self.isTiled = isTiled; self.rotatesWithShape = rotatesWithShape; self.rawXML = rawXML
    }
}

public struct TableCellBorder: Sendable, Equatable, Codable {
    public enum Edge: String, Sendable, Codable { case left, right, top, bottom, topLeftToBottomRight, bottomLeftToTopRight }
    public var edge: Edge
    public var stroke: Stroke?
    public var isExplicitlyNone: Bool
    public var rawXML: String
    public init(edge: Edge, stroke: Stroke? = nil, isExplicitlyNone: Bool = false, rawXML: String = "") {
        self.edge = edge; self.stroke = stroke; self.isExplicitlyNone = isExplicitlyNone; self.rawXML = rawXML
    }
}
/// 表示文字とは独立した元形式の型付きキャッシュ。未知のtypeも字句値を残す。
public struct TableCellValue: Sendable, Equatable, Codable {
    public var type: String
    public var lexicalValue: String?
    public var currency: String?
    public init(type: String, lexicalValue: String? = nil, currency: String? = nil) { self.type = type; self.lexicalValue = lexicalValue; self.currency = currency }
    public var number: Double? { guard ["float", "percentage", "currency"].contains(type), let lexicalValue, let n = Double(lexicalValue), n.isFinite else { return nil }; return n }
    public var boolean: Bool? { guard type == "boolean" else { return nil }; switch lexicalValue { case "true", "1": return true; case "false", "0": return false; default: return nil } }
}

/// 効果の記述。未指定とfalse/0を区別する。再生や既定値の補完は行わない。
public struct SlideTransition: Sendable, Equatable, Codable {
    private enum CodingKeys: String, CodingKey {
        case effect
        case effectNamespace
        case speed
        case advancesOnClick = "advanceOnClick"
        case advanceAfterMilliseconds
        case durationMilliseconds
        case rawXML
    }

    public var effect: String?
    public var effectNamespace: String?
    public var speed: String?
    public var advancesOnClick: Bool?
    public var advanceAfterMilliseconds: UInt32?
    public var durationMilliseconds: UInt32?
    public var rawXML: String
    public init(effect: String? = nil, effectNamespace: String? = nil, speed: String? = nil, advancesOnClick: Bool? = nil, advanceAfterMilliseconds: UInt32? = nil, durationMilliseconds: UInt32? = nil, rawXML: String = "") {
        self.effect = effect; self.effectNamespace = effectNamespace; self.speed = speed; self.advancesOnClick = advancesOnClick; self.advanceAfterMilliseconds = advanceAfterMilliseconds; self.durationMilliseconds = durationMilliseconds; self.rawXML = rawXML
    }
}
/// timingの原本構造。属性キーは名前空間つき属性ではURI|localName。
public struct TimingNode: Sendable, Equatable, Codable {
    public var nativeProperties: [String:NativeValue]?
    public var name: String
    public var namespace: String
    public var attributes: [String: String]
    public var text: String?
    public var children: [TimingNode]
    public init(name: String, namespace: String, attributes: [String: String] = [:], text: String? = nil, children: [TimingNode] = []) {
        self.name = name; self.namespace = namespace; self.attributes = attributes; self.text = text; self.children = children
    }
}
public struct SlideTiming: Sendable, Equatable, Codable {
    public var root: TimingNode
    /// ファイル順のshape target。重複は異なるtargetの出現として保持する。
    public var targetElementIDs: [String]
    public var rawXML: String
    public init(root: TimingNode, targetElementIDs: [String] = [], rawXML: String = "") { self.root = root; self.targetElementIDs = targetElementIDs; self.rawXML = rawXML }
}
public struct MediaReference: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable { case audio, video, media }
    public var kind: Kind
    public var reference: PartReference
    public var contentType: String?
    public var rawXML: String
    public init(kind: Kind, reference: PartReference, contentType: String? = nil, rawXML: String = "") { self.kind = kind; self.reference = reference; self.contentType = contentType; self.rawXML = rawXML }
}
/// 従来コメントの直接値。日時は元の字句、位置はポイント。
public struct SlideComment: Sendable, Equatable, Codable {
    public var id: String?
    public var authorID: String?
    public var authorName: String?
    public var authorInitials: String?
    public var dateTime: String?
    public var x: Double?
    public var y: Double?
    public var text: String
    public var part: String
    public var rawXML: String
    public init(id: String? = nil, authorID: String? = nil, authorName: String? = nil, authorInitials: String? = nil, dateTime: String? = nil, x: Double? = nil, y: Double? = nil, text: String, part: String, rawXML: String = "") {
        self.id = id; self.authorID = authorID; self.authorName = authorName; self.authorInitials = authorInitials; self.dateTime = dateTime; self.x = x; self.y = y; self.text = text; self.part = part; self.rawXML = rawXML
    }
}
