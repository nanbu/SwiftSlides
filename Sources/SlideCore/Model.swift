import Foundation

/// ポイント単位のサイズ。1 pt = 1/72 inch = 12,700 EMU。
public struct Size: Sendable, Equatable, Codable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
    public static let widescreen = Size(width: 960, height: 540)
    public static let standard = Size(width: 720, height: 540)
}
/// ポイント単位の矩形。グループ内では親のローカル座標。
public struct Rect: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var size: Size { .init(width: width, height: height) }
    public func inset(by i: Insets) -> Rect { .init(x: x + i.left, y: y + i.top, width: width - i.left - i.right, height: height - i.top - i.bottom) }
}
/// テキストやレイアウトのポイント単位の余白。
public struct Insets: Sendable, Equatable, Codable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double
    public init(top: Double = 0, left: Double = 0, bottom: Double = 0, right: Double = 0) { self.top = top; self.left = left; self.bottom = bottom; self.right = right }
    public init(_ all: Double) { self.init(top: all, left: all, bottom: all, right: all) }
    public static let zero = Insets()
}
/// RGBまたはテーマ参照。テーマ参照は継承した見た目の解決結果ではない。
public enum Color: Sendable, Equatable, Codable {
    case rgb(String)
    case theme(String)
    public static let black = Color.rgb("000000")
    public static let white = Color.rgb("FFFFFF")
    public static let blue = Color.rgb("2364AA")
}
/// 図形・スライド背景・表セルの塗り。
public enum Fill: Sendable, Equatable, Codable {
    case none
    case solid(Color)
}
/// 線端の矢印形。
public enum Arrowhead: String, Sendable, Codable { case none, triangle, stealth, diamond, oval, arrow }
/// 線・図形枠の書式。幅はポイント。
public struct Stroke: Sendable, Equatable, Codable {
    public enum Dash: String, Sendable, Codable { case solid, dot, dash, lgDash, dashDot, lgDashDot, lgDashDotDot, sysDash, sysDot, sysDashDot, sysDashDotDot }
    public var color: Color
    public var width: Double
    public var dash: Dash
    public var startArrow: Arrowhead
    public var endArrow: Arrowhead
    public init(color: Color = .black, width: Double = 1, dash: Dash = .solid, startArrow: Arrowhead = .none, endArrow: Arrowhead = .none) {
        self.color = color; self.width = width; self.dash = dash; self.startArrow = startArrow; self.endArrow = endArrow
    }
}
/// フォント名とポイントサイズ。東アジア・複合文字用フォントを別指定できる。フォントファイルは埋め込まない。
public struct Font: Sendable, Equatable, Codable {
    public var family: String?
    public var size: Double?
    public var eastAsianFamily: String?
    public var complexScriptFamily: String?
    /// テーマ内のscript別フォント。JpanとEast Asianは別の指定。
    public var supplementalFamilies: [String: String]
    public init(family: String? = nil, size: Double? = nil, eastAsianFamily: String? = nil, complexScriptFamily: String? = nil, supplementalFamilies: [String: String] = [:]) {
        self.family = family; self.size = size; self.eastAsianFamily = eastAsianFamily; self.complexScriptFamily = complexScriptFamily; self.supplementalFamilies = supplementalFamilies
    }
}
/// 文字の直接指定書式。nilは未指定で、実効値の計算ではない。
public struct TextStyle: Sendable, Equatable, Codable {
    public var font: Font
    public var bold: Bool?
    public var italic: Bool?
    public var underline: Bool?
    public var color: Color?
    public var language: String?
    public init(font: Font = .init(), bold: Bool? = nil, italic: Bool? = nil, underline: Bool? = nil, color: Color? = nil, language: String? = nil) {
        self.font = font; self.bold = bold; self.italic = italic; self.underline = underline; self.color = color; self.language = language
    }
}
/// リンク先。既存文書の内部スライド参照はパーツパスで保持する。
public enum Link: Sendable, Equatable, Codable { case external(String), slide(String) }
/// 一つの文字書式を持つ文字列。改行・タブは文字列中に保持する。
public struct TextRun: Sendable, Equatable, Codable {
    public var text: String
    public var style: TextStyle
    public var link: Link?
    public init(_ text: String, style: TextStyle = .init(), link: Link? = nil) { self.text = text; self.style = style; self.link = link }
}
/// 行の揃え位置。
public enum TextAlignment: String, Sendable, Codable { case left = "l", center = "ctr", right = "r", justified = "just" }
/// 段落の箇条書き。
public enum Bullet: Sendable, Equatable, Codable { case none, character(String), numbered(String, start: Int) }
/// 段落書式。余白はポイント、lineSpacingは行高倍率。
public struct ParagraphStyle: Sendable, Equatable, Codable {
    public var alignment: TextAlignment?
    public var level: Int?
    public var leftMargin: Double?
    public var indent: Double?
    public var spaceBefore: Double?
    public var spaceAfter: Double?
    public var lineSpacing: Double?
    public var bullet: Bullet?
    public init(alignment: TextAlignment? = nil, level: Int? = nil, leftMargin: Double? = nil, indent: Double? = nil, spaceBefore: Double? = nil, spaceAfter: Double? = nil, lineSpacing: Double? = nil, bullet: Bullet? = nil) {
        self.alignment = alignment; self.level = level; self.leftMargin = leftMargin; self.indent = indent; self.spaceBefore = spaceBefore; self.spaceAfter = spaceAfter; self.lineSpacing = lineSpacing; self.bullet = bullet
    }
}
/// 段落。defaultTextStyleは直接指定の既定run書式。
public struct Paragraph: Sendable, Equatable, Codable {
    public var runs: [TextRun]
    public var style: ParagraphStyle
    public var defaultTextStyle: TextStyle
    /// 空段落・段落終端の直接指定書式。
    public var endTextStyle: TextStyle
    public init(runs: [TextRun] = [], style: ParagraphStyle = .init(), defaultTextStyle: TextStyle = .init(), endTextStyle: TextStyle = .init()) { self.endTextStyle = endTextStyle; self.runs = runs; self.style = style; self.defaultTextStyle = defaultTextStyle }
    public init(_ text: String, style: ParagraphStyle = .init(), textStyle: TextStyle = .init()) { self.init(runs: [.init(text, style: textStyle)], style: style) }
    public var plainText: String { runs.map(\.text).joined() }
}
/// 図形内テキストの縦位置。
public enum VerticalAlignment: String, Sendable, Codable { case top = "t", center = "ctr", bottom = "b" }
/// 図形内の段落・余白・折り返し。レンダリングや文字計測は行わない。
public struct TextBody: Sendable, Equatable, Codable {
    public var paragraphs: [Paragraph]
    public var insets: Insets?
    public var verticalAlignment: VerticalAlignment?
    public var wrap: Bool?
    public init(paragraphs: [Paragraph] = [], insets: Insets? = nil, verticalAlignment: VerticalAlignment? = nil, wrap: Bool? = nil) {
        self.paragraphs = paragraphs; self.insets = insets; self.verticalAlignment = verticalAlignment; self.wrap = wrap
    }
    public init(_ text: String, style: TextStyle = .init(), alignment: TextAlignment? = nil, insets: Insets? = nil, verticalAlignment: VerticalAlignment? = nil) {
        self.init(paragraphs: text.components(separatedBy: "\n").map { Paragraph($0, style: .init(alignment: alignment), textStyle: style) }, insets: insets, verticalAlignment: verticalAlignment)
    }
    public var plainText: String { paragraphs.map(\.plainText).joined(separator: "\n") }
}
/// DrawingMLで共有されるプリセット名。未知のプリセットも名前のまま保持する。
public struct ShapeGeometry: Sendable, Equatable, Codable, ExpressibleByStringLiteral {
    public var preset: String
    public init(_ preset: String) { self.preset = preset }
    public init(stringLiteral value: String) { preset = value }
    public static let rectangle: Self = "rect"
    public static let roundedRectangle: Self = "roundRect"
    public static let ellipse: Self = "ellipse"
    public static let triangle: Self = "triangle"
    public static let diamond: Self = "diamond"
    public static let chevron: Self = "chevron"
    public static let rightArrow: Self = "rightArrow"
    public static let line: Self = "line"
    public static let straightConnector: Self = "straightConnector1"
    public static let elbowConnector: Self = "bentConnector3"
}
/// 保存する画像。読んだ画像はpath参照、新規画像はdataを指定する。
public struct Image: Sendable, Equatable, Codable {
    public var path: String?
    public var data: Data?
    public var contentType: String?
    public var alternativeText: String
    public init(data: Data, contentType: String, alternativeText: String = "") { self.path = nil; self.data = data; self.contentType = contentType; self.alternativeText = alternativeText }
    public init(path: String, contentType: String? = nil, alternativeText: String = "") { self.path = path; self.data = nil; self.contentType = contentType; self.alternativeText = alternativeText }
}
/// 表セル。rowSpan/columnSpanと継続セルのフラグを保持する。
public struct TableCell: Sendable, Equatable, Codable {
    public var text: TextBody
    public var fill: Fill?
    public var border: Stroke?
    public var insets: Insets?
    public var rowSpan: Int
    public var columnSpan: Int
    public var isMergeContinuation: Bool
    public init(_ text: String = "", style: TextStyle = .init(), fill: Fill? = nil, border: Stroke? = nil, insets: Insets? = nil, rowSpan: Int = 1, columnSpan: Int = 1, isMergeContinuation: Bool = false) {
        self.text = .init(text, style: style); self.fill = fill; self.border = border; self.insets = insets; self.rowSpan = rowSpan; self.columnSpan = columnSpan; self.isMergeContinuation = isMergeContinuation
    }
}
/// 表。columnWidthsとrowHeightsはポイント。
public struct Table: Sendable, Equatable, Codable {
    public var columnWidths: [Double]
    public var rowHeights: [Double]
    public var rows: [[TableCell]]
    public var styleID: String?
    public init(columnWidths: [Double], rowHeights: [Double], rows: [[TableCell]], styleID: String? = nil) { self.columnWidths = columnWidths; self.rowHeights = rowHeights; self.rows = rows; self.styleID = styleID }
    public var plainText: String { rows.map { $0.map { $0.text.plainText }.joined(separator: "\t") }.joined(separator: "\n") }
}
/// レイアウト上のプレースホルダー。継承値の自動解決は行わない。
public struct Placeholder: Sendable, Equatable, Codable {
    public var kind: String
    public var index: Int?
    public init(kind: String = "obj", index: Int? = nil) { self.kind = kind; self.index = index }
}
/// 図形、線、画像、表、グループ、未解釈要素。idはスライド内で一意。
public struct Element: Sendable, Equatable, Codable, Identifiable {
    public enum Kind: String, Sendable, Codable { case shape, connector, image, table, group, opaque }
    public var id: String
    public var name: String
    public var kind: Kind
    /// テキストボックスと図形中のラベルを区別する。
    public var isTextBox: Bool
    /// nilは継承または未指定。サイズを計算した結果ではない。
    public var frame: Rect?
    public var rotation: Double
    public var flipHorizontal: Bool
    public var flipVertical: Bool
    public var geometry: ShapeGeometry?
    public var fill: Fill?
    public var stroke: Stroke?
    public var text: TextBody?
    public var image: Image?
    public var table: Table?
    public var children: [Element]
    /// グループ内座標領域。frameへ縮尺して配置される。
    public var childFrame: Rect?
    public var placeholder: Placeholder?
    /// 保存で保全される未解釈XMLの説明用コピー。編集不可。
    public internal(set) var rawXML: String?
    public init(id: String = UUID().uuidString, name: String = "", kind: Kind = .shape, frame: Rect? = nil, geometry: ShapeGeometry? = .rectangle, fill: Fill? = nil, stroke: Stroke? = nil, text: TextBody? = nil, image: Image? = nil, table: Table? = nil, children: [Element] = [], childFrame: Rect? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.isTextBox = false; self.frame = frame; self.rotation = 0; self.flipHorizontal = false; self.flipVertical = false; self.geometry = geometry; self.fill = fill; self.stroke = stroke; self.text = text; self.image = image; self.table = table; self.children = children; self.childFrame = childFrame; self.placeholder = nil; self.rawXML = nil
    }
    public var plainText: String { text?.plainText ?? table?.plainText ?? children.map(\.plainText).filter { !$0.isEmpty }.joined(separator: "\n") }
    package mutating func setRawXML(_ value: String) { rawXML = value }
}
/// 一枚のスライド。idはPresentation内で一意。既存スライドのidentityを維持する。
public struct Slide: Sendable, Equatable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var isHidden: Bool
    public var background: Fill?
    public var elements: [Element]
    public var notes: TextBody?
    /// 読み取ったレイアウトへのパッケージ参照。
    public var layoutPath: String?
    public init(id: String = UUID().uuidString, name: String = "", elements: [Element] = [], notes: TextBody? = nil, background: Fill? = nil) {
        self.id = id; self.name = name; self.elements = elements; self.notes = notes; self.background = background; self.isHidden = false; self.layoutPath = nil
    }
    public var plainText: String { elements.map(\.plainText).filter { !$0.isEmpty }.joined(separator: "\n") }
    /// テキストボックスを末尾へ追加し、そのIDを返す。
    @discardableResult public mutating func addText(_ text: String, frame: Rect, style: TextStyle = .init(), alignment: TextAlignment? = nil, name: String = "") -> String {
        var e = Element(name: name, frame: frame, text: .init(text, style: style, alignment: alignment)); e.isTextBox = true; elements.append(e); return e.id
    }
    @discardableResult public mutating func addShape(_ geometry: ShapeGeometry = .rectangle, frame: Rect, fill: Fill? = nil, stroke: Stroke? = nil, text: TextBody? = nil, name: String = "") -> String {
        let e = Element(name: name, frame: frame, geometry: geometry, fill: fill, stroke: stroke, text: text); elements.append(e); return e.id
    }
    /// 始点・終点から線を配置する。矢印や破線はStrokeで指定する。
    @discardableResult public mutating func addLine(from start: (x: Double, y: Double), to end: (x: Double, y: Double), stroke: Stroke = .init(), geometry: ShapeGeometry = .straightConnector) -> String {
        var e = Element(kind: .connector, frame: .init(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)), geometry: geometry, stroke: stroke)
        e.flipHorizontal = end.x < start.x; e.flipVertical = end.y < start.y; elements.append(e); return e.id
    }
    @discardableResult public mutating func addImage(_ image: Image, frame: Rect) -> String {
        let e = Element(kind: .image, frame: frame, geometry: nil, image: image); elements.append(e); return e.id
    }
    @discardableResult public mutating func addTable(_ table: Table, frame: Rect) -> String {
        let e = Element(kind: .table, frame: frame, geometry: nil, table: table); elements.append(e); return e.id
    }
}
/// 新規文書の色とフォントのテーマ。既存テーマの読み取りはパーツ保全で扱う。
public struct Theme: Sendable, Equatable, Codable {
    public var name: String
    public var titleFont: Font
    public var bodyFont: Font
    public var colors: [String: String]
    public init(name: String = "SwiftSlides", titleFont: Font = .init(family: "Aptos Display", eastAsianFamily: "Yu Gothic"), bodyFont: Font = .init(family: "Aptos", eastAsianFamily: "Yu Gothic"), colors: [String: String] = ["dk1":"000000", "lt1":"FFFFFF", "dk2":"172B4D", "lt2":"F4F6F8", "accent1":"2364AA", "accent2":"24A19C", "accent3":"E8AA42", "accent4":"7952B3", "accent5":"D65A5A", "accent6":"748DA6", "hlink":"0563C1", "folHlink":"954F72"]) {
        self.name = name; self.titleFont = titleFont; self.bodyFont = bodyFont; self.colors = colors
    }
}
/// 原本テーマの投影。フォント名・色参照を直接読み、見た目の解決済み値とは区別する。
public struct ThemePart: Sendable, Equatable, Codable {
    public var path: String
    public var name: String
    public var titleFont: Font
    public var bodyFont: Font
    public var colors: [String: Color]
    public init(path: String, name: String, titleFont: Font, bodyFont: Font, colors: [String: Color]) { self.path = path; self.name = name; self.titleFont = titleFont; self.bodyFont = bodyFont; self.colors = colors }
}
/// 文書プロパティ。日時・作者は指定された値だけを保存する。
public struct Metadata: Sendable, Equatable, Codable {
    public var title: String?
    public var subject: String?
    public var creator: String?
    public var description: String?
    public var keywords: String?
    public init(title: String? = nil, subject: String? = nil, creator: String? = nil, description: String? = nil, keywords: String? = nil) { self.title = title; self.subject = subject; self.creator = creator; self.description = description; self.keywords = keywords }
}
/// 形式中立のスライド文書。読み取った原本は値と共に保持される。
public struct Presentation: Sendable {
    public var size: Size
    public var slides: [Slide]
    public var metadata: Metadata
    /// 新規文書用テーマ。既存文書のテーマ変更は安全性のため拒否される。
    public var theme: Theme
    /// パッケージから読み取ったテーマ定義。継承・色変換の解決は行わない。
    public internal(set) var sourceThemes: [ThemePart]
    public internal(set) var sourceFormat: PresentationFormat?
    public internal(set) var readWarnings: [SlideWarning]
    public internal(set) var packageParts: [PackagePart]
    package var storage: Preservation?
    public init(size: Size = .widescreen, slides: [Slide] = [], metadata: Metadata = .init(), theme: Theme = .init()) {
        self.size = size; self.slides = slides; self.metadata = metadata; self.theme = theme; self.sourceThemes = []; self.sourceFormat = nil; self.readWarnings = []; self.packageParts = []; self.storage = nil
    }
    public var plainText: String { slides.map(\.plainText).joined(separator: "\n\n") }
    /// 参照画像や未知パーツのオリジナルbytesを必要時に展開・CRC検査する。
    public func asset(at path: String) throws -> Data {
        guard let storage else { throw SlideError.missingPart(path) }; return try storage.archive.read(path)
    }
    package mutating func preserve(_ value: Preservation, format: PresentationFormat, warnings: [SlideWarning], parts: [PackagePart], themes: [ThemePart]) { sourceThemes = themes; storage = value; sourceFormat = format; readWarnings = warnings; packageParts = parts }
}
/// パッケージパーツの検査情報。expandedSizeは宣言値でありメモリ使用量ではない。
public struct PackagePart: Sendable, Equatable, Codable {
    public var path: String
    public var contentType: String?
    public var compressedSize: Int
    public var expandedSize: Int
    public init(path: String, contentType: String?, compressedSize: Int, expandedSize: Int) { self.path = path; self.contentType = contentType; self.compressedSize = compressedSize; self.expandedSize = expandedSize }
}
package struct Preservation: Sendable {
    package let data: Data
    package let archive: PackageArchive
    package let mainPart: String
    package let limits: PackageLimits
    package let originalSize: Size
    package let originalSlides: [Slide]
    package let originalMetadata: Metadata
    package let originalTheme: Theme
    package let slidePaths: [String: String]
    package let notesPaths: [String: String]
    package let notesOmitted: Bool
    package init(data: Data, archive: PackageArchive, mainPart: String, limits: PackageLimits, originalSize: Size, originalSlides: [Slide], originalMetadata: Metadata, originalTheme: Theme, slidePaths: [String: String], notesPaths: [String: String], notesOmitted: Bool) {
        self.data = data; self.archive = archive; self.mainPart = mainPart; self.limits = limits; self.originalSize = originalSize; self.originalSlides = originalSlides; self.originalMetadata = originalMetadata; self.originalTheme = originalTheme; self.slidePaths = slidePaths; self.notesPaths = notesPaths; self.notesOmitted = notesOmitted
    }
}
