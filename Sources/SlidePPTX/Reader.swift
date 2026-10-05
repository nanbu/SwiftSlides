import Foundation
import SlideCore

/// PowerPointのOPCとPresentationMLを読み書きする形式別コーデック。
public struct PPTXCodec: PreservationInspectingCodec, SlideImportingCodec {
    public let format: PresentationFormat
    public init(macroEnabled: Bool = false) { format = macroEnabled ? .pptm : .pptx }
    public var capabilities: CodecCapabilities {
        .init(format: format, operations: [
            .inspect: .partial, .read: .partial, .create: format == .pptx ? .partial : .unsupported,
            .edit: .partial, .preserve: .partial, .convert: .unsupported, .render: .unsupported, .play: .unsupported
        ], notes: "直接指定の基本要素と部分編集。継承外観・再生は未解釈。未知内容は原本保持、危険編集は拒否。新規作成はPPTXのみ。詳細は対応台帳を参照。", features: PPTXFeatureCapabilities.features(for: format))
    }
    public func read(_ data: Data, options: ReadOptions = .init()) throws -> ReadResult {
        let reader = try PPTXReader(data, options: options)
        guard reader.package.format == format else { throw SlideError.unknownFormat }
        return try reader.read()
    }
    public func inspect(_ data: Data, limits: PackageLimits = .init()) throws -> PresentationSummary {
        let reader = try PPTXReader(data, options: .init(limits: limits, includeNotes: false))
        guard reader.package.format == format else { throw SlideError.unknownFormat }
        return try reader.inspect()
    }
    public func write(_ presentation: Presentation, options: WriteOptions = .init()) throws -> WriteResult { try PPTXWriter(presentation, format: format, options: options).write() }
    public func inspectPreservation(_ presentation: Presentation) throws -> PackageGraph {
        guard let storage = presentation.storage else { return .init() }
        guard presentation.sourceFormat == format else { throw SlideError.unknownFormat }
        return try PPTXInventory.build(storage)
    }
    @discardableResult public func importSlide(id: String, from source: Presentation, into destination: inout Presentation,
        at index: Int?, options: SlideImportOptions) throws -> String {
        try PPTXCloner.importSlide(id: id, source: source, destination: &destination, index: index, options: options, duplicate: false, format: format)
    }
    @discardableResult public func duplicateSlide(id: String, in presentation: inout Presentation, at index: Int?) throws -> String {
        let source = presentation
        return try PPTXCloner.importSlide(id: id, source: source, destination: &presentation, index: index, options: .init(), duplicate: true, format: format)
    }
}
extension Codec {
    public static let pptx = Codec(PPTXCodec())
    public static let pptm = Codec(PPTXCodec(macroEnabled: true))
}

