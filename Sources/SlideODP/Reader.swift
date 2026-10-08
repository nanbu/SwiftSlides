import Foundation
import SlideCore

/// ODF ZIP presentationの読取専用codec。保存・変換は拒否する。
public struct ODPCodec: PresentationCodec {
    public let format = PresentationFormat.odp
    public init() {}
    public var capabilities: CodecCapabilities {
        .init(format:.odp,operations:[.inspect:.partial,.read:.partial,.create:.unsupported,.edit:.unsupported,.preserve:.preserveOnly,.convert:.unsupported,.render:.unsupported,.play:.unsupported],notes:"ODF 1.2/1.3/1.4 ZIPの基本読取。原本保持、書込は未提供。書式索引の限定解決を別途返す。",features:ODPFeatureCapabilities.features(for:.odp))
    }
    public func read(_ data: Data, options: ReadOptions = .init()) throws -> ReadResult { try ODPDocument(data,options:options).read() }
    public func inspect(_ data: Data, limits: PackageLimits = .init()) throws -> PresentationSummary { try ODPDocument(data,options:.init(limits:limits,includeNotes:false)).summary }
    public func write(_ presentation: Presentation, options: WriteOptions = .init()) throws -> WriteResult { throw SlideError.unsafeEdit("ODP codecは読取専用です。ODP保存・変換は未提供です") }
    /// 直接値と分離された書式索引。原本bytesから構築する。
    public func styleIndex(_ data: Data, limits: PackageLimits = .init()) throws -> ODPStyleIndex { try ODPDocument(data,options:.init(limits:limits)).styles }
}
extension Codec { public static let odp = Codec(ODPCodec()) }

