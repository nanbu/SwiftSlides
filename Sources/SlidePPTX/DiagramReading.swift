import Foundation
import SlideCore

private let diagramNamespaces = ["http://schemas.openxmlformats.org/drawingml/2006/diagram", "http://purl.oclc.org/ooxml/drawingml/diagram"]
private let drawingNamespace = "http://schemas.microsoft.com/office/drawing/2008/diagram"
extension PPTXReader {
    func diagram(_ graphic: MarkupNode?, rels: [String:Relationship], part: String) throws -> Diagram? {
        guard let node = graphic?.children.first(where:{ diagramNamespaces.contains($0.namespace) && $0.name == "relIds" }) else { return nil }
        func reference(_ key: String, _ expected: String) throws -> PartReference? {
            guard let id = node.rel(key) else { return nil }; return try partReference(id,rels:rels,part:part,expected:expected)
        }
        let data = try reference("dm","diagramData"), layout = try reference("lo","diagramLayout"), quickStyle = try reference("qs","diagramQuickStyle"), colors = try reference("cs","diagramColors")
        var drawing: PartReference?, texts: [String] = [], dataXML: String?, projected: [Element] = [], frame: Rect?, childFrame: Rect?
        if let path = data?.path {
            guard path != part else { throw SlideError.corruptedPackage("循環したdiagram参照") }
            let root = try tree(path)
            guard diagramNamespaces.contains(root.namespace), root.name == "dataModel" else { throw SlideError.corruptedPackage("不正なdiagram data: \(path)") }
            dataXML = root.xml; texts = root.descendants("t").map(\.text)
            let dataRels = try relationships(from:path)
            let extensions = root.descendants("dataModelExt",ns:drawingNamespace)
            if extensions.count > 1 { warn(path,root,.unsupportedContent,"複数のdiagram drawing参照を解決できません",feature:"OBJ-001") }
            else if let ext = extensions.first, let id = ext.attr("relId") ?? ext.rel("id") {
                drawing = try partReference(id,rels:dataRels,part:path)
                if let target = drawing?.path {
                    guard target != path, target != part else { throw SlideError.corruptedPackage("循環したdiagram drawing参照") }
                    let saved = try tree(target)
                    guard saved.namespace == drawingNamespace, saved.name == "drawing", let tree = saved.child("spTree",ns:drawingNamespace) else { throw SlideError.corruptedPackage("不正なdiagram drawing: \(target)") }
                    // Office diagramのshape要素だけを共通parserへ投影。未知のgraphicFrame等はopaqueのまま。
                    let shapeNames: Set<String> = ["spTree","sp","grpSp","cxnSp","nvSpPr","nvGrpSpPr","nvCxnSpPr","cNvPr","cNvSpPr","cNvGrpSpPr","cNvCxnSpPr","nvPr","spPr","grpSpPr","txBody","style"]
                    func normalize(_ source: MarkupNode) throws -> MarkupNode {
                        try Task.checkCancellation()
                        let convert = source.namespace == drawingNamespace && shapeNames.contains(source.name)
                        let n = MarkupNode(name:source.name,namespace:convert ? NS.p : source.namespace,qualifiedName:convert ? "p:" + source.name : source.qualifiedName,attributes:source.attributes,attributeNames:source.attributeNames,namespaces:source.namespaces)
                        if convert { n.namespaces["p"] = NS.p }
                        n.content = try source.content.map { item in switch item { case .text(let text): return .text(text); case .node(let child): return .node(try normalize(child)) } }; return n
                    }
                    let normalized = try normalize(tree), transform = normalized.child("grpSpPr")?.child("xfrm")
                    frame = rect(transform); childFrame = rect(transform,offset:"chOff",extent:"chExt")
                    var ids: Set<String> = []
                    projected = try elements(normalized,rels:relationships(from:target),part:target,slideID:nil,ids:&ids)
                } else { warn(path,ext,.unsupportedContent,"外部diagram drawingを取得しません",feature:"OBJ-001") }
            }
        }
        if drawing?.path == nil { warn(part,node,.unsupportedContent,"保存済みdiagram drawingがありません。データ文字を保持し、自動配置はしません",feature:"OBJ-001") }
        return .init(data:data,layout:layout,quickStyle:quickStyle,colors:colors,drawing:drawing,drawingFrame:frame,drawingChildFrame:childFrame,elements:projected,dataTexts:texts,dataXML:dataXML)
    }
}