struct PPTXReader {
    let data: Data
    let package: OPCPackage
    let options: ReadOptions
    let warnings = WarningCollector()
    init(_ data: Data, options: ReadOptions, package: OPCPackage? = nil) throws { self.data = data; self.options = options; self.package = try package ?? OPCPackage(data, limits: options.limits) }
    func tree(_ part: String) throws -> MarkupNode { try MarkupNode.parse(package.archive.read(part), part: part, limits: options.limits) }
    func warn(_ part: String, _ node: MarkupNode, _ code: SlideWarning.Code = .unsupportedContent, _ message: String = "未対応の要素を原本に保持します",
              feature: FeatureID? = nil, slideID: String? = nil, elementID: String? = nil) {
        warnings.add(code, part: part, element: node.name, message: message, feature: feature, slideID: slideID, elementID: elementID)
    }
    func header() throws -> (MarkupNode, Size, [(String,String)], [String: Relationship]) {
        let root = try tree(package.mainPart)
        guard root.isP, root.name == "presentation", let size = root.child("sldSz"), let width = size.attr("cx").flatMap(Double.init), let height = size.attr("cy").flatMap(Double.init), width.isFinite, height.isFinite, width > 0, height > 0 else { throw SlideError.corruptedPackage("不正なpresentationまたはスライド寸法") }
        let rels = try package.relationships(from: package.mainPart)
        var ids: Set<String> = [], paths: Set<String> = [], result: [(String,String)] = []
        for node in root.child("sldIdLst")?.named("sldId") ?? [] {
            guard let id = node.attr("id"), let n = UInt32(id), n >= 256, n < 2_147_483_648, ids.insert(id).inserted,
                  let rid = node.rel("id"), let rel = rels[rid], rel.type == "slide", let path = rel.path, paths.insert(path).inserted else { throw SlideError.corruptedPackage("スライドID・参照が不正または重複しています") }
            result.append((id,path))
        }
        return (root,.init(width: width / 12_700, height: height / 12_700),result,rels)
    }
    func metadata() throws -> Metadata {
        let roots = try package.relationships(from: "")
        guard let part = roots.values.first(where: { $0.type == "core-properties" })?.path else { return .init() }
        let root = try tree(part)
        guard root.namespace == NS.core, root.name == "coreProperties" else { throw SlideError.corruptedPackage("不正なcore metadata") }
        func text(_ name: String) -> String? { root.children.first { $0.namespace == NS.dc && $0.name == name }?.text }
        return .init(title: text("title"), subject: text("subject"), creator: text("creator"), description: text("description"), keywords: root.children.first { $0.namespace == NS.core && $0.name == "keywords" }?.text)
    }
    func inspect() throws -> PresentationSummary {
        let (_,size,slides,_) = try header()
        return .init(format: package.format, size: size, slideCount: slides.count, metadata: try metadata(), parts: package.parts)
    }
    func read() throws -> ReadResult {
        let (root,size,list,_) = try header()
        let metadata = try metadata()
        var slides: [Slide] = [], slidePaths: [String:String] = [:], notesPaths: [String:String] = [:]
        for (id,path) in list {
            try Task.checkCancellation()
            let slide = try readSlide(id:id,path:path)
            if let notes = try package.relationships(from:path).values.first(where: { $0.type == "notesSlide" })?.path { notesPaths[id] = notes }
            slidePaths[id] = path; slides.append(slide)
        }
        for child in root.children where !["sldIdLst","sldSz","notesSz","sldMasterIdLst","notesMasterIdLst","defaultTextStyle"].contains(child.name) { warn(package.mainPart,child) }
        for part in package.parts {
            try Task.checkCancellation()
            if part.path.hasPrefix("_xmlsignatures/") { warnings.add(.unsupportedPart, part: part.path, element: "signature", message: "署名は検証しません。編集保存は拒否します", feature: "SEC-006") }
            if part.path.hasSuffix("vbaProject.bin") { warnings.add(.macrosPreserved, part: part.path, element: "VBA", message: "マクロを原本のまま保持します。実行しません", feature: "SEC-005") }
            if let type = part.contentType, ["chart","diagram","oleObject","video","audio"].contains(where: { type.localizedCaseInsensitiveContains($0) }) { warnings.add(.unsupportedPart, part: part.path, element: "part", message: "未解釈パーツを保持します") }
        }
        let sourceThemes = try themes()
        var presentation = Presentation(size: size, slides: slides, metadata: metadata)
        let storage = Preservation(data: data, archive: package.archive, mainPart: package.mainPart, limits: options.limits, originalSize: size, originalSlides: slides, originalMetadata: metadata, originalTheme: presentation.theme, slidePaths: slidePaths, notesPaths: notesPaths, notesOmitted: !options.includeNotes)
        presentation.preserve(storage, format: package.format, warnings: warnings.result, parts: package.parts, themes: sourceThemes)
        try Task.checkCancellation()
        return .init(presentation: presentation)
    }
    func readSlide(id: String, path: String) throws -> Slide {
        let node = try tree(path)
        guard node.isP, node.name == "sld", let c = node.child("cSld"), let sp = c.child("spTree") else { throw SlideError.corruptedPackage("スライド本体がありません: \(path)") }
        let rels = try package.relationships(from: path)
        var ids: Set<String> = []
        var slide = Slide(id: id, name: c.attr("name") ?? "", elements: try elements(sp, rels: rels, part: path, slideID: id, ids: &ids), background: fill(c.child("bg")?.child("bgPr"), part: path))
        slide.isHidden = ["0","false"].contains(node.attr("show") ?? "1")
        slide.layoutPath = rels.values.first { $0.type == "slideLayout" }?.path
        if let notes = rels.values.first(where: { $0.type == "notesSlide" })?.path {
            if options.includeNotes {
                let n = try tree(notes)
                guard n.isP, n.name == "notes" else { throw SlideError.corruptedPackage("不正なnotes: \(notes)") }
                let paragraphs = try (n.child("cSld")?.child("spTree")?.named("sp") ?? []).filter { shape in
                    let kind = shape.child("nvSpPr")?.child("nvPr")?.child("ph")?.attr("type")
                    return kind == "body" || kind == nil
                }.flatMap { shape -> [Paragraph] in guard let tx = shape.child("txBody") else { return [] }; return try text(tx, rels: try package.relationships(from: notes), part: notes).paragraphs }
                slide.notes = .init(paragraphs: paragraphs)
            } else { warnings.add(.notesOmitted, part: notes, element: "notes", message: "ノート読み取りを省略しました。保存では元パーツを保持します", slideID: id) }
        }
        for child in node.children where !["cSld","clrMapOvr"].contains(child.name) {
            let feature: FeatureID? = child.isP && child.name == "timing" ? "ANI-005" : child.isP && child.name == "transition" ? "ANI-001" : nil
            warn(path, child, feature: feature, slideID: id)
        }
        if let bgRef = c.child("bg")?.child("bgRef") { warn(path,bgRef,.uninterpretedFormatting,"テーマ背景参照を保持します。実効色は未解決です") }
        return slide
    }
    func themes() throws -> [ThemePart] {
        try package.parts.filter { $0.contentType == "application/vnd.openxmlformats-officedocument.theme+xml" }.map { part in
            let root = try tree(part.path)
            guard root.isA, root.name == "theme", let elements = root.child("themeElements") else { throw SlideError.corruptedPackage("不正なテーマ") }
            func font(_ node: MarkupNode?) -> Font {
                var supplemental: [String:String] = [:]
                for f in node?.named("font") ?? [] { if let script = f.attr("script"), let face = f.attr("typeface") { supplemental[script] = face } }
                return .init(family:node?.child("latin")?.attr("typeface"),eastAsianFamily:node?.child("ea")?.attr("typeface"),complexScriptFamily:node?.child("cs")?.attr("typeface"),supplementalFamilies:supplemental)
            }
            var colors: [String:Color] = [:]
            for slot in elements.child("clrScheme")?.children ?? [] {
                if let sys = slot.child("sysClr"), let fallback = sys.attr("lastClr") { colors[slot.name] = .rgb(fallback); warn(part.path,sys,.uninterpretedFormatting,"システム色はlastClrの代替値です") }
                else if let c = color(slot,part:part.path) { colors[slot.name] = c }
            }
            return ThemePart(path:part.path,name:root.attr("name") ?? "",titleFont:font(elements.child("fontScheme")?.child("majorFont")),bodyFont:font(elements.child("fontScheme")?.child("minorFont")),colors:colors)
        }
    }
    func elements(_ parent: MarkupNode, rels: [String:Relationship], part: String, slideID: String, ids: inout Set<String>) throws -> [Element] {
        var result: [Element] = []
        for node in parent.children {
            try Task.checkCancellation()
            if node.isP, ["nvGrpSpPr","grpSpPr"].contains(node.name) { continue }
            let nvName: String
            let kind: Element.Kind
            switch node.isP ? node.name : "" {
            case "sp": nvName = "nvSpPr"; kind = .shape
            case "cxnSp": nvName = "nvCxnSpPr"; kind = .connector
            case "pic": nvName = "nvPicPr"; kind = .image
            case "graphicFrame": nvName = "nvGraphicFramePr"; kind = node.child("graphic")?.child("graphicData")?.child("tbl") == nil ? .opaque : .table
            case "grpSp": nvName = "nvGrpSpPr"; kind = .group
            default: nvName = ""; kind = .opaque
            }
            let cnv = node.child(nvName)?.child("cNvPr")
            let id: String
            if let raw = cnv?.attr("id") { guard UInt32(raw) != nil, ids.insert(raw).inserted else { throw SlideError.corruptedPackage("図形IDが不正または重複: \(part)") }; id = raw }
            else { id = "opaque-\(result.count)-\(ids.count)"; guard ids.insert(id).inserted else { throw SlideError.corruptedPackage("opaque IDの重複") } }
            let props = node.child(kind == .group ? "grpSpPr" : "spPr")
            let xfrm = props?.child("xfrm") ?? node.child("xfrm")
            var e = Element(id: id, name: cnv?.attr("name") ?? "", kind: kind, frame: rect(xfrm), geometry: props?.child("prstGeom").flatMap { $0.attr("prst") }.map { ShapeGeometry($0) }, fill: fill(props, part: part), stroke: stroke(props?.child("ln"), part: part))
            e.isTextBox = on(node.child("nvSpPr")?.child("cNvSpPr")?.attr("txBox"))
            e.rotation = (xfrm?.attr("rot").flatMap(Double.init) ?? 0) / 60_000
            e.flipHorizontal = on(xfrm?.attr("flipH")); e.flipVertical = on(xfrm?.attr("flipV"))
            if let ph = node.child(nvName)?.child("nvPr")?.child("ph") { e.placeholder = .init(kind: ph.attr("type") ?? "obj", index: ph.attr("idx").flatMap(Int.init)); warnings.add(.uninterpretedFormatting, part: part, element: "ph", message: "プレースホルダーのmaster/layout継承値は計算しません") }
            if let body = node.child("txBody") { e.text = try text(body, rels: rels, part: part) }
            if kind == .image {
                guard let blip = node.child("blipFill")?.child("blip") else { throw SlideError.corruptedPackage("画像参照がありません") }
                if let embed = blip.rel("embed"), let imageRel = rels[embed], imageRel.type == "image", let path = imageRel.path { e.image = .init(path: path, contentType: package.type(of: path), alternativeText: cnv?.attr("descr") ?? "") }
                else if let link = blip.rel("link"), let rel = rels[link], rel.isExternal { warn(part, blip, .unsupportedContent, "外部画像の参照を保持し、取得しません") }
                else { throw SlideError.corruptedPackage("画像relationshipが不正です") }
                if let crop = node.child("blipFill")?.child("srcRect") { warn(part,crop,.uninterpretedFormatting,"画像の切り抜きを原本で保持します") }
            }
            if kind == .table, let tbl = node.child("graphic")?.child("graphicData")?.child("tbl") { e.table = try table(tbl, rels: rels, part: part) }
            if kind == .group { e.children = try elements(node, rels: rels, part: part, slideID: slideID, ids: &ids); e.childFrame = rect(xfrm, offset: "chOff", extent: "chExt") }
            if kind == .opaque { e.setRawXML(node.xml); warn(part,node,feature: "OBJ-011",slideID: slideID,elementID: id) }
            for child in props?.children ?? [] where !["xfrm","prstGeom","solidFill","noFill","ln"].contains(child.name) { warn(part,child,.uninterpretedFormatting) }
            if let av = props?.child("prstGeom")?.child("avLst"), !av.children.isEmpty { warn(part,av,.uninterpretedFormatting,"図形の調整値を原本で保持します") }
            if let style = node.child("style") { warn(part,style,.uninterpretedFormatting,"テーマ由来の図形書式参照を保持します。実効値は未解決です") }
            for child in node.children where ![nvName,"spPr","grpSpPr","txBody","style","blipFill","xfrm","graphic","sp","cxnSp","pic","graphicFrame","grpSp"].contains(child.name) { warn(part,child) }
            result.append(e)
        }
        return result
    }
    func rect(_ node: MarkupNode?, offset: String = "off", extent: String = "ext") -> Rect? {
        guard let off = node?.child(offset), let ext = node?.child(extent), let x = off.attr("x").flatMap(Double.init), let y = off.attr("y").flatMap(Double.init), let w = ext.attr("cx").flatMap(Double.init), let h = ext.attr("cy").flatMap(Double.init) else { return nil }
        return .init(x: x / 12_700, y: y / 12_700, width: w / 12_700, height: h / 12_700)
    }
    func on(_ value: String?) -> Bool { ["1","true","on"].contains(value ?? "") }
    func boolean(_ value: String?) -> Bool? { value.map { !["0","false","off"].contains($0) } }
    func color(_ node: MarkupNode?, part: String) -> Color? {
        guard let node else { return nil }
        for c in node.children {
            if c.isA, let value = c.attr("val"), c.name == "srgbClr" || c.name == "schemeClr" {
                if !c.children.isEmpty { warn(part,c,.uninterpretedFormatting,"色の変換・透明度を原本で保持します。Colorは変換前の値です") }
                return c.name == "srgbClr" ? .rgb(value) : .theme(value)
            }
            warn(part,c,.uninterpretedFormatting,"未解決の色を原本に保持します")
        }
        return nil
    }
    func fill(_ node: MarkupNode?, part: String) -> Fill? {
        guard let node else { return nil }
        if node.child("noFill") != nil { return Fill.none }
        if let c = color(node.child("solidFill"), part: part) { return .solid(c) }
        return nil
    }
    func stroke(_ node: MarkupNode?, part: String) -> Stroke? {
        guard let node else { return nil }
        if node.child("noFill") != nil { return nil }
        let c = color(node.child("solidFill"), part: part) ?? .theme("tx1")
        let result = Stroke(color: c, width: (node.attr("w").flatMap(Double.init) ?? 12_700) / 12_700, dash: Stroke.Dash(rawValue: node.child("prstDash")?.attr("val") ?? "solid") ?? .solid, startArrow: Arrowhead(rawValue: node.child("headEnd")?.attr("type") ?? "none") ?? .none, endArrow: Arrowhead(rawValue: node.child("tailEnd")?.attr("type") ?? "none") ?? .none)
        for c in node.children where !["solidFill","prstDash","headEnd","tailEnd"].contains(c.name) { warn(part,c,.uninterpretedFormatting) }
        if !node.attributes.keys.filter({ $0 != "w" }).isEmpty { warn(part,node,.uninterpretedFormatting,"線の追加属性を原本で保持します") }
        return result
    }
    func textStyle(_ node: MarkupNode?, part: String) -> TextStyle {
        guard let node else { return .init() }
        var result = TextStyle(font: .init(family: node.child("latin")?.attr("typeface"), size: node.attr("sz").flatMap(Double.init).map { $0 / 100 }, eastAsianFamily: node.child("ea")?.attr("typeface"), complexScriptFamily: node.child("cs")?.attr("typeface")), bold: boolean(node.attr("b")), italic: boolean(node.attr("i")), underline: node.attr("u").map { $0 != "none" }, color: color(node.child("solidFill"), part: part), language: node.attr("lang"))
        if let u = node.attr("u"), !["none","sng"].contains(u) { warn(part,node,.uninterpretedFormatting,"下線の種類を原本で保持します") }
        for key in node.attributes.keys where !["sz","b","i","u","lang","dirty","smtClean"].contains(key) { warnings.add(.uninterpretedFormatting, part: part, element: key, message: "未対応の文字属性を原本で保持します") }
        for c in node.children where !["latin","ea","cs","solidFill","hlinkClick"].contains(c.name) { warn(part,c,.uninterpretedFormatting) }
        if result.font.size?.isFinite == false { result.font.size = nil; warn(part,node,.uninterpretedFormatting) }
        return result
    }
    func text(_ node: MarkupNode, rels: [String:Relationship], part: String) throws -> TextBody {
        var paragraphs: [Paragraph] = []
        let body = node.child("bodyPr")
        for p in node.named("p") {
            let pr = p.child("pPr")
            func spacing(_ name: String) -> Double? { pr?.child(name)?.child("spcPts")?.attr("val").flatMap(Double.init).map { $0 / 100 } }
            var ps = ParagraphStyle(alignment: pr?.attr("algn").flatMap(TextAlignment.init), level: pr?.attr("lvl").flatMap(Int.init), leftMargin: pr?.attr("marL").flatMap(Double.init).map { $0/12_700 }, indent: pr?.attr("indent").flatMap(Double.init).map { $0/12_700 }, spaceBefore: spacing("spcBef"), spaceAfter: spacing("spcAft"), lineSpacing: pr?.child("lnSpc")?.child("spcPct")?.attr("val").flatMap(Double.init).map { $0 / 100_000 })
            if pr?.child("buNone") != nil { ps.bullet = Bullet.none }
            else if let b = pr?.child("buChar")?.attr("char") { ps.bullet = .character(b) }
            else if let b = pr?.child("buAutoNum"), let type = b.attr("type") { ps.bullet = .numbered(type,start: b.attr("startAt").flatMap(Int.init) ?? 1) }
            for c in pr?.children ?? [] where !["defRPr","lnSpc","spcBef","spcAft","buNone","buChar","buAutoNum"].contains(c.name) { warn(part,c,.uninterpretedFormatting) }
            if let pr { for key in pr.attributes.keys where !["algn","lvl","marL","indent"].contains(key) { warnings.add(.uninterpretedFormatting, part: part, element: key, message: "段落属性を原本に保持します") } }
            var runs: [TextRun] = []
            for child in p.children {
                switch child.isA ? child.name : "" {
                case "r","fld":
                    var run = TextRun(child.child("t")?.text ?? "", style: textStyle(child.child("rPr"), part: part))
                    if let link = child.child("rPr")?.child("hlinkClick"), let rid = link.rel("id") {
                        guard let rel = rels[rid] else { throw SlideError.invalidRelationship(part: part, detail: "テキストリンクの参照がありません") }
                        if rel.isExternal { run.link = .external(rel.target) } else if rel.type == "slide", let path = rel.path { run.link = .slide(path) } else { warn(part,link) }
                    }
                    runs.append(run)
                    if child.name == "fld" { warn(part,child,.unsupportedContent,"フィールドは表示値だけを読み、再計算しません") }
                case "br": runs.append(.init("\n",style: textStyle(child.child("rPr"),part:part)))
                case "pPr","endParaRPr": break
                default: warn(part,child)
                }
            }
            paragraphs.append(.init(runs: runs,style:ps,defaultTextStyle:textStyle(pr?.child("defRPr"),part:part),endTextStyle:textStyle(p.child("endParaRPr"),part:part)))
        }
        var insets: Insets?
        if let body, ["lIns","rIns","tIns","bIns"].contains(where: { body.attr($0) != nil }) {
            func margin(_ key: String, _ fallback: Double) -> Double { (body.attr(key).flatMap(Double.init) ?? fallback) / 12_700 }
            insets = Insets(top:margin("tIns",45_720),left:margin("lIns",91_440),bottom:margin("bIns",45_720),right:margin("rIns",91_440))
        }
        if let body { for key in body.attributes.keys where !["lIns","rIns","tIns","bIns","anchor","wrap"].contains(key) { warnings.add(.uninterpretedFormatting,part:part,element:key,message:"テキスト領域の追加属性を原本で保持します") }; for child in body.children { warn(part,child,.uninterpretedFormatting) } }
        if let list = node.child("lstStyle"), !list.children.isEmpty { warn(part,list,.uninterpretedFormatting,"リストの既定書式を原本で保持します。継承値は未解決です") }
        return .init(paragraphs:paragraphs,insets:insets,verticalAlignment:body?.attr("anchor").flatMap(VerticalAlignment.init),wrap:body?.attr("wrap").map { $0 != "none" })
    }
    func table(_ node: MarkupNode, rels: [String:Relationship], part: String) throws -> Table {
        let widths = node.child("tblGrid")?.named("gridCol").compactMap { $0.attr("w").flatMap(Double.init).map { $0/12_700 } } ?? []
        var rows: [[TableCell]] = [], heights: [Double] = []
        for row in node.named("tr") {
            heights.append((row.attr("h").flatMap(Double.init) ?? 0) / 12_700)
            var cells: [TableCell] = []
            for cell in row.named("tc") {
                let properties = cell.child("tcPr")
                var result = TableCell(fill: fill(properties,part:part),border:stroke(properties?.child("lnL"),part:part),rowSpan:cell.attr("rowSpan").flatMap(Int.init) ?? 1,columnSpan:cell.attr("gridSpan").flatMap(Int.init) ?? 1,isMergeContinuation:on(cell.attr("hMerge")) || on(cell.attr("vMerge")))
                if let tx = cell.child("txBody") { result.text = try text(tx,rels:rels,part:part) }
                if let properties, ["marL","marR","marT","marB"].contains(where:{ properties.attr($0) != nil }) {
                    func margin(_ key: String, _ fallback: Double) -> Double { (properties.attr(key).flatMap(Double.init) ?? fallback) / 12_700 }
                    result.insets = Insets(top:margin("marT",45_720),left:margin("marL",91_440),bottom:margin("marB",45_720),right:margin("marR",91_440))
                }
                for c in properties?.children ?? [] where !["solidFill","noFill","lnL"].contains(c.name) { warn(part,c,.uninterpretedFormatting,"セルの個別辺・追加書式を原本で保持します") }
                cells.append(result)
            }
            rows.append(cells)
        }
        guard !widths.isEmpty, rows.allSatisfy({ $0.count == widths.count }) else { throw SlideError.corruptedPackage("表の列数が不整合です") }
        if let pr = node.child("tblPr"), !pr.attributes.isEmpty { warn(part,pr,.uninterpretedFormatting,"表スタイルの適用フラグを原本で保持します") }
        return .init(columnWidths:widths,rowHeights:heights,rows:rows,styleID:node.child("tblPr")?.child("tableStyleId")?.text)
    }
}


