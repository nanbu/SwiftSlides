import Foundation
import SlideCore

private let chartNS="urn:oasis:names:tc:opendocument:xmlns:chart:1.0"
extension ODPPageParser {
    func chartObject(_ node:MarkupNode) throws -> Chart? {
        guard let href=node.odf(ODF.xlink,"href") else {
            guard !node.children.isEmpty else { throw SlideError.corruptedPackage("ODP object参照なし") }
            return nil
        }
        let ref=try reference(href)
        guard let path=ref.path else { return nil }
        guard path.hasSuffix(".xml") else { return nil }
        let root=try MarkupNode.parse(archive.read(path),part:path,limits:options.limits)
        guard let chart=root.child("body",ns:ODF.office)?.child("chart",ns:ODF.office)?.child("chart",ns:chartNS) else { return nil }
        let plot=chart.child("plot-area",ns:chartNS)
        guard let plot else { throw SlideError.corruptedPackage("ODP chart plot-area不在") }
        let stylePath = (path as NSString).deletingLastPathComponent + "/styles.xml"
        let styleRoot = try archive.entries[stylePath].map { _ in try MarkupNode.parse(archive.read(stylePath), part: stylePath, limits: options.limits) } ?? root
        let chartStyles = try ODPStyleIndex(content: root, styles: styleRoot === root ? MarkupNode(name: "document-styles", namespace: ODF.office, qualifiedName: "office:document-styles") : styleRoot, limits: options.limits)
        func properties(_ node: MarkupNode) throws -> [String: String] {
            let resolved = try chartStyles.resolve(name: node.odf(chartNS,"style-name"), family: "chart")
            for unresolved in resolved.unresolved { warn(node, "未解決chart style: \(unresolved)") }
            return resolved.properties.merging(node.attributes) { _, direct in direct }
        }
        func numeric(_ props: [String: String], _ name: String) throws -> Double? {
            guard let raw = props[ODF.key(chartNS, name)] else { return nil }
            guard let n = Double(raw), n.isFinite else { throw SlideError.corruptedPackage("ODP chart数値: \(name)") }; return n
        }
        func flag(_ props: [String: String], _ name: String) throws -> Bool? {
            guard let raw = props[ODF.key(chartNS, name)] else { return nil }; guard ["true", "false", "1", "0"].contains(raw) else { throw SlideError.corruptedPackage("ODP chart真偽値") }; return raw == "true" || raw == "1"
        }
        let plotProperties = try properties(plot)
        var grid:[[TableCell]]=[]
        let localName=chart.child("table",ns:ODF.table)?.odf(ODF.table,"name")
        if let local=chart.child("table",ns:ODF.table) { grid=try table(local).rows }
        func range(_ raw:String?) -> [ChartPoint]? {
            guard let raw else { return nil }
            // quoteされたtable名を保ち、同じlocal tableの矩形だけを解決する。
            let terms=raw.split(separator:":",omittingEmptySubsequences:false)
            guard (1...2).contains(terms.count) else { return nil }
            func cell(_ value:Substring) -> (Int,Int)? {
                let components=value.split(separator:".",omittingEmptySubsequences:false)
                guard components.count == 2 else { return nil }
                let table=components[0].replacingOccurrences(of:"$",with:"").trimmingCharacters(in:CharacterSet(charactersIn:"'"))
                guard table.isEmpty || table == localName else { return nil }
                let token=components[1].replacingOccurrences(of:"$",with:"")
                let letters=token.prefix { $0.isASCII && $0.isLetter },digits=token.dropFirst(letters.count)
                guard !letters.isEmpty,!digits.isEmpty,digits.allSatisfy(\.isNumber),let row=Int(digits),row > 0 else { return nil }
                var column=0
                for scalar in letters.uppercased().unicodeScalars { guard column <= (Int.max-26)/26 else { return nil };column=column*26+Int(scalar.value-64) }
                return (row-1,column-1)
            }
            guard let start=cell(terms[0]),let end=cell(terms.count == 1 ? terms[0] : terms[1]),start.0 <= end.0,start.1 <= end.1,end.0 < grid.count,end.1 < (grid.first?.count ?? 0) else { return nil }
            var values:[ChartPoint]=[],index=0
            for row in start.0...end.0 {
                for column in start.1...end.1 {
                    let c=grid[row][column],value=c.value?.lexicalValue ?? (c.text.plainText.isEmpty ? nil : c.text.plainText)
                    if let value { values.append(.init(index:index,text:value)) };index += 1
                }
            }
            return values
        }
        func data(_ raw:String?,numeric:Bool) -> ChartData? {
            guard let raw else { return nil }
            let values=range(raw)
            if values == nil { warn(chart,"ODP chart rangeを解決できません: \(raw)") }
            return .init(source:numeric ? .numberReference : .stringReference,formula:raw,pointCount:nil,formatCode:nil,points:values ?? [],rawXML:chart.xml)
        }
        let categories=plot.descendants("categories",ns:chartNS).first?.odf(ODF.table,"cell-range-address")
        var groups:[ChartGroup]=[],axes:[ChartAxis]=[]
        for (index,series) in plot.children(chartNS,"series").enumerated() {
            let kind=series.odf(chartNS,"class") ?? chart.odf(chartNS,"class") ?? "",label=series.odf(chartNS,"label-cell-address")
            var value=ChartSeries(index:index,order:index,title:range(label)?.first?.text,titleData:data(label,numeric:false),categories:data(categories,numeric:false),values:data(series.odf(chartNS,"values-cell-range-address"),numeric:true),fill:nil,stroke:nil,rawXML:series.xml)
            value.properties=try SourceXMLNode(series)
            value.fill = try fill(properties(series))
            let domains=series.children(chartNS,"domain").compactMap { $0.odf(ODF.table,"cell-range-address") }
            if !domains.isEmpty { value.xValues=data(domains[0],numeric:true) }
            if domains.count > 1 { value.yValues=data(domains[1],numeric:true) }
            if let i=groups.firstIndex(where:{ $0.kind == kind }) { groups[i].series.append(value) }
            else { var group=ChartGroup(kind:kind,grouping:try flag(plotProperties,"percentage") == true ? "percentStacked" : flag(plotProperties,"stacked") == true ? "stacked" : nil,orientation:try flag(plotProperties,"vertical").map { $0 ? "bar" : "col" },series:[value],axisIDs:[],rawXML:plot.xml);group.properties=try SourceXMLNode(plot);groups.append(group) }
        }
        for axis in plot.children(chartNS,"axis") {
            let props = try properties(axis)
            var value = try ChartAxis(kind: axis.odf(chartNS,"dimension") ?? "", id: axis.odf(chartNS,"name"), crossAxisID: nil, position: props[ODF.key(chartNS,"axis-position")], minimum: numeric(props,"minimum"), maximum: numeric(props,"maximum"), logarithmicBase: flag(props,"logarithmic") == true ? 10 : nil, numberFormat: nil, isDeleted: nil, rawXML: axis.xml)
            if let min = value.minimum, let max = value.maximum, min > max { throw SlideError.corruptedPackage("ODP chart軸min/max") }
            let major = try numeric(props,"interval-major"), divisor = try numeric(props,"interval-minor-divisor")
            if let major, major <= 0 { throw SlideError.corruptedPackage("ODP chart major unit") }; if let divisor, divisor <= 0 { throw SlideError.corruptedPackage("ODP chart minor divisor") }
            value.scale = try .init(majorUnit: major, minorUnit: major.flatMap { m in divisor.map { m / $0 } }, crossesAt: numeric(props,"axis-position-value"), reversed: flag(props,"reverse-direction"), crosses: props[ODF.key(chartNS,"axis-position")], tickLabelPosition: props[ODF.key(chartNS,"label-position")])
            value.title = axis.child("title", ns: chartNS)?.descendants("p", ns: ODF.text).map(\.text).joined(separator: "\n")
            value.scaleType = try flag(props,"logarithmic").map { $0 ? "logarithmic" : "linear" }
            value.nativeProperties = props
            value.properties = try SourceXMLNode(axis); axes.append(value)
        }
        var result=Chart(part:ref,groups:groups,axes:axes,title:chart.child("title",ns:chartNS)?.descendants("p",ns:ODF.text).map(\.text).joined(separator:"\n"),legendPosition:chart.child("legend",ns:chartNS)?.odf(chartNS,"legend-position"),externalData:nil,rawXML:root.xml)
        result.properties=try SourceXMLNode(root)
        result.nativeProperties = plotProperties
        let surfaces = try ["wall", "floor"].compactMap { name -> ChartSurface? in
            guard let node = plot.child(name, ns: chartNS) else { return nil }; return try .init(kind: name, fill: fill(properties(node)), source: SourceXMLNode(node))
        }
        result.surfaces = surfaces.isEmpty ? nil : surfaces
        warn(node,"埋込ODP chartのlocal-table/rangeと原本書式を読みます。外部データ・再計算・描画は行いません")
        return result
    }
}
