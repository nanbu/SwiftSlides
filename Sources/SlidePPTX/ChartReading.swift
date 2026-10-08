import Foundation
import SlideCore

private let chartNamespaces = ["http://schemas.openxmlformats.org/drawingml/2006/chart", "http://purl.oclc.org/ooxml/drawingml/chart"]
extension PPTXReader {
    func partReference(_ id: String, rels: [String:Relationship], part: String, expected: String? = nil) throws -> PartReference {
        guard let rel = rels[id], expected == nil || rel.type == expected else { throw SlideError.invalidRelationship(part:part,detail:"型または参照先が不正: \(id)") }
        return .init(relationshipID:id,path:rel.path,externalTarget:rel.isExternal ? rel.target : nil)
    }
    func chart(_ graphic: MarkupNode?, rels: [String:Relationship], part: String) throws -> Chart? {
        guard let node = graphic?.children.first(where:{ chartNamespaces.contains($0.namespace) && $0.name == "chart" }) else { return nil }
        guard let rid = node.rel("id") else { throw SlideError.invalidRelationship(part:part,detail:"chartのrelationshipがありません") }
        let reference = try partReference(rid,rels:rels,part:part,expected:"chart")
        guard let path = reference.path else { warn(part,node,.unsupportedContent,"外部chartを取得しません",feature:"CHT-001"); return .init(part:reference,groups:[],axes:[],title:nil,legendPosition:nil,externalData:nil,rawXML:node.xml) }
        let root = try tree(path)
        guard chartNamespaces.contains(root.namespace), root.name == "chartSpace" else { throw SlideError.corruptedPackage("不正なchart: \(path)") }
        let ns = root.namespace
        func child(_ n: MarkupNode?, _ name: String) -> MarkupNode? { n?.child(name,ns:ns) }
        func val(_ n: MarkupNode?, _ name: String) -> String? { child(n,name)?.attr("val") }
        func data(_ container: MarkupNode?) throws -> ChartData? {
            guard let container else { return nil }
            let sources: [String:ChartData.Source] = ["strCache":.stringCache,"numCache":.numberCache,"strLit":.stringLiteral,"numLit":.numberLiteral,"multiLvlStrCache":.multiLevelStringCache]
            let ref = container.children.first { $0.namespace == ns && ["strRef","numRef","multiLvlStrRef"].contains($0.name) }
            let parent = ref ?? container
            guard let cache = parent.children.first(where:{ $0.namespace == ns && sources[$0.name] != nil }), let source = sources[cache.name] else {
                warn(path,container,.unsupportedContent,"chartのキャッシュが欠落または未対応です",feature:"CHT-004")
                guard let ref else { return nil }
                let source: ChartData.Source = ref.name == "numRef" ? .numberReference : ref.name == "multiLvlStrRef" ? .multiLevelStringReference : .stringReference
                return .init(source:source,formula:child(ref,"f")?.text,pointCount:nil,formatCode:nil,points:[],rawXML:container.xml)
            }
            func points(_ node: MarkupNode) throws -> [ChartPoint] {
                var points: [ChartPoint] = [], indices = Set<Int>()
                for point in node.children where point.namespace == ns && point.name == "pt" {
                    try Task.checkCancellation()
                    guard let index = point.attr("idx").flatMap(Int.init), index >= 0, indices.insert(index).inserted, let value = child(point,"v") else { throw SlideError.corruptedPackage("chartのcache pointが不正または重複しています") }
                    points.append(.init(index:index,text:value.text))
                    if source == .numberCache || source == .numberLiteral, points.last?.number == nil { warn(path,point,.unsupportedContent,"不正なchart数値を字句のまま保持します",feature:"CHT-004") }
                }
                return points
            }
            let values = try points(cache)
            var result = ChartData(source:source,formula:child(ref,"f")?.text,pointCount:val(cache,"ptCount").flatMap(Int.init),formatCode:child(cache,"formatCode")?.text,points:values,rawXML:container.xml)
            if source == .multiLevelStringCache { result.levels = try cache.children.filter { $0.namespace == ns && $0.name == "lvl" }.map(points) }
            if let raw = val(cache,"ptCount") {
                guard let count = Int(raw), count >= 0 else { throw SlideError.corruptedPackage("chart pointCount不正") }
                if (values + (result.levels ?? []).flatMap { $0 }).contains(where: { $0.index >= count }) { warn(path,cache,.unsupportedContent,"chartのpointCountとindexが不整合です",feature:"CHT-004") }
            }
            return result
        }
        let chartNode = child(root,"chart"), plot = child(chartNode,"plotArea")
        guard chartNode != nil, plot != nil else { throw SlideError.corruptedPackage("chartのplotAreaがありません") }
        var groups: [ChartGroup] = [], axes: [ChartAxis] = []
        for group in plot?.children ?? [] where group.namespace == ns {
            try Task.checkCancellation()
            if group.name.hasSuffix("Chart") {
                if !["barChart","lineChart","pieChart","areaChart","scatterChart","bubbleChart","doughnutChart","radarChart","stockChart","surfaceChart","bar3DChart","line3DChart","pie3DChart","area3DChart","surface3DChart","ofPieChart"].contains(group.name) { warn(path,group,.unsupportedContent,"このchart種別の表示は未対応です",feature:"CHT-001") }
                if let grouping = val(group,"grouping"), !["clustered","standard"].contains(grouping) { warn(path,group,.uninterpretedFormatting,"積上げ等のgroupingを保持します",feature:"CHT-001") }
                var series: [ChartSeries] = []
                for ser in group.children where ser.namespace == ns && ser.name == "ser" {
                    let tx = child(ser,"tx"), props = child(ser,"spPr")
                    var value = ChartSeries(index:val(ser,"idx").flatMap(Int.init),order:val(ser,"order").flatMap(Int.init),title:child(tx,"v")?.text,
                        titleData:try data(tx.flatMap { child($0,"strRef") == nil ? nil : $0 }),categories:try data(child(ser,"cat")),values:try data(child(ser,"val")),fill:try fill(props,part:path),stroke:stroke(props?.child("ln"),part:path),rawXML:ser.xml)
                    value.xValues = try data(child(ser,"xVal")); value.yValues = try data(child(ser,"yVal")); value.bubbleSizes = try data(child(ser,"bubbleSize"))
                    value.properties = try SourceXMLNode(ser); series.append(value)
                }
                var value = ChartGroup(kind:group.name,grouping:val(group,"grouping"),orientation:val(group,"barDir"),series:series,axisIDs:group.children.filter { $0.namespace == ns && $0.name == "axId" }.compactMap { $0.attr("val") },rawXML:group.xml)
                value.properties = try SourceXMLNode(group); groups.append(value)
                warn(path,group,.uninterpretedFormatting,"高度なchart書式・ラベルはXMLで保持します。表示は呼出側で判断してください",feature:"CHT-001")
            } else if ["catAx","valAx","dateAx","serAx"].contains(group.name) {
                let scaling = child(group,"scaling")
                var axis = ChartAxis(kind:group.name,id:val(group,"axId"),crossAxisID:val(group,"crossAx"),position:val(group,"axPos"),minimum:try finite(val(scaling,"min"),part:path,name:"axis min"),maximum:try finite(val(scaling,"max"),part:path,name:"axis max"),logarithmicBase:try finite(val(scaling,"logBase"),part:path,name:"axis logBase"),numberFormat:child(group,"numFmt")?.attr("formatCode"),isDeleted:boolean(val(group,"delete")),rawXML:group.xml)
                axis.properties = try SourceXMLNode(group)
                axis.scale = try .init(majorUnit: finite(val(group,"majorUnit"),part:path,name:"majorUnit"), minorUnit: finite(val(group,"minorUnit"),part:path,name:"minorUnit"), crossesAt: finite(val(group,"crossesAt"),part:path,name:"crossesAt"), reversed: val(scaling,"orientation").map { $0 == "maxMin" }, crosses: val(group,"crosses"), majorTickMark: val(group,"majorTickMark"), minorTickMark: val(group,"minorTickMark"), tickLabelPosition: val(group,"tickLblPos"), baseTimeUnit: val(group,"baseTimeUnit"), majorTimeUnit: val(group,"majorTimeUnit"), minorTimeUnit: val(group,"minorTimeUnit"))
                axes.append(axis)
                if val(scaling,"logBase") != nil { warn(path,group,.uninterpretedFormatting,"log軸を保持します。表示の評価は未対応です",feature:"CHT-001") }
            }
        }
        var external: PartReference?
        if let ext = child(root,"externalData"), let id = ext.rel("id") { external = try partReference(id,rels:relationships(from:path),part:path); warn(path,ext,.unsupportedContent,"外部・埋込workbookは再計算しません",feature:"CHT-004") }
        let title = child(chartNode,"title")?.descendants("t").map(\.text).joined()
        var result = Chart(part:reference,groups:groups,axes:axes,title:title,legendPosition:val(child(chartNode,"legend"),"legendPos"),externalData:external,rawXML:root.xml)
        if let view = child(chartNode, "view3D") {
            func n(_ name: String) throws -> Double? { try finite(val(view, name), part: path, name: name) }
            result.view3D = try .init(rotationX: n("rotX"), rotationY: n("rotY"), perspective: n("perspective"), depth: n("depthPercent").map { $0 / 100 }, height: n("hPercent").map { $0 / 100 }, rightAngleAxes: boolean(val(view,"rAngAx")), source: SourceXMLNode(view))
        }
        let surfaces = try ["floor", "sideWall", "backWall"].compactMap { name -> ChartSurface? in
            guard let node = child(chartNode, name) else { return nil }; let props = child(node, "spPr")
            return try .init(kind: name, thickness: finite(val(node, "thickness"), part: path, name: "thickness"), fill: fill(props, part: path), stroke: stroke(props?.child("ln"), part: path), scene3D: scene3D(props?.child("scene3d"), part: path), shape3D: shape3D(props?.child("sp3d"), part: path), source: SourceXMLNode(node))
        }
        result.surfaces = surfaces.isEmpty ? nil : surfaces
        result.properties = try SourceXMLNode(root)
        if let external {
            let bytes: Data?
            if let internalPath = external.path { bytes = try package.archive.read(internalPath) }
            else { bytes = try options.workbookProvider?(external) }
            if let bytes {
                guard bytes.starts(with: [0x50, 0x4b]) else { warn(path, root, .unsupportedContent, "XLSX以外のworkbookは参照と原本に保持します", feature: "CHT-004"); return result }
                let workbook = try WorkbookDataReader.readXLSX(bytes, limits: options.limits)
                try tableBudget.consume(workbook.sheets.reduce(0) { $0 + $1.cells.count }, limit: options.limits.maxTableCells)
                result.workbook = workbook
                func resolve(_ data: inout ChartData?) throws {
                    guard var value = data, let formula = value.formula else { return }
                    do {
                        let resolved = try workbook.resolve(formula, maxCells: options.limits.maxTableCells)
                        value.workbookPoints = resolved.points
                        let cache = Dictionary(uniqueKeysWithValues: value.points.map { ($0.index, $0.text) })
                        let actual = Dictionary(uniqueKeysWithValues: resolved.points.map { ($0.index, $0.text) })
                        let numeric = [.numberCache, .numberLiteral, .numberReference].contains(value.source)
                        let equal = cache.keys == actual.keys && cache.allSatisfy { key, cached in
                            guard let stored = actual[key] else { return false }
                            if numeric, let a = Double(cached), let b = Double(stored), a.isFinite, b.isFinite { return a == b }; return cached == stored
                        }
                        if !value.points.isEmpty && !equal { warn(path, root, .unsupportedContent, "chart cacheとworkbookの保存済み値が不一致です", feature: "CHT-004") }
                        data = value
                    } catch is CancellationError { throw CancellationError() }
                    catch SlideError.limitExceeded(let message) { throw SlideError.limitExceeded(message) }
                    catch { warn(path, root, .unsupportedContent, "workbook参照を解決できません: \(error)", feature: "CHT-004") }
                }
                for g in result.groups.indices { for s in result.groups[g].series.indices {
                    try resolve(&result.groups[g].series[s].titleData); try resolve(&result.groups[g].series[s].categories); try resolve(&result.groups[g].series[s].values)
                    try resolve(&result.groups[g].series[s].xValues); try resolve(&result.groups[g].series[s].yValues); try resolve(&result.groups[g].series[s].bubbleSizes)
                } }
            }
        }
        return result
    }
}