extension PPTXCodec: SlideReadingCodec {
    public func openSlides(_ data: Data, options: ReadOptions) throws -> any PresentationSlideSource {
        let reader = try PPTXReader(data,options:options)
        guard reader.package.format == format else { throw SlideError.unknownFormat }
        let (_,size,list,_) = try reader.header()
        return PPTXSlideSource(data:data,package:reader.package,options:options,
            summary:.init(format:format,size:size,slideCount:list.count,metadata:try reader.metadata(),parts:reader.package.parts),list:list)
    }
}
private struct PPTXSlideSource: PresentationSlideSource {
    let data: Data
    let package: OPCPackage
    let options: ReadOptions
    let summary: PresentationSummary
    let list: [(String,String)]
    var slideDescriptors: [SlideDescriptor] { list.enumerated().map { .init(id:$0.element.0,index:$0.offset) } }
    func slide(at index: Int) throws -> SlideReadResult {
        guard list.indices.contains(index) else { throw SlideError.invalidModel("reader index範囲外") }
        let reader = try PPTXReader(data,options:options,package:package)
        let slide = try reader.readSlide(id:list[index].0,path:list[index].1)
        return .init(slide:slide,warnings:reader.warnings.result)
    }
    func asset(at path: String) throws -> Data { try package.archive.read(path) }
}