struct ODPDocument: Sendable {
    let data: Data
    let archive: PackageArchive
    let options: ReadOptions
    let styles: ODPStyleIndex
    let pages: [String]
    let descriptors: [SlideDescriptor]
    let summary: PresentationSummary
    let initialWarnings: [SlideWarning]
    init(_ data: Data, options: ReadOptions) throws {
        self.data = data; self.options = options
        let archive = try PackageArchive(data,limits:options.limits); self.archive = archive
        guard String(data:try archive.read("mimetype"),encoding:.utf8) == ODF.mime else { throw SlideError.unknownFormat }
        func tree(_ part: String, rootName: String) throws -> MarkupNode {
            let node = try MarkupNode.parse(archive.read(part),part:part,limits:options.limits)
            guard node.namespace == ODF.office, node.name == rootName,
                  let version = node.odf(ODF.office,"version"), ["1.2","1.3","1.4"].contains(version) else { throw SlideError.unsupportedContainer("ODP root/version: \(part)") }
            return node
        }
        let manifest = try MarkupNode.parse(archive.read("META-INF/manifest.xml"),part:"META-INF/manifest.xml",limits:options.limits)
        guard manifest.namespace == ODF.manifest, manifest.name == "manifest" else { throw SlideError.corruptedPackage("不正なODF manifest") }
        guard let mv = manifest.odf(ODF.manifest,"version"), ["1.2","1.3","1.4"].contains(mv) else { throw SlideError.unsupportedContainer("ODF manifest version") }
        var types: [String:String] = [:]
        for entry in manifest.children(ODF.manifest,"file-entry") {
            guard let path = entry.odf(ODF.manifest,"full-path"), let type = entry.odf(ODF.manifest,"media-type"), types[path] == nil else { throw SlideError.corruptedPackage("不正または重複ODF manifest entry") }
            if !entry.descendants("encryption-data",ns:ODF.manifest).isEmpty { throw SlideError.unsupportedContainer("暗号化ODP") }
            if path != "/", !path.hasSuffix("/"), archive.entries[path] == nil { throw SlideError.missingPart(path) }
            types[path] = type
        }
        guard types["/"] == ODF.mime, types["content.xml"] == "text/xml", types["styles.xml"] == "text/xml" else { throw SlideError.corruptedPackage("必須ODP manifest entryがありません") }
        let content = try tree("content.xml",rootName:"document-content"), styleRoot = try tree("styles.xml",rootName:"document-styles")
        guard content.odf(ODF.office,"version") == styleRoot.odf(ODF.office,"version"), content.odf(ODF.office,"version") == mv else { throw SlideError.corruptedPackage("ODF version不一致") }
        let styles = try ODPStyleIndex(content:content,styles:styleRoot,limits:options.limits); self.styles = styles
        guard let body = content.child("body",ns:ODF.office), let presentation = body.child("presentation",ns:ODF.office) else { throw SlideError.corruptedPackage("ODP presentation本体がありません") }
        let pageNodes = presentation.children(ODF.draw,"page")
        guard let first = pageNodes.first else { throw SlideError.corruptedPackage("ODPページがありません") }
        let size = try styles.pageSize(master:first.odf(ODF.draw,"master-page-name"))
        var pages: [String] = [], descriptors: [SlideDescriptor] = [], ids: Set<String> = []
        let reservedPageIDs = Set(pageNodes.compactMap { $0.odf("http://www.w3.org/XML/1998/namespace","id") ?? $0.odf(ODF.draw,"id") })
        for (i,page) in pageNodes.enumerated() {
            try Task.checkCancellation()
            var id: String
            if let original = page.odf("http://www.w3.org/XML/1998/namespace","id") ?? page.odf(ODF.draw,"id") { id = original }
            else {
                id = "odf-page-\(i+1)"
                while reservedPageIDs.contains(id) || ids.contains(id) { id += "-generated" }
            }
            guard ids.insert(id).inserted else { throw SlideError.corruptedPackage("重複ODP page ID") }
            let pageSize = try styles.pageSize(master:page.odf(ODF.draw,"master-page-name"))
            guard abs(pageSize.width-size.width) < 0.00001, abs(pageSize.height-size.height) < 0.00001 else { throw SlideError.unsupportedContainer("異なるODPページ寸法") }
            pages.append(page.xml); descriptors.append(.init(id:id,name:page.odf(ODF.draw,"name") ?? "",index:i))
        }
        self.pages = pages; self.descriptors = descriptors
        var metadata = Metadata()
        if archive.entries["meta.xml"] != nil {
            let meta = try tree("meta.xml",rootName:"document-meta")
            if let node = meta.child("meta",ns:ODF.office) {
                metadata.title = node.child("title",ns:NS.dc)?.text; metadata.subject = node.child("subject",ns:NS.dc)?.text
                metadata.creator = node.child("creator",ns:NS.dc)?.text; metadata.description = node.child("description",ns:NS.dc)?.text
            }
        }
        let parts = archive.paths.map { path -> PackagePart in let e = archive.entries[path]!; return .init(path:path,contentType:types[path],compressedSize:e.compressedSize,expandedSize:e.expandedSize) }
        self.summary = .init(format:.odp,size:size,slideCount:pages.count,metadata:metadata,parts:parts)
        var warnings: [SlideWarning] = []
        for node in presentation.children where !(node.namespace == ODF.draw && node.name == "page") {
            warnings.append(.init(code:.unsupportedContent,part:"content.xml",element:node.name,message:"ページ以外のpresentation内容を原本に保持します"))
        }
        for node in content.children where !["automatic-styles","font-face-decls","body"].contains(node.name) || node.namespace != ODF.office {
            warnings.append(.init(code:.unsupportedContent,part:"content.xml",element:node.name,message:"未解釈のODP文書内容を原本に保持します"))
        }
        warnings.append(.init(code:.uninterpretedFormatting,part:"styles.xml",element:"master-styles",message:"master上の図形・継承外観はモデルへ投影しません。style索引は限定解決です"))
        for part in parts where !["mimetype","content.xml","styles.xml","meta.xml","META-INF/manifest.xml"].contains(part.path) && !(part.contentType?.hasPrefix("image/") ?? false) && !part.path.hasSuffix("/") {
            warnings.append(.init(code:.unsupportedPart,part:part.path,element:"part",message:"未解釈ODPパーツを原本に保持します"))
        }
        initialWarnings = warnings
    }
    func slide(at index: Int) throws -> SlideReadResult {
        guard pages.indices.contains(index) else { throw SlideError.invalidModel("reader index範囲外") }
        return try decode(index,options:options).0
    }
    private func decode(_ index: Int, options: ReadOptions) throws -> (SlideReadResult,Int,Int) {
        let node = try MarkupNode.parse(Data(pages[index].utf8),part:"content.xml",limits:options.limits)
        let parser = ODPPageParser(archive:archive,styles:styles,options:options,slideID:descriptors[index].id,contentTypes:Dictionary(uniqueKeysWithValues:summary.parts.compactMap { part in part.contentType.map { (part.path,$0) } }))
        return (try parser.read(node,descriptor:descriptors[index]),parser.tableCells,parser.textBytes)
    }
    func read() throws -> ReadResult {
        var slides: [Slide] = [], warnings = initialWarnings
        var remainingCells = options.limits.maxTableCells, remainingText = options.limits.maxExpandedBytes
        for index in pages.indices {
            var bounded = options; bounded.limits.maxTableCells = remainingCells; bounded.limits.maxExpandedBytes = remainingText
            let (result,cells,text) = try decode(index,options:bounded)
            remainingCells -= cells; remainingText -= text
            slides.append(result.slide); warnings += result.warnings
        }
        var p = Presentation(size:summary.size,slides:slides,metadata:summary.metadata)
        let storage = Preservation(data:data,archive:archive,mainPart:"content.xml",limits:options.limits,originalSize:summary.size,originalSlides:slides,originalMetadata:summary.metadata,originalTheme:p.theme,slidePaths:Dictionary(uniqueKeysWithValues:slides.map { ($0.id,"content.xml") }),notesPaths:[:],notesOmitted:!options.includeNotes)
        p.preserve(storage,format:.odp,warnings:warnings,parts:summary.parts,themes:[])
        return .init(presentation:p)
    }
}

