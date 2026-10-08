import Foundation

/// 描画エンジンに依存しない座標計算。文字計測・自動改ページは行わない。
public enum Layout {
    public enum Alignment: Sendable { case left, horizontalCenter, right, top, verticalCenter, bottom }
    public enum Axis: Sendable { case horizontal, vertical }
    /// 指定矩形を均等なグリッドへ分割する。返却は行優先。
    public static func grid(in bounds: Rect, rows: Int, columns: Int, gap: Double = 0, insets: Insets = .zero) throws -> [Rect] {
        let b = bounds.inset(by: insets)
        guard rows > 0, columns > 0, rows <= 10_000, columns <= 10_000, rows <= 100_000 / columns,
              [b.x,b.y,b.width,b.height,gap,insets.top,insets.left,insets.bottom,insets.right].allSatisfy(\.isFinite), gap >= 0,
              b.width >= Double(columns - 1) * gap, b.height >= Double(rows - 1) * gap else { throw SlideError.invalidModel("グリッドのサイズ・行列数・余白が不正です") }
        let w = (b.width - Double(columns - 1) * gap) / Double(columns), h = (b.height - Double(rows - 1) * gap) / Double(rows)
        return (0..<rows).flatMap { row in (0..<columns).map { col in Rect(x: b.x + Double(col)*(w+gap), y: b.y + Double(row)*(h+gap), width: w, height: h) } }
    }
    /// frameを持つ要素を指定矩形の辺・中心へ揃える。
    public static func align(_ elements: inout [Element], to alignment: Alignment, in bounds: Rect) {
        for i in elements.indices {
            guard var f = elements[i].frame else { continue }
            switch alignment {
            case .left: f.x = bounds.minX
            case .horizontalCenter: f.x = bounds.midX - f.width / 2
            case .right: f.x = bounds.maxX - f.width
            case .top: f.y = bounds.minY
            case .verticalCenter: f.y = bounds.midY - f.height / 2
            case .bottom: f.y = bounds.maxY - f.height
            }
            elements[i].frame = f
        }
    }
    /// frameを持つ要素を配列順に、同じ隙間で指定矩形内へ置く。収まらない場合はthrow。
    public static func distribute(_ elements: inout [Element], along axis: Axis, in bounds: Rect) throws {
        func valid(_ frame: Rect) -> Bool {
            [frame.x, frame.y, frame.width, frame.height, frame.maxX, frame.maxY].allSatisfy(\.isFinite)
                && frame.width >= 0 && frame.height >= 0
        }
        guard valid(bounds), elements.allSatisfy({ $0.frame.map(valid) ?? true }) else {
            throw SlideError.invalidModel("均等配置の座標・寸法が不正です")
        }
        let indices = elements.indices.filter { elements[$0].frame != nil }
        guard !indices.isEmpty else { return }
        let horizontal = axis == .horizontal
        let length = horizontal ? bounds.width : bounds.height
        let total = indices.reduce(0.0) { $0 + (horizontal ? elements[$1].frame!.width : elements[$1].frame!.height) }
        guard length.isFinite, total.isFinite, total <= length else { throw SlideError.invalidModel("均等配置する要素が指定領域に収まりません") }
        var position = horizontal ? bounds.x : bounds.y
        let gap = indices.count > 1 ? (length - total) / Double(indices.count - 1) : 0
        for i in indices { var f = elements[i].frame!; if horizontal { f.x = position; position += f.width + gap } else { f.y = position; position += f.height + gap }; elements[i].frame = f }
    }
}
