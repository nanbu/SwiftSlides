import Foundation

/// 描画継承を適用する前のlayout。element IDはpathと組で識別する。
public struct SlideLayoutPart: Sendable, Equatable, Codable {
    private enum CodingKeys: String, CodingKey {
        case path
        case name
        case masterPath
        case themeOverridePath
        case elements
        case background
        case backgroundReference
        case colorMapOverride
        case usesMasterColorMapping
        case showsMasterShapes = "showMasterShapes"
        case layoutType
    }

    public let path: String
    public var name: String
    public var masterPath: String?
    public var themeOverridePath: String?
    public var elements: [Element]
    public var background: Fill?
    public var backgroundReference: StyleReference?
    public var colorMapOverride: [String: String]?
    public var usesMasterColorMapping: Bool?
    public var showsMasterShapes: Bool?
    public var layoutType: String?
    public init(path: String, name: String, masterPath: String?, themeOverridePath: String?, elements: [Element], background: Fill?, backgroundReference: StyleReference?, colorMapOverride: [String: String]?, usesMasterColorMapping: Bool?, showsMasterShapes: Bool?, layoutType: String?) { self.path = path; self.name = name; self.masterPath = masterPath; self.themeOverridePath = themeOverridePath; self.elements = elements; self.background = background; self.backgroundReference = backgroundReference; self.colorMapOverride = colorMapOverride; self.usesMasterColorMapping = usesMasterColorMapping; self.showsMasterShapes = showsMasterShapes; self.layoutType = layoutType }
}
public struct SlideMasterPart: Sendable, Equatable, Codable {
    public let path: String
    public var name: String
    public var themePath: String?
    public var elements: [Element]
    public var background: Fill?
    public var backgroundReference: StyleReference?
    public var colorMap: [String: String]?
    public var textStyles: [String: TextListStyle]
    public var layoutPaths: [String]
    public init(path: String, name: String, themePath: String?, elements: [Element], background: Fill?, backgroundReference: StyleReference?, colorMap: [String: String]?, textStyles: [String: TextListStyle], layoutPaths: [String]) { self.path = path; self.name = name; self.themePath = themePath; self.elements = elements; self.background = background; self.backgroundReference = backgroundReference; self.colorMap = colorMap; self.textStyles = textStyles; self.layoutPaths = layoutPaths }
}
public struct SlideLayoutReadResult: Sendable {
    public let layout: SlideLayoutPart
    public let warnings: [SlideWarning]
    public var diagnostics: [SlideDiagnostic] { warnings.map { $0.diagnostic(stage: .read) } }
    public init(layout: SlideLayoutPart, warnings: [SlideWarning] = []) { self.layout = layout; self.warnings = warnings }
}
public struct SlideMasterReadResult: Sendable {
    public let master: SlideMasterPart
    public let warnings: [SlideWarning]
    public var diagnostics: [SlideDiagnostic] { warnings.map { $0.diagnostic(stage: .read) } }
    public init(master: SlideMasterPart, warnings: [SlideWarning] = []) { self.master = master; self.warnings = warnings }
}