private final class ODPPageParser {
    let archive: PackageArchive
    let styles: ODPStyleIndex
    let options: ReadOptions
    let slideID: String
    let warnings = WarningCollector()
    var ids: Set<String> = []
    var nextID = 0
    var reservedIDs: Set<String> = []
    var tableCells = 0
    var textBytes = 0
    let contentTypes: [String:String]
    init(archive: PackageArchive, styles: ODPStyleIndex, options: ReadOptions, slideID: String, contentTypes: [String:String]) { self.archive = archive; self.styles = styles; self.options = options; self.slideID = slideID; self.contentTypes = contentTypes }
    func warn(_ node: MarkupNode, _ message: String, code: SlideWarning.Code = .unsupportedContent, id: String? = nil) {
        warnings.add(code,part:"content.xml",element:node.name,message:message,slideID:slideID,elementID:id)
    }
    func read(_ node: MarkupNode, descriptor: SlideDescriptor) throws -> SlideReadResult {
        func reserve(_ node: MarkupNode) {
            if let id = node.odf("http://www.w3.org/XML/1998/namespace","id") ?? node.odf(ODF.draw,"id") { reservedIDs.insert(id) }
            for child in node.children { reserve(child) }
        }
        reserve(node)
        var elements: [Element] = [], notes: TextBody?
        for child in node.children {
            if child.namespace == ODF.presentation, child.name == "notes" {
                if options.includeNotes {
                    let paragraphs = try child.descendants("p",ns:ODF.text).map { try paragraph($0) }; notes = .init(paragraphs:paragraphs)
                } else { warn(child,"ノート読取を省略しました。原本は保持します",code:.notesOmitted) }
            } else { elements.append(try element(child)) }
        }
        var slide = Slide(id:descriptor.id,name:descriptor.name,elements:elements,notes:notes)
        let resolved = try styles.resolve(name:node.odf(ODF.draw,"style-name"),family:"drawing-page",masterPage:node.odf(ODF.draw,"master-page-name"))
        for ref in resolved.unresolved { warn(node,"未解決ODP書式参照: \(ref)",code:.uninterpretedFormatting) }
        if resolved.properties[ODF.key(ODF.presentation,"visibility")] == "hidden" { slide.isHidden = true }
        slide.background = try fill(styles.direct(name:node.odf(ODF.draw,"style-name"),family:"drawing-page"))
        if !resolved.properties.isEmpty { warn(node,"ページ書式は原本とstyle索引に保持します。モデル背景は直接値のみです",code:.uninterpretedFormatting) }
        return .init(slide:slide,warnings:warnings.result)
    }
    func element(_ node: MarkupNode) throws -> Element {
        try Task.checkCancellation(); nextID += 1
        var id: String
        if let original = node.odf("http://www.w3.org/XML/1998/namespace","id") ?? node.odf(ODF.draw,"id") { id = original }
        else {
            id = "odf-element-\(nextID)"
            while reservedIDs.contains(id) || ids.contains(id) { id += "-generated" }
        }
        guard ids.insert(id).inserted else { throw SlideError.corruptedPackage("重複ODP element ID: \(id)") }
        let name = node.odf(ODF.draw,"name") ?? ""
        func opaque(_ message: String) throws -> Element {
            warn(node,message,id:id); var e = Element(id:id,name:name,kind:.opaque,geometry:nil)
            if node.namespace == ODF.draw {
                let paragraphs = node.children.filter { $0.namespace == ODF.text && ["p","h"].contains($0.name) }
                if !paragraphs.isEmpty { e.text = .init(paragraphs:try paragraphs.map { try paragraph($0) }) }
            }
            e.setRawXML(node.xml); return e
        }
        guard node.namespace == ODF.draw else { return try opaque("未対応namespace/要素を原本に保持します") }
        if node.odf(ODF.draw,"transform") != nil { return try opaque("transform付き要素は未解釈として保持します") }
        let styleName = node.odf(ODF.draw,"style-name")
        if let styleName {
            let resolved = try styles.resolve(name:styleName,family:"graphic")
            warn(node,resolved.unresolved.isEmpty ? "継承書式はstyle索引に保持します。モデルは直接値のみです" : "未解決style: \(resolved.unresolved.joined(separator:", "))",code:.uninterpretedFormatting,id:id)
        }
        if node.name == "g" {
            var e = Element(id:id,name:name,kind:.group,geometry:nil,children:try node.children.map { try element($0) }); e.setRawXML(node.xml); return e
        }
        let allowed = ["rect","ellipse","line","connector","frame"]
        guard allowed.contains(node.name) else { return try opaque("未対応ODP図形/geometryを保持します") }
        var frame: Rect?
        if node.name == "line" || node.name == "connector" {
            let attrs = ["x1","y1","x2","y2"].map { node.odf(ODF.svg,$0) }
            guard attrs.allSatisfy({ $0 != nil }) else { return try opaque("endpointを解決できない線を保持します") }
            let values = try attrs.map { try ODF.length($0!) }
            frame = .init(x:min(values[0],values[2]),y:min(values[1],values[3]),width:abs(values[2]-values[0]),height:abs(values[3]-values[1]))
        } else {
            let attrs = ["x","y","width","height"].map { node.odf(ODF.svg,$0) }
            if attrs.allSatisfy({ $0 != nil }) {
                let values = try attrs.map { try ODF.length($0!) }
                guard values[2] >= 0, values[3] >= 0 else { throw SlideError.corruptedPackage("負のODP図形寸法") }
                frame = .init(x:values[0],y:values[1],width:values[2],height:values[3])
            } else { warn(node,"図形位置/寸法は未解決です",code:.uninterpretedFormatting,id:id) }
        }
        var e = Element(id:id,name:name,frame:frame,geometry:node.name == "ellipse" ? .ellipse : .rectangle,fill:try fill(styles.direct(name:styleName,family:"graphic")))
        if node.name == "line" || node.name == "connector" {
            e.kind = .connector; e.geometry = .line
            e.flipHorizontal = try ODF.length(node.odf(ODF.svg,"x2")!) < ODF.length(node.odf(ODF.svg,"x1")!)
            e.flipVertical = try ODF.length(node.odf(ODF.svg,"y2")!) < ODF.length(node.odf(ODF.svg,"y1")!)
        }
        if node.name == "frame" {
            let children = node.children.filter { !($0.namespace == ODF.svg && ["title","desc"].contains($0.name)) }
            guard children.count == 1, let child = children.first else { return try opaque("複数内容/空のframeを保持します") }
            if child.namespace == ODF.draw, child.name == "image" {
                guard let href = child.odf(ODF.xlink,"href") else { throw SlideError.corruptedPackage("画像参照がありません") }
                if href.contains(":"), !href.hasPrefix("./") { return try opaque("外部画像は取得せず保持します") }
                var path = href.hasPrefix("./") ? String(href.dropFirst(2)) : href
                guard let decoded = path.removingPercentEncoding else { throw SlideError.corruptedPackage("画像URI escape不正") }; path = decoded
                guard !path.hasPrefix("/"), !path.split(separator:"/").contains(".."), archive.entries[path] != nil else { throw SlideError.missingPart(path) }
                e.kind = .image; e.geometry = nil; e.image = .init(path:path,contentType:contentTypes[path],alternativeText:node.child("desc",ns:ODF.svg)?.text ?? "")
            } else if child.namespace == ODF.draw, child.name == "text-box" {
                e.isTextBox = true; e.text = try text(child)
            } else if child.namespace == ODF.table, child.name == "table" {
                e.kind = .table; e.geometry = nil; e.table = try table(child)
            } else { return try opaque("埋込object/未対応frameを保持します") }
        } else {
            let paragraphs = node.children.filter { $0.namespace == ODF.text && ["p","h","list"].contains($0.name) }
            if !paragraphs.isEmpty { e.text = try text(node) }
            for child in node.children where child.namespace != ODF.text || !["p","h","list"].contains(child.name) { warn(child,"未対応図形内容を原本に保持します",id:id) }
        }
        e.setRawXML(node.xml); return e
    }
    func fill(_ attrs: [String:String]) throws -> Fill? {
        guard let kind = attrs[ODF.key(ODF.draw,"fill")] else { return nil }
        if kind == "none" { return Fill.none }
        if kind == "solid", let value = attrs[ODF.key(ODF.draw,"fill-color")] { return .solid(try color(value)) }
        return nil
    }
    func color(_ value: String) throws -> Color {
        guard value.count == 7, value.first == "#", value.dropFirst().allSatisfy({ $0.isHexDigit }) else { throw SlideError.corruptedPackage("不正なODP色") }
        return .rgb(String(value.dropFirst()).uppercased())
    }
    func textStyle(_ node: MarkupNode) throws -> TextStyle {
        var result = TextStyle()
        let family = ["p","h"].contains(node.name) ? "paragraph" : "text"
        let properties = styles.direct(name:node.odf(ODF.text,"style-name"),family:family)
        func property(_ name: String) -> String? { properties[ODF.key(ODF.fo,name)] }
        if let size = property("font-size") {
            if size.hasSuffix("%") { warn(node,"相対font-sizeは未解決です",code:.uninterpretedFormatting) }
            else { let points = try ODF.length(size); guard points > 0 else { throw SlideError.corruptedPackage("不正なODP文字サイズ") }; result.font.size = points }
        }
        result.font.family = property("font-family")
        if let value = property("font-weight"), ["bold","normal"].contains(value) { result.bold = value == "bold" }
        if let value = property("font-style"), ["italic","normal"].contains(value) { result.italic = value == "italic" }
        if let value = property("color") { result.color = try color(value) }
        result.language = property("language")
        if node.odf(ODF.text,"style-name") != nil { warn(node,"文字style参照は原本とstyle索引に保持します",code:.uninterpretedFormatting) }
        return result
    }
    func text(_ node: MarkupNode) throws -> TextBody {
        var paragraphs: [Paragraph] = []
        for child in node.children {
            if child.namespace == ODF.text, ["p","h"].contains(child.name) { paragraphs.append(try paragraph(child)) }
            else if child.namespace == ODF.text, child.name == "list" {
                warn(child,"listの箇条書き書式を保持します",code:.uninterpretedFormatting)
                paragraphs += try child.descendants("p",ns:ODF.text).map { try paragraph($0) }
            } else { warn(child,"未対応テキスト内容を原本に保持します") }
        }
        return .init(paragraphs:paragraphs)
    }
    func paragraph(_ node: MarkupNode) throws -> Paragraph {
        var runs: [TextRun] = []
        let base = try textStyle(node)
        func append(_ value: String, style: TextStyle, link: Link?) throws {
            let count = value.utf8.count, budget = min(options.limits.maxPartBytes,options.limits.maxExpandedBytes)
            guard count <= budget - textBytes else { throw SlideError.limitExceeded("ODP表示文字の展開予算") }
            textBytes += count; runs.append(.init(value,style:style,link:link))
        }
        func visit(_ node: MarkupNode, style: TextStyle, link: Link?) throws {
            for item in node.content {
                switch item {
                case .text(let value): try append(value,style:style,link:link)
                case .node(let child):
                    guard child.namespace == ODF.text else { warn(child,"未知inlineを原本に保持します"); continue }
                    switch child.name {
                    case "s":
                        let count: Int
                        if let raw = child.odf(ODF.text,"c") { guard let n = Int(raw), n > 0, n <= options.limits.maxPartBytes else { throw SlideError.limitExceeded("ODP text:s") }; count = n } else { count = 1 }
                        guard count <= options.limits.maxPartBytes - runs.reduce(0, { $0 + $1.text.utf8.count }) else { throw SlideError.limitExceeded("ODP展開文字数") }
                        try append(String(repeating:" ",count:count),style:style,link:link)
                    case "tab": try append("\t",style:style,link:link)
                    case "line-break": try append("\n",style:style,link:link)
                    case "span":
                        let direct = try textStyle(child)
                        var merged = style
                        if let family = direct.font.family { merged.font.family = family }; if let size = direct.font.size { merged.font.size = size }
                        if let bold = direct.bold { merged.bold = bold }; if let italic = direct.italic { merged.italic = italic }; if let color = direct.color { merged.color = color }
                        try visit(child,style:merged,link:link)
                    case "a":
                        guard let href = child.odf(ODF.xlink,"href") else { throw SlideError.corruptedPackage("ODPリンク参照がありません") }
                        try visit(child,style:style,link:href.hasPrefix("#") ? .slide(String(href.dropFirst())) : .external(href))
                    default: warn(child,"未対応inlineの表示文字だけを投影します"); try visit(child,style:style,link:link)
                    }
                }
            }
        }
        try visit(node,style:base,link:nil)
        var p = Paragraph(runs:runs)
        if let align = styles.direct(name:node.odf(ODF.text,"style-name"),family:"paragraph")[ODF.key(ODF.fo,"text-align")] { p.style.alignment = ["left":.left,"start":.left,"center":.center,"right":.right,"end":.right,"justify":.justified][align] }
        return p
    }
    func repeated(_ node: MarkupNode, _ name: String) throws -> Int {
        guard options.limits.maxTableCells > 0 else { throw SlideError.limitExceeded("ODP table予算") }
        guard let raw = node.odf(ODF.table,name) else { return 1 }
        guard let n = Int(raw), n > 0, n <= options.limits.maxTableCells else { throw SlideError.limitExceeded("ODP table反復") }; return n
    }
    func table(_ node: MarkupNode) throws -> Table {
        var rows: [[TableCell]] = [], heights: [Double] = [], widths: [Double] = []
        func dimension(_ node: MarkupNode, family: String, name: String) throws -> Double {
            let resolved = try styles.resolve(name:node.odf(ODF.table,"style-name"),family:family)
            if let raw = resolved.properties[ODF.key(ODF.style,name)] { let value = try ODF.length(raw); guard value >= 0 else { throw SlideError.corruptedPackage("負のODP表寸法") }; return value }
            warn(node,"表の\(name)は未解決で0として投影します",code:.uninterpretedFormatting); return 0
        }
        for column in node.children(ODF.table,"table-column") {
            let n = try repeated(column,"number-columns-repeated"), width = try dimension(column,family:"table-column",name:"column-width")
            guard n <= options.limits.maxTableCells - widths.count else { throw SlideError.limitExceeded("ODP table列数") }
            widths += Array(repeating:width,count:n)
        }
        let rowNodes = node.children.flatMap { child -> [MarkupNode] in
            if child.namespace == ODF.table, child.name == "table-row" { return [child] }
            if child.namespace == ODF.table, ["table-header-rows","table-rows","table-row-group"].contains(child.name) { return child.descendants("table-row",ns:ODF.table) }
            return []
        }
        for row in rowNodes {
            var cells: [TableCell] = []
            for cell in row.children where cell.namespace == ODF.table && ["table-cell","covered-table-cell"].contains(cell.name) {
                let repeatCount = try repeated(cell,"number-columns-repeated")
                guard repeatCount <= options.limits.maxTableCells - cells.count else { throw SlideError.limitExceeded("ODP tableセル数") }
                var value = TableCell(); value.text = try text(cell); value.isMergeContinuation = cell.name == "covered-table-cell"
                for (key,isRow) in [("number-rows-spanned",true),("number-columns-spanned",false)] {
                    if let raw = cell.odf(ODF.table,key) { guard let n = Int(raw), n > 0, n <= options.limits.maxTableCells else { throw SlideError.corruptedPackage("ODP table span") }; if isRow { value.rowSpan = n } else { value.columnSpan = n } }
                }
                value.formula = cell.odf(ODF.table,"formula")
                if let type = cell.odf(ODF.office,"value-type") {
                    let attr = ["float":"value", "percentage":"value", "currency":"value", "boolean":"boolean-value", "date":"date-value", "time":"time-value", "string":"string-value"][type]
                    value.value = .init(type:type,lexicalValue:attr.flatMap { cell.odf(ODF.office,$0) },currency:cell.odf(ODF.office,"currency"))
                    if attr == nil { warn(cell,"未知のセル型を字句値として保持します") }
                    else if !["string","void"].contains(type), value.value?.lexicalValue == nil { warn(cell,"型付きセルのキャッシュがありません") }
                }
                if value.formula != nil { warn(cell,"式とキャッシュを読みます。式は再計算しません") }
                value.fill = try fill(styles.direct(name:cell.odf(ODF.table,"style-name"),family:"table-cell"))
                cells += Array(repeating:value,count:repeatCount)
            }
            let n = try repeated(row,"number-rows-repeated")
            guard !cells.isEmpty, n <= (options.limits.maxTableCells - tableCells) / cells.count else { throw SlideError.limitExceeded("ODP table反復展開予算") }
            tableCells += n * cells.count
            let h = try dimension(row,family:"table-row",name:"row-height")
            rows += Array(repeating:cells,count:n); heights += Array(repeating:h,count:n)
        }
        guard let first = rows.first, rows.allSatisfy({ $0.count == first.count }) else { throw SlideError.corruptedPackage("空または非矩形ODP table") }
        if widths.isEmpty { widths = Array(repeating:0,count:first.count); warn(node,"列幅を解決できない表を0幅として投影します",code:.uninterpretedFormatting) }
        guard widths.count == first.count else { throw SlideError.corruptedPackage("ODP table列宣言とセル数が不一致") }
        return .init(columnWidths:widths,rowHeights:heights,rows:rows,styleID:node.odf(ODF.table,"style-name"))
    }
}


extension ODPCodec: SlideReadingCodec {
    public func openSlides(_ data: Data, options: ReadOptions) throws -> any PresentationSlideSource { try ODPDocument(data,options:options) }
}
extension ODPDocument: PresentationSlideSource {
    var slideDescriptors: [SlideDescriptor] { descriptors }
    func asset(at path: String) throws -> Data { try archive.read(path) }
}
