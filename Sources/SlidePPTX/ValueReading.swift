import Foundation
import SlideCore

extension PPTXReader {
    func percentage(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let number = raw.hasSuffix("%") ? Double(raw.dropLast()).map { $0 / 100 } : Double(raw).map { $0 / 100_000 }
        return number.flatMap { $0.isFinite ? $0 : nil }
    }
    func spacing(_ node: MarkupNode?, part: String) -> TextSpacing? {
        guard let node else { return nil }
        if let points = node.child("spcPts")?.attr("val").flatMap(Double.init), points.isFinite { return .points(points / 100) }
        if let ratio = percentage(node.child("spcPct")?.attr("val")) { return .percentage(ratio) }
        warn(part, node, .uninterpretedFormatting, "間隔の値または単位が未解決です", feature: "TXT-009"); return nil
    }
    func paragraphStyle(_ pr: MarkupNode?, part: String) -> ParagraphStyle {
        var ps = ParagraphStyle(alignment: pr?.attr("algn").flatMap(TextAlignment.init), level: pr?.attr("lvl").flatMap(Int.init), leftMargin: pr?.attr("marL").flatMap(Double.init).map { $0 / 12_700 }, indent: pr?.attr("indent").flatMap(Double.init).map { $0 / 12_700 }, lineSpacingValue: spacing(pr?.child("lnSpc"), part: part), spaceBeforeValue: spacing(pr?.child("spcBef"), part: part), spaceAfterValue: spacing(pr?.child("spcAft"), part: part))
        if case .percentage(let v) = ps.lineSpacingValue { ps.lineSpacing = v }
        if case .points(let v) = ps.spaceBeforeValue { ps.spaceBefore = v }
        if case .points(let v) = ps.spaceAfterValue { ps.spaceAfter = v }
        if pr?.child("buNone") != nil { ps.bullet = Bullet.none }
        else if let b = pr?.child("buChar")?.attr("char") { ps.bullet = .character(b) }
        else if let b = pr?.child("buAutoNum"), let type = b.attr("type") { ps.bullet = .numbered(type, start: b.attr("startAt").flatMap(Int.init) ?? 1) }
        for c in pr?.children ?? [] where !["defRPr", "lnSpc", "spcBef", "spcAft", "buNone", "buChar", "buAutoNum"].contains(c.name) { warn(part, c, .uninterpretedFormatting) }
        if let pr { for key in pr.attributes.keys where !["algn", "lvl", "marL", "indent"].contains(key) { warnings.add(.uninterpretedFormatting, part: part, element: key, message: "段落属性を原本に保持します") } }
        return ps
    }
    func styleLevel(_ node: MarkupNode, part: String) -> TextStyleLevel {
        .init(paragraph: paragraphStyle(node, part: part), text: textStyle(node.child("defRPr"), part: part))
    }
    func listStyle(_ node: MarkupNode?, part: String) -> TextListStyle? {
        guard let node else { return nil }
        var levels: [Int: TextStyleLevel] = [:]
        for i in 0..<9 { if let level = node.child("lvl\(i + 1)pPr") { levels[i] = styleLevel(level, part: part) } }
        for child in node.children where child.name != "defPPr" && !(1...9).map({ "lvl\($0)pPr" }).contains(child.name) { warn(part, child, .uninterpretedFormatting) }
        return .init(defaultStyle: node.child("defPPr").map { styleLevel($0, part: part) }, levels: levels)
    }
    func styleReference(_ node: MarkupNode?, part: String) -> StyleReference? {
        node.map { .init(index: $0.attr("idx").flatMap(Int.init), color: color($0, part: part)) }
    }
    func effects(_ props: MarkupNode?, style: MarkupNode?, part: String) -> ElementEffects? {
        let reference = styleReference(style?.child("effectRef"), part: part)
        let list = props?.child("effectLst"), dag = props?.child("effectDag")
        guard list != nil || dag != nil || reference != nil else { return nil }
        var direct: [VisualEffect]? = list.map { _ in [] }
        for node in list?.children ?? [] {
            if node.isA, node.name == "outerShdw" {
                func n(_ key: String, _ divisor: Double) -> Double? { node.attr(key).flatMap(Double.init).map { $0 / divisor } }
                direct?.append(.outerShadow(.init(blurRadius: n("blurRad",12_700), distance: n("dist",12_700), direction: n("dir",60_000), scaleX: percentage(node.attr("sx")), scaleY: percentage(node.attr("sy")), skewX: n("kx",60_000), skewY: n("ky",60_000), alignment: node.attr("algn"), rotateWithShape: boolean(node.attr("rotWithShape")), color: color(node, part: part))))
            } else { direct?.append(.unsupported(name: node.name, xml: node.xml)); warn(part,node,.uninterpretedFormatting,"この効果の解釈・合成は未対応です",feature:"PNT-009") }
        }
        if let dag { direct = (direct ?? []) + [.unsupported(name: dag.name, xml: dag.xml)]; warn(part,dag,.uninterpretedFormatting,"効果DAGは未対応です",feature:"PNT-009") }
        return .init(direct: direct, reference: reference)
    }
    func customGeometry(_ node: MarkupNode?, part: String) throws -> CustomGeometry? {
        guard let node else { return nil }
        func guides(_ list: String) -> [GeometryGuide] { node.child(list)?.named("gd").map { .init(name: $0.attr("name") ?? "", formula: $0.attr("fmla") ?? "") } ?? [] }
        let gs = guides("gdLst"), adjustments = guides("avLst")
        if !gs.isEmpty || !adjustments.isEmpty { warn(part,node,.uninterpretedFormatting,"guide・adjustment式の評価は未対応です",feature:"GEO-004") }
        var paths: [GeometryPath] = []
        for path in node.child("pathLst")?.named("path") ?? [] {
            try Task.checkCancellation()
            var commands: [PathCommand] = []
            for command in path.children {
                try Task.checkCancellation()
                let points = command.named("pt").compactMap { point -> GeometryPoint? in
                    guard let x = point.attr("x"), let y = point.attr("y") else { return nil }
                    if Double(x) == nil || Double(y) == nil { warn(part,point,.uninterpretedFormatting,"パスのguide座標は未解決です",feature:"GEO-004") }
                    return .init(x:x,y:y)
                }
                switch command.isA ? command.name : "" {
                case "moveTo" where points.count == 1: commands.append(.move(points[0]))
                case "lnTo" where points.count == 1: commands.append(.line(points[0]))
                case "quadBezTo" where points.count == 2: commands.append(.quadratic(control: points[0], end: points[1]))
                case "cubicBezTo" where points.count == 3: commands.append(.cubic(control1: points[0], control2: points[1], end: points[2]))
                case "close": commands.append(.close)
                case "arcTo":
                    guard let w = command.attr("wR"), let h = command.attr("hR"), let start = command.attr("stAng"), let sweep = command.attr("swAng") else { commands.append(.unsupported(command.xml)); warn(part,command,.uninterpretedFormatting,"不正な円弧を保持します",feature:"GEO-004"); continue }
                    commands.append(.arc(widthRadius: w, heightRadius: h, startAngle: start, sweepAngle: sweep)); warn(part,command,.uninterpretedFormatting,"円弧の評価は未対応です",feature:"GEO-004")
                default: commands.append(.unsupported(command.xml)); warn(part,command,.uninterpretedFormatting,"不正または未対応のパス命令を保持します",feature:"GEO-004")
                }
            }
            paths.append(.init(width: path.attr("w").flatMap(Double.init), height: path.attr("h").flatMap(Double.init), fillMode: path.attr("fill"), stroke: boolean(path.attr("stroke")), extrusionOK: boolean(path.attr("extrusionOk")), commands: commands))
        }
        for child in node.children where !["pathLst","gdLst","avLst"].contains(child.name) { warn(part,child,.uninterpretedFormatting,"追加geometry情報を原本で保持します",feature:"GEO-004") }
        return .init(paths: paths, guides: gs, adjustments: adjustments, rawXML: node.xml)
    }
}
