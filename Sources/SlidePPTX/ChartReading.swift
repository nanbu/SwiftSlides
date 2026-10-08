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
            var points: [ChartPoint] = [], indices: Set<Int> = []
            for point in cache.children where point.namespace == ns && point.name == "pt" {
                try Task.checkCancellation()
                guard let index = point.attr("idx").flatMap(Int.init), index >= 0, indices.insert(index).inserted, let value = child(point,"v") else { throw SlideError.corruptedPackage("chartのcache pointが不正または重複しています") }
                points.append(.init(index:index,text:value.text))
                if source == .numberCache || source == .numberLiteral, points.last?.number == nil { warn(path,point,.unsupportedContent,"不正なchart数値を字句のまま保持します",feature:"CHT-004") }
            }
            if let count = val(cache,"ptCount").flatMap(Int.init), count < 0 || points.contains(where: { $0.index >= count }) { warn(path,cache,.unsupportedContent,"chartのpointCountとindexが不整合です",feature:"CHT-004") }
            if source == .multiLevelStringCache { warn(path,cache,.unsupportedContent,"多段カテゴリはXMLで保持します",feature:"CHT-004") }
            return .init(source:source,formula:child(ref,"f")?.text,pointCount:val(cache,"ptCount").flatMap(Int.init),formatCode:child(cache,"formatCode")?.text,points:points,rawXML:container.xml)
        }
        let chartNode = child(root,"chart"), plot = child(chartNode,"plotArea")
        guard chartNode != nil, plot != nil else { throw SlideError.corruptedPackage("chartのplotAreaがありません") }
        var groups: [ChartGroup] = [], axes: [ChartAxis] = []
        for group in plot?.children ?? [] where group.namespace == ns {
            try Task.checkCancellation()
            if group.name.hasSuffix("Chart") {
                if !["barChart","lineChart","pieChart"].contains(group.name) { warn(path,group,.unsupportedContent,"このchart種別の表示は未対応です",feature:"CHT-001") }
                if let grouping = val(group,"grouping"), !["clustered","standard"].contains(grouping) { warn(path,group,.uninterpretedFormatting,"積上げ等のgroupingを保持します",feature:"CHT-001") }
                var series: [ChartSeries] = []
                for ser in group.children where ser.namespace == ns && ser.name == "ser" {
                    let tx = child(ser,"tx"), props = child(ser,"spPr")
                    series.append(.init(index:val(ser,"idx").flatMap(Int.init),order:val(ser,"order").flatMap(Int.init),title:child(tx,"v")?.text,
                        titleData:try data(tx.flatMap { child($0,"strRef") == nil ? nil : $0 }),categories:try data(child(ser,"cat")),values:try data(child(ser,"val")),fill:try fill(props,part:path),stroke:stroke(props?.child("ln"),part:path),rawXML:ser.xml))
                }
                groups.append(.init(kind:group.name,grouping:val(group,"grouping"),orientation:val(group,"barDir"),series:series,axisIDs:group.children.filter { $0.namespace == ns && $0.name == "axId" }.compactMap { $0.attr("val") },rawXML:group.xml))
                warn(path,group,.uninterpretedFormatting,"高度なchart書式・ラベルはXMLで保持します。表示は呼出側で判断してください",feature:"CHT-001")
            } else if ["catAx","valAx","dateAx","serAx"].contains(group.name) {
                let scaling = child(group,"scaling")
                axes.append(.init(kind:group.name,id:val(group,"axId"),crossAxisID:val(group,"crossAx"),position:val(group,"axPos"),minimum:val(scaling,"min").flatMap(Double.init),maximum:val(scaling,"max").flatMap(Double.init),logarithmicBase:val(scaling,"logBase").flatMap(Double.init),numberFormat:child(group,"numFmt")?.attr("formatCode"),isDeleted:boolean(val(group,"delete")),rawXML:group.xml))
                if val(scaling,"logBase") != nil { warn(path,group,.uninterpretedFormatting,"log軸を保持します。表示の評価は未対応です",feature:"CHT-001") }
            }
        }
        var external: PartReference?
        if let ext = child(root,"externalData"), let id = ext.rel("id") { external = try partReference(id,rels:relationships(from:path),part:path); warn(path,ext,.unsupportedContent,"外部・埋込workbookは再計算しません",feature:"CHT-004") }
        let title = child(chartNode,"title")?.descendants("t").map(\.text).joined()
        return .init(part:reference,groups:groups,axes:axes,title:title,legendPosition:val(child(chartNode,"legend"),"legendPos"),externalData:external,rawXML:root.xml)
    }
}