/// 外部参照は取得しない。pathとexternalTargetを混同しない。
public struct PartReference: Sendable, Equatable, Codable {
    public var relationshipID: String
    public var path: String?
    public var externalTarget: String?
    public init(relationshipID: String, path: String? = nil, externalTarget: String? = nil) { self.relationshipID = relationshipID; self.path = path; self.externalTarget = externalTarget }
}
public struct ChartPoint: Sendable, Equatable, Codable {
    public var index: Int
    /// 空・不正な数値も字句のまま保持。欠落pointは配列へ追加しない。
    public var text: String
    public var number: Double? { guard let n = Double(text), n.isFinite else { return nil }; return n }
    public init(index: Int, text: String) { self.index = index; self.text = text }
}
public struct ChartData: Sendable, Equatable, Codable {
    public var workbookPoints: [ChartPoint]?
    /// 多段カテゴリの各level。各点のindexを維持し、欠落点を補わない。
    public var levels: [[ChartPoint]]?
    public enum Source: String, Sendable, Codable { case stringCache, numberCache, stringLiteral, numberLiteral, multiLevelStringCache, stringReference, numberReference, multiLevelStringReference }
    public var source: Source
    public var formula: String?
    public var pointCount: Int?
    public var formatCode: String?
    public var points: [ChartPoint]
    public var rawXML: String
    public init(source: Source, formula: String?, pointCount: Int?, formatCode: String?, points: [ChartPoint], rawXML: String) { self.source = source; self.formula = formula; self.pointCount = pointCount; self.formatCode = formatCode; self.points = points; self.rawXML = rawXML }
}
public struct ChartSeries: Sendable, Equatable, Codable {
    public var xValues: ChartData?
    public var yValues: ChartData?
    public var bubbleSizes: ChartData?
    /// label・marker・trendline・error bar等の全構造。
    public var properties: SourceXMLNode?
    public var index: Int?
    public var order: Int?
    public var title: String?
    public var titleData: ChartData?
    public var categories: ChartData?
    public var values: ChartData?
    public var fill: Fill?
    public var stroke: Stroke?
    /// 点別書式・ラベル・マーカーなども原本を保持する。
    public var rawXML: String
    public init(index: Int?, order: Int?, title: String?, titleData: ChartData?, categories: ChartData?, values: ChartData?, fill: Fill?, stroke: Stroke?, rawXML: String) { self.index = index; self.order = order; self.title = title; self.titleData = titleData; self.categories = categories; self.values = values; self.fill = fill; self.stroke = stroke; self.rawXML = rawXML }
}
public struct ChartGroup: Sendable, Equatable, Codable {
    public var properties: SourceXMLNode?
    public var kind: String
    public var grouping: String?
    public var orientation: String?
    public var series: [ChartSeries]
    public var axisIDs: [String]
    public var rawXML: String
    public init(kind: String, grouping: String?, orientation: String?, series: [ChartSeries], axisIDs: [String], rawXML: String) { self.kind = kind; self.grouping = grouping; self.orientation = orientation; self.series = series; self.axisIDs = axisIDs; self.rawXML = rawXML }
}
public struct ChartAxis: Sendable, Equatable, Codable {
    public var nativeValues: [String:NativeValue]?
    public var scale: ChartAxisScale?
    public var nativeProperties: [String: String]?
    public var title: String?
    public var scaleType: String?
    public var properties: SourceXMLNode?
    public var kind: String
    public var id: String?
    public var crossAxisID: String?
    public var position: String?
    public var minimum: Double?
    public var maximum: Double?
    public var logarithmicBase: Double?
    public var numberFormat: String?
    public var isDeleted: Bool?
    public var rawXML: String
    public init(kind: String, id: String?, crossAxisID: String?, position: String?, minimum: Double?, maximum: Double?, logarithmicBase: Double?, numberFormat: String?, isDeleted: Bool?, rawXML: String) { self.kind = kind; self.id = id; self.crossAxisID = crossAxisID; self.position = position; self.minimum = minimum; self.maximum = maximum; self.logarithmicBase = logarithmicBase; self.numberFormat = numberFormat; self.isDeleted = isDeleted; self.rawXML = rawXML }
}
public struct Chart: Sendable, Equatable, Codable {
    public var view3D: ChartView3D?
    public var surfaces: [ChartSurface]?
    public var nativeProperties: [String: String]?
    public var workbook: WorkbookData?
    public var properties: SourceXMLNode?
    public var part: PartReference
    public var groups: [ChartGroup]
    public var axes: [ChartAxis]
    public var title: String?
    public var legendPosition: String?
    public var externalData: PartReference?
    public var rawXML: String
    public init(part: PartReference, groups: [ChartGroup], axes: [ChartAxis], title: String?, legendPosition: String?, externalData: PartReference?, rawXML: String) { self.part = part; self.groups = groups; self.axes = axes; self.title = title; self.legendPosition = legendPosition; self.externalData = externalData; self.rawXML = rawXML }
}
/// 保存済みdrawingのElementは元のdiagram座標領域のまま。slide座標へ自動追加しない。
public struct Diagram: Sendable, Equatable, Codable {
    public var data: PartReference?
    public var layout: PartReference?
    public var quickStyle: PartReference?
    public var colors: PartReference?
    public var drawing: PartReference?
    public var drawingFrame: Rect?
    public var drawingChildFrame: Rect?
    public var elements: [Element]
    public var dataTexts: [String]
    public var dataXML: String?
    public init(data: PartReference?, layout: PartReference?, quickStyle: PartReference?, colors: PartReference?, drawing: PartReference?, drawingFrame: Rect?, drawingChildFrame: Rect?, elements: [Element], dataTexts: [String], dataXML: String?) { self.data = data; self.layout = layout; self.quickStyle = quickStyle; self.colors = colors; self.drawing = drawing; self.drawingFrame = drawingFrame; self.drawingChildFrame = drawingChildFrame; self.elements = elements; self.dataTexts = dataTexts; self.dataXML = dataXML }
}
