import Foundation
import SlideCore

/// All strings pass through XML escaping; numeric conversions are validated before emission.
enum PPTXXML {
    // DrawingML ST_ShapeType names from the public format specification.
    static let validPresets: Set<String> = ["line","lineInv","triangle","rtTriangle","rect","diamond","parallelogram","trapezoid","nonIsoscelesTrapezoid","pentagon","hexagon","heptagon","octagon","decagon","dodecagon","star4","star5","star6","star7","star8","star10","star12","star16","star24","star32","roundRect","round1Rect","round2SameRect","round2DiagRect","snipRoundRect","snip1Rect","snip2SameRect","snip2DiagRect","plaque","ellipse","teardrop","homePlate","chevron","pieWedge","pie","blockArc","donut","noSmoking","rightArrow","leftArrow","upArrow","downArrow","stripedRightArrow","notchedRightArrow","bentUpArrow","leftRightArrow","upDownArrow","leftUpArrow","leftRightUpArrow","quadArrow","leftArrowCallout","rightArrowCallout","upArrowCallout","downArrowCallout","leftRightArrowCallout","upDownArrowCallout","quadArrowCallout","bentArrow","uturnArrow","circularArrow","leftCircularArrow","leftRightCircularArrow","curvedRightArrow","curvedLeftArrow","curvedUpArrow","curvedDownArrow","swooshArrow","cube","can","lightningBolt","heart","sun","moon","smileyFace","irregularSeal1","irregularSeal2","foldedCorner","bevel","frame","halfFrame","corner","diagStripe","chord","arc","leftBracket","rightBracket","leftBrace","rightBrace","bracketPair","bracePair","straightConnector1","bentConnector2","bentConnector3","bentConnector4","bentConnector5","curvedConnector2","curvedConnector3","curvedConnector4","curvedConnector5","callout1","callout2","callout3","accentCallout1","accentCallout2","accentCallout3","borderCallout1","borderCallout2","borderCallout3","accentBorderCallout1","accentBorderCallout2","accentBorderCallout3","wedgeRectCallout","wedgeRoundRectCallout","wedgeEllipseCallout","cloudCallout","cloud","ribbon","ribbon2","ellipseRibbon","ellipseRibbon2","leftRightRibbon","verticalScroll","horizontalScroll","wave","doubleWave","plus","flowChartProcess","flowChartDecision","flowChartInputOutput","flowChartPredefinedProcess","flowChartInternalStorage","flowChartDocument","flowChartMultidocument","flowChartTerminator","flowChartPreparation","flowChartManualInput","flowChartManualOperation","flowChartConnector","flowChartPunchedCard","flowChartPunchedTape","flowChartSummingJunction","flowChartOr","flowChartCollate","flowChartSort","flowChartExtract","flowChartMerge","flowChartOfflineStorage","flowChartOnlineStorage","flowChartMagneticTape","flowChartMagneticDisk","flowChartMagneticDrum","flowChartDisplay","flowChartDelay","flowChartAlternateProcess","flowChartOffpageConnector","actionButtonBlank","actionButtonHome","actionButtonHelp","actionButtonInformation","actionButtonForwardNext","actionButtonBackPrevious","actionButtonEnd","actionButtonBeginning","actionButtonReturn","actionButtonDocument","actionButtonSound","actionButtonMovie","gear6","gear9","funnel","mathPlus","mathMinus","mathMultiply","mathDivide","mathEqual","mathNotEqual","cornerTabs","squareTabs","plaqueTabs","chartX","chartStar","chartPlus"]
    static func emu(_ value: Double) -> String { String(Int64((value * 12_700).rounded())) }
    static func hundredths(_ value: Double) -> String { String(Int64((value * 100).rounded())) }
    static func color(_ color: Color) throws -> String { switch color { case .rgb(let hex): "<a:srgbClr val=\"\(escapeXML(hex.uppercased()))\"/>"; case .theme(let key): "<a:schemeClr val=\"\(escapeXML(key))\"/>"; case .value: throw SlideError.unsafeEdit("色変換を持つ色の書換えは未対応です") } }
    static func fill(_ fill: Fill?) throws -> String { guard let fill else { return "" }; switch fill { case .none: return "<a:noFill/>"; case .solid(let c): return "<a:solidFill>\(try color(c))</a:solidFill>"; case .gradient, .pattern, .picture: throw SlideError.unsafeEdit("追加の塗りは読取専用です") } }
    static func line(_ stroke: Stroke?, tag: String = "ln") throws -> String {
        guard let stroke else { return "<a:\(tag)><a:noFill/></a:\(tag)>" }
        return "<a:\(tag) w=\"\(emu(stroke.width))\"><a:solidFill>\(try color(stroke.color))</a:solidFill><a:prstDash val=\"\(stroke.dash.rawValue)\"/><a:headEnd type=\"\(stroke.startArrow.rawValue)\"/><a:tailEnd type=\"\(stroke.endArrow.rawValue)\"/></a:\(tag)>"
    }
    static func transform(_ e: Element, p: Bool = false) -> String {
        let prefix = p ? "p" : "a"
        let attrs = " rot=\"\(Int64((e.rotation * 60_000).rounded()))\" flipH=\"\(e.flipHorizontal ? 1 : 0)\" flipV=\"\(e.flipVertical ? 1 : 0)\""
        let f = e.frame ?? Rect(x:0,y:0,width:0,height:0)
        var body = "<a:off x=\"\(emu(f.x))\" y=\"\(emu(f.y))\"/><a:ext cx=\"\(emu(f.width))\" cy=\"\(emu(f.height))\"/>"
        if e.kind == .group, let c = e.childFrame { body += "<a:chOff x=\"\(emu(c.x))\" y=\"\(emu(c.y))\"/><a:chExt cx=\"\(emu(c.width))\" cy=\"\(emu(c.height))\"/>" }
        return "<\(prefix):xfrm\(attrs)>\(body)</\(prefix):xfrm>"
    }
    static func textStyle(_ s: TextStyle, tag: String = "rPr", linkID: String? = nil, internalLink: Bool = false) throws -> String {
        var attrs = ""
        if let size = s.font.size { attrs += " sz=\"\(hundredths(size))\"" }
        if let bold = s.bold { attrs += " b=\"\(bold ? 1 : 0)\"" }; if let italic = s.italic { attrs += " i=\"\(italic ? 1 : 0)\"" }
        if let underline = s.underline { attrs += " u=\"\(underline ? "sng" : "none")\"" }; if let lang = s.language { attrs += " lang=\"\(escapeXML(lang))\"" }
        var body = try s.color.map { "<a:solidFill>\(try color($0))</a:solidFill>" } ?? ""
        for (tag,family) in [("latin",s.font.family),("ea",s.font.eastAsianFamily),("cs",s.font.complexScriptFamily)] { if let family { body += "<a:\(tag) typeface=\"\(escapeXML(family))\"/>" } }
        if let linkID { body += "<a:hlinkClick r:id=\"\(escapeXML(linkID))\"\(internalLink ? " action=\"ppaction://hlinksldjump\"" : "")/>" }
        return "<a:\(tag)\(attrs)>\(body)</a:\(tag)>"
    }
    static func paragraphProperties(_ style: ParagraphStyle, defaultTextStyle: TextStyle) throws -> String {
        try ModelValidation.paragraphStyle(style)
        try ModelValidation.style(defaultTextStyle)
        var attrs = "", body = ""
        if let a = style.alignment { attrs += " algn=\"\(a.rawValue)\"" }; if let l = style.level { attrs += " lvl=\"\(l)\"" }
        if let m = style.leftMargin { attrs += " marL=\"\(emu(m))\"" }; if let i = style.indent { attrs += " indent=\"\(emu(i))\"" }
        func spacing(_ value: TextSpacing?, _ tag: String) throws -> String {
            guard let value else { return "" }
            let n: Double, child: String
            switch value { case .points(let v): n = v * 100; child = "spcPts"; case .percentage(let v): n = v * 100_000; child = "spcPct" }
            guard n.isFinite, n >= 0, n <= Double(Int32.max) else { throw SlideError.invalidModel("間隔が範囲外です") }
            return "<a:\(tag)><a:\(child) val=\"\(Int64(n.rounded()))\"/></a:\(tag)>"
        }
        body += try spacing(style.effectiveLineSpacing,"lnSpc") + spacing(style.effectiveSpaceBefore,"spcBef") + spacing(style.effectiveSpaceAfter,"spcAft")
        if let bullet = style.bullet { switch bullet {
            case .none: body += "<a:buNone/>"
            case .character(let char): body += "<a:buChar char=\"\(escapeXML(char))\"/>"
            case .numbered(let type,let start): body += "<a:buAutoNum type=\"\(escapeXML(type))\" startAt=\"\(start)\"/>"
        } }
        body += try textStyle(defaultTextStyle,tag:"defRPr")
        return "<a:pPr\(attrs)>\(body)</a:pPr>"
    }
    static func paragraph(_ p: Paragraph, relationship: (Link) throws -> String) throws -> String {
        let properties = try paragraphProperties(p.style, defaultTextStyle: p.defaultTextStyle)
        var runs = ""
        for run in p.runs {
            let rid = try run.link.map(relationship)
            let internalLink: Bool; if case .slide = run.link { internalLink = true } else { internalLink = false }
            let style = try textStyle(run.style,linkID:rid,internalLink:internalLink)
            if let field = run.field {
                try ModelValidation.string(field.id); try ModelValidation.string(field.type)
                guard UUID(uuidString: field.id.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))) != nil, !field.type.isEmpty, run.text == field.cachedText else { throw SlideError.unsafeEdit("不正なfieldまたはrunとキャッシュが不一致です") }
                let pr = try field.paragraphStyle.map { try paragraphProperties($0.paragraph, defaultTextStyle: $0.text) } ?? ""
                runs += "<a:fld id=\"\(escapeXML(field.id))\" type=\"\(escapeXML(field.type))\">\(style)\(pr)<a:t>\(escapeXML(run.text))</a:t></a:fld>"
                continue
            }
            let pieces = run.text.components(separatedBy:"\n")
            for i in pieces.indices { if i > 0 { runs += "<a:br>\(style)</a:br>" }; runs += "<a:r>\(style)<a:t>\(escapeXML(pieces[i]))</a:t></a:r>" }
        }
        return "<a:p>\(properties)\(runs)\(try textStyle(p.endTextStyle,tag:"endParaRPr"))</a:p>"
    }
    static func text(_ text: TextBody, p: Bool = true, relationship: (Link) throws -> String) throws -> String {
        guard text.listStyle == nil else { throw SlideError.unsafeEdit("リスト既定書式の書換えは未対応です") }
        let prefix = p ? "p" : "a"
        var attrs = ""
        if let i = text.insets { attrs += " lIns=\"\(emu(i.left))\" tIns=\"\(emu(i.top))\" rIns=\"\(emu(i.right))\" bIns=\"\(emu(i.bottom))\"" }
        if let alignment = text.verticalAlignment { attrs += " anchor=\"\(alignment.rawValue)\"" }; if let wrap = text.wrap { attrs += " wrap=\"\(wrap ? "square" : "none")\"" }
        let paragraphs = try (text.paragraphs.isEmpty ? [Paragraph()] : text.paragraphs).map { try paragraph($0,relationship:relationship) }.joined()
        return "<\(prefix):txBody><a:bodyPr\(attrs)/><a:lstStyle/>\(paragraphs)</\(prefix):txBody>"
    }
    static func table(_ table: Table, relationship: (Link) throws -> String) throws -> String {
        let grid = table.columnWidths.map { "<a:gridCol w=\"\(emu($0))\"/>" }.joined()
        var rows = ""
        for i in table.rows.indices {
            var cells = ""
            for cell in table.rows[i] {
                guard cell.borders == nil, cell.value == nil, cell.formula == nil else { throw SlideError.unsafeEdit("個別罫線・型付きセル値・式の新規保存は未対応です") }
                var attrs = ""
                if cell.rowSpan > 1 { attrs += " rowSpan=\"\(cell.rowSpan)\"" }; if cell.columnSpan > 1 { attrs += " gridSpan=\"\(cell.columnSpan)\"" }
                if cell.isMergeContinuation { attrs += " hMerge=\"1\"" }
                var margins = ""
                if let m = cell.insets { margins = " marL=\"\(emu(m.left))\" marR=\"\(emu(m.right))\" marT=\"\(emu(m.top))\" marB=\"\(emu(m.bottom))\"" }
                let borders = try cell.border.map { b in try ["lnL","lnR","lnT","lnB"].map { try line(b,tag:$0) }.joined() } ?? ""
                cells += "<a:tc\(attrs)>\(try text(cell.text,p:false,relationship:relationship))<a:tcPr\(margins)>\(borders)\(try fill(cell.fill))</a:tcPr></a:tc>"
            }
            rows += "<a:tr h=\"\(emu(table.rowHeights[i]))\">\(cells)</a:tr>"
        }
        return "<a:tbl><a:tblPr>\(table.styleID.map { "<a:tableStyleId>\(escapeXML($0))</a:tableStyleId>" } ?? "")</a:tblPr><a:tblGrid>\(grid)</a:tblGrid>\(rows)</a:tbl>"
    }
    static func groupHeader() -> String { "<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>" }
    static func envelope(_ tag: String, _ body: String) -> String { "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><p:\(tag) xmlns:a=\"\(NS.a)\" xmlns:r=\"\(NS.r)\" xmlns:p=\"\(NS.p)\">\(body)</p:\(tag)>" }
    static func core(_ metadata: Metadata) -> String {
        var body = ""
        for (key,value) in [("title",metadata.title),("subject",metadata.subject),("creator",metadata.creator),("description",metadata.description)] { if let value { body += "<dc:\(key)>\(escapeXML(value))</dc:\(key)>" } }
        if let keywords = metadata.keywords { body += "<cp:keywords>\(escapeXML(keywords))</cp:keywords>" }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?><cp:coreProperties xmlns:cp=\"\(NS.core)\" xmlns:dc=\"\(NS.dc)\">\(body)</cp:coreProperties>"
    }
    static func theme(_ theme: Theme) -> String {
        let order = ["dk1","lt1","dk2","lt2","accent1","accent2","accent3","accent4","accent5","accent6","hlink","folHlink"]
        let colors = order.map { "<a:\($0)><a:srgbClr val=\"\(theme.colors[$0]!)\"/></a:\($0)>" }.joined()
        func font(_ f: Font, _ tag: String) -> String { "<a:\(tag)><a:latin typeface=\"\(escapeXML(f.family ?? "Aptos"))\"/><a:ea typeface=\"\(escapeXML(f.eastAsianFamily ?? ""))\"/><a:cs typeface=\"\(escapeXML(f.complexScriptFamily ?? ""))\"/>\(f.supplementalFamilies.sorted(by: { $0.key < $1.key }).map { "<a:font script=\"\(escapeXML($0.key))\" typeface=\"\(escapeXML($0.value))\"/>" }.joined())</a:\(tag)>" }
        let fill = "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
        let fills = Array(repeating:fill,count:3).joined()
        let lines = [1.0,2,3].map { "<a:ln w=\"\(emu($0))\" cap=\"flat\" cmpd=\"sng\" algn=\"ctr\">\(fill)<a:prstDash val=\"solid\"/><a:miter lim=\"800000\"/></a:ln>" }.joined()
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?><a:theme xmlns:a=\"\(NS.a)\" name=\"\(escapeXML(theme.name))\"><a:themeElements><a:clrScheme name=\"SwiftSlides\">\(colors)</a:clrScheme><a:fontScheme name=\"SwiftSlides\">\(font(theme.titleFont,"majorFont"))\(font(theme.bodyFont,"minorFont"))</a:fontScheme><a:fmtScheme name=\"SwiftSlides\"><a:fillStyleLst>\(fills)</a:fillStyleLst><a:lnStyleLst>\(lines)</a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst>\(fills)</a:bgFillStyleLst></a:fmtScheme></a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>"
    }
    static let colorMap = "<p:clrMap accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" bg1=\"lt1\" bg2=\"lt2\" folHlink=\"folHlink\" hlink=\"hlink\" tx1=\"dk1\" tx2=\"dk2\"/>"
}
