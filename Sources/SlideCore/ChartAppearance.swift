import Foundation

/// chartの立体表示指示。角度は度、百分率は倍率。
public final class ChartView3D: Sendable, Equatable, Codable {
    public let rotationX: Double?, rotationY: Double?, perspective: Double?, depth: Double?, height: Double?
    public let rightAngleAxes: Bool?
    public let source: SourceXMLNode
    public init(rotationX: Double? = nil, rotationY: Double? = nil, perspective: Double? = nil, depth: Double? = nil, height: Double? = nil, rightAngleAxes: Bool? = nil, source: SourceXMLNode) { self.rotationX = rotationX; self.rotationY = rotationY; self.perspective = perspective; self.depth = depth; self.height = height; self.rightAngleAxes = rightAngleAxes; self.source = source }
    public static func == (a: ChartView3D, b: ChartView3D) -> Bool { a === b || (a.rotationX == b.rotationX && a.rotationY == b.rotationY && a.perspective == b.perspective && a.depth == b.depth && a.height == b.height && a.rightAngleAxes == b.rightAngleAxes && a.source == b.source) }
}
public final class ChartSurface: Sendable, Equatable, Codable {
    public let kind: String
    public let thickness: Double?
    public let fill: Fill?
    public let stroke: Stroke?
    public let scene3D: Scene3D?
    public let shape3D: Shape3D?
    public let source: SourceXMLNode
    public init(kind: String, thickness: Double? = nil, fill: Fill? = nil, stroke: Stroke? = nil, scene3D: Scene3D? = nil, shape3D: Shape3D? = nil, source: SourceXMLNode) { self.kind = kind; self.thickness = thickness; self.fill = fill; self.stroke = stroke; self.scene3D = scene3D; self.shape3D = shape3D; self.source = source }
    public static func == (a: ChartSurface, b: ChartSurface) -> Bool { a === b || (a.kind == b.kind && a.thickness == b.thickness && a.fill == b.fill && a.stroke == b.stroke && a.scene3D == b.scene3D && a.shape3D == b.shape3D && a.source == b.source) }
}
/// 軸の刻み・向き・交点・目盛・時間単位。nilは未指定。
public final class ChartAxisScale: Sendable, Equatable, Codable {
    public let majorUnit: Double?, minorUnit: Double?, crossesAt: Double?
    public let reversed: Bool?
    public let crosses: String?, majorTickMark: String?, minorTickMark: String?, tickLabelPosition: String?
    public let baseTimeUnit: String?, majorTimeUnit: String?, minorTimeUnit: String?
    public init(majorUnit: Double? = nil, minorUnit: Double? = nil, crossesAt: Double? = nil, reversed: Bool? = nil, crosses: String? = nil, majorTickMark: String? = nil, minorTickMark: String? = nil, tickLabelPosition: String? = nil, baseTimeUnit: String? = nil, majorTimeUnit: String? = nil, minorTimeUnit: String? = nil) { self.majorUnit = majorUnit; self.minorUnit = minorUnit; self.crossesAt = crossesAt; self.reversed = reversed; self.crosses = crosses; self.majorTickMark = majorTickMark; self.minorTickMark = minorTickMark; self.tickLabelPosition = tickLabelPosition; self.baseTimeUnit = baseTimeUnit; self.majorTimeUnit = majorTimeUnit; self.minorTimeUnit = minorTimeUnit }
    public static func == (a: ChartAxisScale, b: ChartAxisScale) -> Bool { a === b || (a.majorUnit == b.majorUnit && a.minorUnit == b.minorUnit && a.crossesAt == b.crossesAt && a.reversed == b.reversed && a.crosses == b.crosses && a.majorTickMark == b.majorTickMark && a.minorTickMark == b.minorTickMark && a.tickLabelPosition == b.tickLabelPosition && a.baseTimeUnit == b.baseTimeUnit && a.majorTimeUnit == b.majorTimeUnit && a.minorTimeUnit == b.minorTimeUnit) }
}
