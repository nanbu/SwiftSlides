import Foundation
import SlideCore

final class PPTXWriter {
    let presentation: Presentation
    let format: PresentationFormat
    let options: WriteOptions
    var parts: [String:Data] = [:]
    var unchanged: Set<String> = []
    var overrides: [String:String] = [:]
    var slidePaths: [String:String] = [:]
    let warnings = WarningCollector()
    var counter = 0
    var notesMasterPath: String?
    var inventory: PackageGraph?
    func graph(_ storage: Preservation) throws -> PackageGraph {
        if let inventory { return inventory }
        let result = try PPTXInventory.build(storage); inventory = result; return result
    }
    init(_ presentation: Presentation, format: PresentationFormat, options: WriteOptions) { self.presentation = presentation; self.format = format; self.options = options }
    func put(_ path: String, _ xml: String, type: String? = nil) { parts[path] = Data(xml.utf8); unchanged.remove(path); if let type { overrides[path] = type } }
    func unique(_ directory: String, _ suffix: String) -> String {
        repeat { counter += 1 } while parts["\(directory)/swiftslides\(counter).\(suffix)"] != nil
        return "\(directory)/swiftslides\(counter).\(suffix)"
    }
    func parse(_ path: String) throws -> MarkupNode { guard var data = parts[path] else { throw SlideError.missingPart(path) }; if unchanged.contains(path), let storage = presentation.storage { data = try storage.archive.read(path) }; return try MarkupNode.parse(data, part: path, limits: presentation.storage?.limits ?? .init()) }
    func warning(_ part: String, _ element: String, _ message: String,
                 feature: FeatureID? = nil, slideID: String? = nil, elementID: String? = nil) {
        warnings.add(.rewrittenContent,part:part,element:element,message:message,feature:feature,
                     slideID:slideID ?? slidePaths.first(where: { $0.value == part })?.key,elementID:elementID)
    }
    func write() throws -> WriteResult {
        try Task.checkCancellation()
        try ModelValidation.presentation(presentation)
        if let storage = presentation.storage {
            guard presentation.sourceFormat == format else { throw SlideError.unsafeEdit("既存PPTX/PPTMの形式を変更できません。マクロや関連パーツの削除は明示的な変換が必要です") }
            if presentation.size == storage.originalSize, presentation.slides == storage.originalSlides, presentation.metadata == storage.originalMetadata, presentation.theme == storage.originalTheme, presentation.firstSlideNumber == storage.originalFirstSlideNumber { return .init(data:storage.data) }
            guard !storage.archive.paths.contains(where:{ $0.hasPrefix("_xmlsignatures/") }) else { throw SlideError.unsafeEdit("署名付き文書は編集保存できません") }
            guard presentation.theme == storage.originalTheme else { throw SlideError.unsafeEdit("既存テーマの書き換えは未対応です") }
            for path in storage.archive.paths where !path.hasSuffix("/") { parts[path] = Data(); unchanged.insert(path) }
            slidePaths = storage.slidePaths
            try installClones()
            try edit(storage)
        } else {
            guard format == .pptx else { throw SlideError.unsafeEdit("マクロ付き文書の新規作成は未対応です") }
            try installClones()
            try create()
        }
        try validateCloneDependencies()
        try normalizeClonedLayoutIDs()
        if options.strict, !warnings.result.isEmpty { throw SlideError.unsafeEdit("strict保存: \(warnings.result.map(\.message).joined(separator:"; "))") }
        return .init(data:try ZIPWriter.write(parts,compress:options.compress,original:presentation.storage?.archive,unchanged:unchanged),warnings:warnings.result)
    }
    func installClones() throws {
        for (id, clone) in presentation.slideClones.sorted(by: { $0.key < $1.key }) {
            for (path, data) in clone.parts {
                if let existing = parts[path], !unchanged.contains(path), existing != data { throw SlideError.unsafeEdit("取り込みpartのパスが衝突しました") }
                parts[path] = data; unchanged.remove(path)
            }
            overrides.merge(clone.contentTypes, uniquingKeysWith: { first, _ in first })
            slidePaths[id] = clone.slidePath
        }
    }
    func resolveCloneLinks() throws {
        let retained = Set(presentation.slides.map(\.id))
        for (id, clone) in presentation.slideClones {
            for link in clone.links {
                if retained.contains(id), !retained.contains(link.slideID) { throw SlideError.unsafeEdit("取り込みスライドのリンク先が削除されています") }
                guard let target = slidePaths[link.slideID] else { throw SlideError.unsafeEdit("取り込みスライドのリンク先がありません") }
                let rels = try relationships(link.part)
                guard let node = rels.children.first(where: { $0.attr("Id") == link.relationshipID }) else { throw SlideError.invalidRelationship(part: link.part, detail: "取り込みリンクがありません") }
                node.set("Target", OPCPackage.uri(for: "/" + target) + link.fragment); saveRelationships(link.part, rels)
            }
        }
    }
    func validateCloneDependencies() throws {
        for clone in presentation.slideClones.values {
            for path in clone.parts.keys where path.hasSuffix(".rels") {
                let root = try parse(path)
                guard let source = PPTXInventory.relationshipSource(path) else { throw SlideError.invalidRelationship(part: path, detail: "取り込みrelationshipの位置が不正です") }
                for rel in root.children where rel.attr("TargetMode") != "External" {
                    guard let target = rel.attr("Target"), parts[try OPCPackage.resolve(target, from: source)] != nil else {
                        throw SlideError.invalidRelationship(part: source, detail: "取り込み依存先がありません")
                    }
                }
            }
        }
    }
    func registerClonedMasters(_ main: MarkupNode, rels: MarkupNode, strict: Bool) throws {
        let masters = overrides.filter { $0.value == "application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml" }.keys.sorted()
        guard !masters.isEmpty else { return }
        let list: MarkupNode
        if let existing = main.child("sldMasterIdLst") { list = existing }
        else { list = try MarkupNode.fragment("<p:sldMasterIdLst/>", strict: strict); main.replace("sldMasterIdLst", with: list, first: true) }
        var ids = Set(list.children.compactMap { $0.attr("id").flatMap(UInt32.init) })
        for path in masters {
            let rid = try addRelationship(rels, type: "slideMaster", target: "/" + path, strict: strict)
            if list.children.contains(where: { $0.rel("id") == rid }) { continue }
            var n: UInt32 = 2_147_483_648
            while ids.contains(n), n < UInt32.max { n += 1 }
            guard !ids.contains(n) else { throw SlideError.limitExceeded("slide master ID") }
            ids.insert(n)
            list.content.append(.node(try MarkupNode.fragment("<p:sldMasterId id=\"\(n)\" r:id=\"\(rid)\"/>", strict: strict)))
        }
    }
    func normalizeClonedLayoutIDs() throws {
        let cloned = Set(presentation.slideClones.values.flatMap { $0.contentTypes.filter { $0.value.hasSuffix("slideMaster+xml") }.keys })
        guard !cloned.isEmpty else { return }
        let masters = Set(presentation.packageParts.filter { $0.contentType?.hasSuffix("slideMaster+xml") == true }.map(\.path))
            .union(overrides.filter { $0.value.hasSuffix("slideMaster+xml") }.keys)
        var used = Set<UInt32>()
        for path in masters.subtracting(cloned) {
            for node in try parse(path).descendants("sldLayoutId") { if let id = node.attr("id").flatMap(UInt32.init) { used.insert(id) } }
        }
        var next: UInt32 = 2_147_483_648
        for path in cloned.sorted() {
            let root = try parse(path)
            for node in root.descendants("sldLayoutId") {
                while used.contains(next), next < UInt32.max { next += 1 }
                guard !used.contains(next) else { throw SlideError.limitExceeded("slide layout ID") }
                node.set("id", String(next)); used.insert(next)
            }
            put(path, root.xml)
        }
    }
    func relationships(_ source: String) throws -> MarkupNode {
        let path = OPCPackage.relationshipPart(for:source)
        if parts[path] != nil { return try parse(path) }
        return try MarkupNode.parse(Data("<Relationships xmlns=\"\(NS.rels)\"/>".utf8),part:path,limits:.init())
    }
    @discardableResult func addRelationship(_ root: MarkupNode, type: String, target: String, external: Bool = false, strict: Bool = false) throws -> String {
        let target = external ? target : OPCPackage.uri(for: target)
        let uri = type.hasPrefix("http") ? type : "\(strict ? NS.strictR : NS.r)/\(type)"
        if let existing = root.children.first(where:{ $0.attr("Type") == uri && $0.attr("Target") == target && ($0.attr("TargetMode") == "External") == external }), let id = existing.attr("Id") { return id }
        var n = 1; let used = Set(root.children.compactMap { $0.attr("Id") })
        while used.contains("ssrId\(n)") { n += 1 }
        let id = "ssrId\(n)"
        let xml = "<Relationship xmlns=\"\(NS.rels)\" Id=\"\(id)\" Type=\"\(escapeXML(uri))\" Target=\"\(escapeXML(target))\"\(external ? " TargetMode=\"External\"" : "")/>"
        root.content.append(.node(try MarkupNode.parse(Data(xml.utf8),part:"generated relationship",limits:.init())))
        return id
    }
    func saveRelationships(_ source: String, _ root: MarkupNode) { put(OPCPackage.relationshipPart(for:source),root.xml) }
    func linkID(_ link: Link, rels: MarkupNode, strict: Bool) throws -> String {
        switch link {
        case .external(let url): return try addRelationship(rels,type:"hyperlink",target:url,external:true,strict:strict)
        case .slide(let target):
            let path = slidePaths[target] ?? target
            guard parts[path] != nil || slidePaths.values.contains(path) else { throw SlideError.invalidModel("リンク先スライドがありません") }
            return try addRelationship(rels,type:"slide",target:"/"+path,strict:strict)
        }
    }
    func imageID(_ image: Image, rels: MarkupNode, strict: Bool) throws -> String {
        let path: String
        if let data = image.data, let type = image.contentType {
            let ext = ["image/png":"png","image/jpeg":"jpg","image/gif":"gif","image/tiff":"tiff","image/bmp":"bmp","image/svg+xml":"svg","image/x-emf":"emf","image/x-wmf":"wmf"][type]!
            path = unique("ppt/media",ext); parts[path] = data; overrides[path] = type
        } else if let source = image.path, parts[source] != nil { path = source }
        else { throw SlideError.invalidModel("画像bytesまたは元パーツがありません") }
        return try addRelationship(rels,type:"image",target:"/"+path,strict:strict)
    }
    func elementXML(_ e: Element, id: String, rels: MarkupNode, strict: Bool, ids: inout Set<String>) throws -> MarkupNode {
        try Task.checkCancellation()
        guard e.kind != .opaque, e.rawXML == nil else { throw SlideError.unsafeEdit("未解釈要素は別スライドへコピーできません") }
        guard e.frame != nil else { throw SlideError.invalidModel("新規要素にはframeが必要です") }
        if e.placeholder != nil { throw SlideError.unsafeEdit("新規プレースホルダーの作成は未対応です") }
        if let g = e.geometry, !PPTXXML.validPresets.contains(g.preset) { throw SlideError.invalidModel("未知の図形プリセット: \(g.preset)") }
        guard e.customGeometry == nil, e.effects == nil, e.chart == nil, e.diagram == nil, e.media == nil, e.nativeFeatures == nil else { throw SlideError.unsafeEdit("読取専用のgeometry・効果・chart・diagramを新規保存できません") }
        guard e.model3D == nil, e.spatialGeometry == nil, e.scene3D == nil, e.shape3D == nil else { throw SlideError.unsafeEdit("3D投影の新規保存は未対応です") }
        guard e.transform2D == nil, e.textPath == nil, e.geometryEngine == nil, e.enhancedGeometry == nil, e.equation == nil else { throw SlideError.unsafeEdit("ODP高度図形・数式の新規保存は未対応です") }
        guard e.image?.crop == nil, e.nativeGeometry == nil, e.nativeObjectID == nil, e.sourceProperties == nil else { throw SlideError.unsafeEdit("画像crop・native object・原本投影の新規保存は未対応です") }
        let cnv = "<p:cNvPr id=\"\(id)\" name=\"\(escapeXML(e.name.isEmpty ? "Shape \(id)" : e.name))\"\(e.image.map { " descr=\"\(escapeXML($0.alternativeText))\"" } ?? "")/>"
        let text: String = try e.text.map { try PPTXXML.text($0,relationship:{ try self.linkID($0,rels:rels,strict:strict) }) } ?? ""
        let geometry = e.geometry.map { "<a:prstGeom prst=\"\(escapeXML($0.preset))\"><a:avLst/></a:prstGeom>" } ?? "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom>"
        let properties = try PPTXXML.transform(e) + geometry + PPTXXML.fill(e.fill ?? Fill.none) + PPTXXML.line(e.stroke)
        let xml: String
        switch e.kind {
        case .shape:
            xml = "<p:sp><p:nvSpPr>\(cnv)<p:cNvSpPr\(e.isTextBox ? " txBox=\"1\"" : "")/><p:nvPr/></p:nvSpPr><p:spPr>\(properties)</p:spPr>\(text)</p:sp>"
        case .connector:
            xml = "<p:cxnSp><p:nvCxnSpPr>\(cnv)<p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr><p:spPr>\(properties)</p:spPr>\(text)</p:cxnSp>"
        case .image:
            guard let image = e.image else { throw SlideError.invalidModel("新規画像内容がありません") }
            let rid = try imageID(image,rels:rels,strict:strict)
            xml = "<p:pic><p:nvPicPr>\(cnv)<p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed=\"\(rid)\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr>\(properties)</p:spPr></p:pic>"
        case .table:
            guard e.table!.rows.allSatisfy({ $0.allSatisfy { $0.rowSpan == 1 && $0.columnSpan == 1 && !$0.isMergeContinuation } }) else { throw SlideError.unsafeEdit("結合表の新規保存は未対応です") }
            xml = "<p:graphicFrame><p:nvGraphicFramePr>\(cnv)<p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>\(PPTXXML.transform(e,p:true))<a:graphic><a:graphicData uri=\"\(strict ? "http://purl.oclc.org/ooxml/drawingml/table" : "http://schemas.openxmlformats.org/drawingml/2006/table")\">\(try PPTXXML.table(e.table!,relationship:{ try self.linkID($0,rels:rels,strict:strict) }))</a:graphicData></a:graphic></p:graphicFrame>"
        case .group:
            guard let c = e.childFrame, c.width > 0, c.height > 0 else { throw SlideError.invalidModel("新規グループには正のchildFrameが必要です") }
            var children = ""
            for child in e.children { let newID = nextID(&ids); children += try elementXML(child,id:newID,rels:rels,strict:strict,ids:&ids).xml }
            xml = "<p:grpSp><p:nvGrpSpPr>\(cnv)<p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr>\(PPTXXML.transform(e))</p:grpSpPr>\(children)</p:grpSp>"
        case .opaque: throw SlideError.unsafeEdit("新規opaque要素は未対応です")
        }
        return try MarkupNode.fragment(xml,strict:strict)
    }
    func nextID(_ ids: inout Set<String>) -> String { var n = 2; while ids.contains(String(n)) { n += 1 }; let id = String(n); ids.insert(id); return id }
    func slideXML(_ slide: Slide, path: String, layout: String) throws {
        guard slide.sizeOverride == nil, slide.transition == nil, slide.timing == nil, slide.comments == nil, slide.commentThreads == nil, slide.media == nil, slide.nativeFeatures == nil else { throw SlideError.unsafeEdit("遷移・時間構造・コメント・追加内容の新規保存は未対応です") }
        guard slide.showsMasterShapes == nil, slide.colorMapOverride == nil, slide.usesMasterColorMapping == nil, slide.backgroundReference == nil, slide.themeOverridePath == nil else { throw SlideError.unsafeEdit("継承投影を持つスライドの新規保存は未対応です") }
        let rels = try relationships(path)
        try addRelationship(rels,type:"slideLayout",target:"/"+layout)
        var ids: Set<String> = ["1"], elements = ""
        for e in slide.elements { elements += try elementXML(e,id:nextID(&ids),rels:rels,strict:false,ids:&ids).xml }
        let bg = try slide.background.map { "<p:bg><p:bgPr>\(try PPTXXML.fill($0))<a:effectLst/></p:bgPr></p:bg>" } ?? ""
        put(path,PPTXXML.envelope("sld","<p:cSld name=\"\(escapeXML(slide.name))\">\(bg)<p:spTree>\(PPTXXML.groupHeader())\(elements)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>"),type:"application/vnd.openxmlformats-officedocument.presentationml.slide+xml")
        if slide.isHidden { let root = try parse(path); root.set("show","0"); put(path,root.xml) }
        if let notes = slide.notes { let note = try newNotes(notes,slidePath:path); try addRelationship(rels,type:"notesSlide",target:"/"+note) }
        saveRelationships(path,rels)
    }
    func ensureNotesMaster() throws -> String {
        // Reuse an existing notes master if present. A newly created master gets its own theme reference.
        if let storage = presentation.storage {
            let package = try OPCPackage(storage.data,limits:storage.limits)
            if let path = try package.relationships(from:storage.mainPart).values.first(where:{$0.type == "notesMaster"})?.path { return path }
        }
        if let notesMasterPath { return notesMasterPath }
        if let imported = overrides.keys.sorted().first(where: { overrides[$0] == "application/vnd.openxmlformats-officedocument.presentationml.notesMaster+xml" }) {
            notesMasterPath = imported; return imported
        }
        let path = unique("ppt/notesMasters","xml")
        notesMasterPath = path
        let placeholders = notesPlaceholder(id:2,type:"sldImg",index:2,frame:.init(x:55,y:55,width:430,height:270)) + notesPlaceholder(id:3,type:"body",index:3,frame:.init(x:55,y:345,width:430,height:315)) + notesPlaceholder(id:4,type:"sldNum",index:5,frame:.init(x:430,y:685,width:55,height:25))
        put(path,PPTXXML.envelope("notesMaster","<p:cSld><p:spTree>\(PPTXXML.groupHeader())\(placeholders)</p:spTree></p:cSld>\(PPTXXML.colorMap)<p:notesStyle/>"),type:"application/vnd.openxmlformats-officedocument.presentationml.notesMaster+xml")
        let themePath: String
        if parts["ppt/theme/theme1.xml"] != nil { themePath = "ppt/theme/theme1.xml" } else { themePath = unique("ppt/theme","xml"); put(themePath,PPTXXML.theme(presentation.theme),type:"application/vnd.openxmlformats-officedocument.theme+xml") }
        let rel = try relationships(path); try addRelationship(rel,type:"theme",target:"/"+themePath); saveRelationships(path,rel)
        return path
    }
    func notesPlaceholder(id: Int, type: String, index: Int, frame: Rect? = nil, text: String = "") -> String {
        let properties = frame.map { PPTXXML.transform(Element(frame:$0)) + "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom>" } ?? ""
        return "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"\(type)\"/><p:cNvSpPr/><p:nvPr><p:ph type=\"\(type)\" idx=\"\(index)\"/></p:nvPr></p:nvSpPr><p:spPr>\(properties)</p:spPr>\(text)</p:sp>"
    }
    func newNotes(_ notes: TextBody, slidePath: String) throws -> String {
        let master = try ensureNotesMaster(), path = unique("ppt/notesSlides","xml"), rels = try relationships(path)
        try addRelationship(rels,type:"notesMaster",target:"/"+master); try addRelationship(rels,type:"slide",target:"/"+slidePath)
        let text = try PPTXXML.text(notes,relationship:{ try self.linkID($0,rels:rels,strict:false) })
        let masterNode = try parse(master)
        let placeholders = masterNode.child("cSld")?.child("spTree")?.named("sp").compactMap { $0.child("nvSpPr")?.child("nvPr")?.child("ph") } ?? []
        let bodies = placeholders.filter { $0.attr("type") == "body" }
        guard bodies.count == 1 else { throw SlideError.unsafeEdit("ノートmasterの本文placeholderが一意ではありません") }
        var shape = "", id = 2
        for type in ["sldImg", "body", "sldNum"] {
            if let ph = placeholders.first(where: { $0.attr("type") == type }) {
                shape += notesPlaceholder(id:id,type:type,index:Int(ph.attr("idx") ?? "0") ?? 0,text:type == "body" ? text : ""); id += 1
            }
        }
        put(path,PPTXXML.envelope("notes","<p:cSld><p:spTree>\(PPTXXML.groupHeader())\(shape)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>"),type:"application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml")
        saveRelationships(path,rels); return path
    }
    func contentTypes() throws {
        let path = "[Content_Types].xml"
        let root = parts[path] != nil ? try parse(path) : try MarkupNode.parse(Data("<Types xmlns=\"\(NS.types)\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/></Types>".utf8),part:path,limits:.init())
        for (part,type) in overrides.sorted(by:{$0.key < $1.key}) {
            if let existing = root.children.first(where: { node in
                guard let value = node.attr("PartName") else { return false }
                return (try? OPCPackage.resolve(value, from: "")) == part
            }) { existing.set("ContentType",type) }
            else { let n = try MarkupNode.parse(Data("<Override xmlns=\"\(NS.types)\" PartName=\"\(escapeXML(OPCPackage.uri(for: "/" + part)))\" ContentType=\"\(escapeXML(type))\"/>".utf8),part:path,limits:.init()); root.content.append(.node(n)) }
        }
        put(path,root.xml)
    }
    func create() throws {
        let main = "ppt/presentation.xml", layout = "ppt/slideLayouts/slideLayout1.xml", master = "ppt/slideMasters/slideMaster1.xml", theme = "ppt/theme/theme1.xml"
        put(theme,PPTXXML.theme(presentation.theme),type:"application/vnd.openxmlformats-officedocument.theme+xml")
        put(layout,PPTXXML.envelope("sldLayout","<p:cSld name=\"Blank\"><p:spTree>\(PPTXXML.groupHeader())</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>"),type:"application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml")
        let layoutRoot = try parse(layout); layoutRoot.set("type","blank"); layoutRoot.set("preserve","1"); put(layout,layoutRoot.xml)
        let layoutRels = try relationships(layout); try addRelationship(layoutRels,type:"slideMaster",target:"/"+master); saveRelationships(layout,layoutRels)
        put(master,PPTXXML.envelope("sldMaster","<p:cSld><p:spTree>\(PPTXXML.groupHeader())</p:spTree></p:cSld>\(PPTXXML.colorMap)<p:sldLayoutIdLst><p:sldLayoutId id=\"2147483649\" r:id=\"ssrId1\"/></p:sldLayoutIdLst><p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles>"),type:"application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml")
        let masterRels = try relationships(master); try addRelationship(masterRels,type:"slideLayout",target:"/"+layout); try addRelationship(masterRels,type:"theme",target:"/"+theme); saveRelationships(master,masterRels)
        let mainRels = try relationships(main); let masterID = try addRelationship(mainRels,type:"slideMaster",target:"/"+master)
        for (i,slide) in presentation.slides.enumerated() { slidePaths[slide.id] = presentation.slideClones[slide.id]?.slidePath ?? "ppt/slides/slide\(i+1).xml" }
        try resolveCloneLinks()
        var list = ""
        for (i,slide) in presentation.slides.enumerated() {
            try Task.checkCancellation()
            let path = slidePaths[slide.id]!
            if let clone = presentation.slideClones[slide.id] {
                if slide != clone.baseline { try patchSlide(slide, original: clone.baseline, path: path, storage: nil, clone: clone) }
            } else { try slideXML(slide,path:path,layout:layout) }
            let rid = try addRelationship(mainRels,type:"slide",target:"/"+path); list += "<p:sldId id=\"\(256+i)\" r:id=\"\(rid)\"/>"
        }
        // PowerPoint discovers notes masters through relationships. The optional ID list is omitted.
        for path in overrides.keys.sorted() where overrides[path] == "application/vnd.openxmlformats-officedocument.presentationml.notesMaster+xml" { let rid = try addRelationship(mainRels,type:"notesMaster",target:"/"+path); _ = rid }
        let defaults = (1...9).map { "<a:lvl\($0)pPr><a:defRPr sz=\"1800\"><a:solidFill><a:schemeClr val=\"tx1\"/></a:solidFill><a:latin typeface=\"+mn-lt\"/><a:ea typeface=\"+mn-ea\"/><a:cs typeface=\"+mn-cs\"/></a:defRPr></a:lvl\($0)pPr>" }.joined()
        put(main,PPTXXML.envelope("presentation","<p:sldMasterIdLst><p:sldMasterId id=\"2147483648\" r:id=\"\(masterID)\"/></p:sldMasterIdLst><p:sldIdLst>\(list)</p:sldIdLst><p:sldSz cx=\"\(PPTXXML.emu(presentation.size.width))\" cy=\"\(PPTXXML.emu(presentation.size.height))\"/><p:notesSz cx=\"6858000\" cy=\"9144000\"/><p:defaultTextStyle>\(defaults)</p:defaultTextStyle>"),type:"application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml")
        let mainNode = try parse(main); mainNode.set("firstSlideNum",presentation.firstSlideNumber.map(String.init)); try registerClonedMasters(mainNode, rels: mainRels, strict: false); put(main, mainNode.xml)
        saveRelationships(main,mainRels)
        put("docProps/core.xml",PPTXXML.core(presentation.metadata),type:"application/vnd.openxmlformats-package.core-properties+xml")
        let rootRels = try relationships(""); try addRelationship(rootRels,type:"officeDocument",target:"/"+main); try addRelationship(rootRels,type:NS.rels+"/metadata/core-properties",target:"/docProps/core.xml"); saveRelationships("",rootRels)
        try contentTypes()
    }
    func edit(_ storage: Preservation) throws {
        let main = try parse(storage.mainPart), strict = main.namespace == NS.strictP
        let mainRels = try relationships(storage.mainPart)
        let original = Dictionary(uniqueKeysWithValues:storage.originalSlides.map { ($0.id,$0) })
        let removed = Set(storage.originalSlides.map(\.id)).subtracting(presentation.slides.map(\.id))
        // Refuse removing slides referenced by another retained part. Do not leave dangling navigation.
        let removedPaths = Set(removed.compactMap { storage.slidePaths[$0] })
        if !removedPaths.isEmpty {
            let inventory = try graph(storage)
            if let scope = inventory.unresolvedScopes.first(where: { $0.slideID.map { !removed.contains($0) } ?? true }) {
                throw SlideError.unsafeEdit("スライド削除に影響する未知参照を判断できません: \(scope.part) \(scope.path)")
            }
            let package = try OPCPackage(storage.data,limits:storage.limits)
            let ignored = removedPaths.union(removed.compactMap { storage.notesPaths[$0] }).union([storage.mainPart])
            for path in storage.archive.paths where path.hasSuffix(".rels") {
                let components = path.split(separator:"/").map(String.init)
                guard let index = components.firstIndex(of:"_rels"), let filename = components.last, filename.hasSuffix(".rels") else { continue }
                let source = (components.prefix(index) + [String(filename.dropLast(5))]).joined(separator:"/")
                if ignored.contains(source) { continue }
                let rels = try package.relationships(from:source == ".rels" ? "" : source)
                if rels.values.contains(where:{ $0.path.map { removedPaths.contains($0) } ?? false }) { throw SlideError.unsafeEdit("削除スライドを他のパーツが参照しています: \(source)") }
            }
            warnings.add(.orphanedParts,part:storage.mainPart,element:"sldIdLst",message:"削除スライドの未参照パーツを保全のため残します")
        }
        for slide in presentation.slides where original[slide.id] == nil && presentation.slideClones[slide.id] == nil { slidePaths[slide.id] = unique("ppt/slides","xml"); parts[slidePaths[slide.id]!] = Data() }
        try resolveCloneLinks()
        var usedIDs = Set(storage.originalSlides.map(\.id)), next: UInt32 = 256, list = ""
        for slide in presentation.slides {
            try Task.checkCancellation()
            let path = slidePaths[slide.id]!
            let id: String
            if let old = original[slide.id] {
                id = slide.id
                if slide != old { try patchSlide(slide,original:old,path:path,storage:storage) }
            } else {
                if let clone = presentation.slideClones[slide.id] {
                    if slide != clone.baseline { try patchSlide(slide, original: clone.baseline, path: path, storage: storage, clone: clone) }
                } else {
                    guard !strict else { throw SlideError.unsafeEdit("Strict文書へのスライド追加は未対応です") }
                    let layout = slide.layoutPath ?? storage.originalSlides.compactMap(\.layoutPath).first
                    guard let layout, parts[layout] != nil else { throw SlideError.unsafeEdit("追加スライドのレイアウトがありません") }
                    try slideXML(slide,path:path,layout:layout)
                }
                while usedIDs.contains(String(next)) { next += 1 }; id = String(next); usedIDs.insert(id)
            }
            let rid = try addRelationship(mainRels,type:"slide",target:"/"+path,strict:strict)
            list += "<p:sldId id=\"\(id)\" r:id=\"\(rid)\"/>"
        }
        if presentation.slides.map(\.id) != storage.originalSlides.map(\.id) {
            main.replace("sldIdLst",with:try MarkupNode.fragment("<p:sldIdLst>\(list)</p:sldIdLst>",strict:strict))
            mainRels.content.removeAll { item in guard case .node(let n) = item, let target = n.attr("Target"), n.attr("Type")?.hasSuffix("/slide") == true else { return false }; return (try? OPCPackage.resolve(target,from:storage.mainPart)).map { removedPaths.contains($0) } ?? false }
        }
        if presentation.size != storage.originalSize, let size = main.child("sldSz") { size.set("cx",PPTXXML.emu(presentation.size.width)); size.set("cy",PPTXXML.emu(presentation.size.height)) }
        main.set("firstSlideNum",presentation.firstSlideNumber.map(String.init))
        // Register one notes master relationship; keep any original optional ID list unchanged.
        try registerClonedMasters(main, rels: mainRels, strict: strict)
        for path in overrides.keys.sorted() where overrides[path] == "application/vnd.openxmlformats-officedocument.presentationml.notesMaster+xml" {
            try addRelationship(mainRels,type:"notesMaster",target:"/"+path,strict:strict)
        }
        if presentation.slides.map(\.id) != storage.originalSlides.map(\.id) || presentation.size != storage.originalSize || !overrides.isEmpty || presentation.firstSlideNumber != storage.originalFirstSlideNumber { put(storage.mainPart,main.xml); saveRelationships(storage.mainPart,mainRels) }
        if presentation.metadata != storage.originalMetadata { try patchMetadata(storage) }
        if !overrides.isEmpty { try contentTypes() }
    }
    func patchMetadata(_ storage: Preservation) throws {
        let package = try OPCPackage(storage.data,limits:storage.limits)
        let path = try package.relationships(from:"").values.first { $0.type == "core-properties" }?.path
        if let path {
            let node = try parse(path)
            let values = [("title",presentation.metadata.title),("subject",presentation.metadata.subject),("creator",presentation.metadata.creator),("description",presentation.metadata.description),("keywords",presentation.metadata.keywords)]
            for (name,value) in values {
                let uri = name == "keywords" ? NS.core : NS.dc
                if let existing = node.children.first(where:{$0.name == name && $0.namespace == uri}) { existing.content = value.map { [.text($0)] } ?? []; if value == nil { node.content.removeAll { if case .node(let n) = $0 { n === existing } else { false } } } }
                else if let value { node.content.append(.node(try MarkupNode.parse(Data("<ss:\(name) xmlns:ss=\"\(uri)\">\(escapeXML(value))</ss:\(name)>".utf8),part:path,limits:.init()))) }
            }
            put(path,node.xml)
        } else {
            let new = unique("docProps","xml"); put(new,PPTXXML.core(presentation.metadata),type:"application/vnd.openxmlformats-package.core-properties+xml")
            let root = try relationships(""); try addRelationship(root,type:NS.rels+"/metadata/core-properties",target:"/"+new); saveRelationships("",root)
        }
    }
    func patchSlide(_ slide: Slide, original: Slide, path: String, storage: Preservation?, clone: SlideClone? = nil) throws {
        let root = try parse(path), strict = root.namespace == NS.strictP, rels = try relationships(path)
        guard let c = root.child("cSld"), let sp = c.child("spTree") else { throw SlideError.corruptedPackage("スライド構造が不正です") }
        c.set("name",slide.name.isEmpty ? nil : slide.name); root.set("show",slide.isHidden ? "0" : nil)
        guard slide.showsMasterShapes == original.showsMasterShapes, slide.colorMapOverride == original.colorMapOverride, slide.usesMasterColorMapping == original.usesMasterColorMapping, slide.backgroundReference == original.backgroundReference, slide.themeOverridePath == original.themeOverridePath else { throw SlideError.unsafeEdit("読取専用の継承書式を変更できません") }
        guard slide.sizeOverride == original.sizeOverride, slide.transition == original.transition, slide.timing == original.timing, slide.comments == original.comments, slide.commentThreads == original.commentThreads, slide.media == original.media, slide.nativeFeatures == original.nativeFeatures else { throw SlideError.unsafeEdit("読取専用の遷移・時間構造・コメント・追加内容を変更できません") }
        if slide.layoutPath != original.layoutPath { throw SlideError.unsafeEdit("既存スライドのレイアウト変更は未対応です") }
        if slide.background != original.background {
            guard !isReadOnlyFill(slide.background), !isReadOnlyFill(original.background) else { throw SlideError.unsafeEdit("追加の背景塗りを変更できません") }
            c.replace("bg",with:try slide.background.map { try MarkupNode.fragment("<p:bg><p:bgPr>\(try PPTXXML.fill($0))<a:effectLst/></p:bgPr></p:bg>",strict:strict) },first:true)
            if original.background == nil && c.child("bg") != nil { warning(path,"bg","背景の継承参照を新しい塗りへ置換しました") }
        }
        func elementIDs(_ elements: [Element]) -> Set<String> { Set(elements.flatMap { [$0.id] + Array(elementIDs($0.children)) }) }
        let removed = elementIDs(original.elements).subtracting(elementIDs(slide.elements))
        if !removed.isEmpty {
            if let clone { try PPTXInventory.validateDeletion(clone.graph, part: path, removed: removed) }
            else if let storage { try PPTXInventory.validateDeletion(graph(storage), part: path, removed: removed) }
            else { throw SlideError.unsafeEdit("削除参照の原本がありません") }
        }
        var ids = Set(sp.descendants("cNvPr").compactMap { $0.attr("id") }); ids.insert("1")
        try patchElements(slide.elements,original:original.elements,parent:sp,path:path,rels:rels,strict:strict,ids:&ids)
        if slide.notes != original.notes {
            if clone?.notesOmitted ?? storage?.notesOmitted ?? false { throw SlideError.unsafeEdit("ノート省略で読んだ文書のノートを編集できません") }
            if let notePath = clone?.notesPath ?? storage?.notesPaths[slide.id] {
                let notesRoot = try parse(notePath), notesRels = try relationships(notePath)
                let bodyShapes = notesRoot.child("cSld")?.child("spTree")?.named("sp").filter { let type = $0.child("nvSpPr")?.child("nvPr")?.child("ph")?.attr("type"); return type == nil || type == "body" } ?? []
                guard bodyShapes.count == 1, let shape = bodyShapes.first else { throw SlideError.unsafeEdit("複数のノート領域は編集できません") }
                guard !containsEquationSource(shape.child("txBody")) else { throw SlideError.unsafeEdit("数式を含むノートの再構成は未対応です") }
                let xml = try PPTXXML.text(slide.notes ?? TextBody(),relationship:{ try self.linkID($0,rels:notesRels,strict:strict) })
                shape.replace("txBody",with:try MarkupNode.fragment(xml,strict:strict)); put(notePath,notesRoot.xml); saveRelationships(notePath,notesRels)
                warning(notePath,"txBody","ノート文字領域を再構成しました",slideID:slide.id)
            } else if let notes = slide.notes {
                guard !strict else { throw SlideError.unsafeEdit("Strict文書へのノート追加は未対応です") }
                let notePath = try newNotes(notes,slidePath:path); try addRelationship(rels,type:"notesSlide",target:"/"+notePath)
            }
        }
        put(path,root.xml); saveRelationships(path,rels)
    }
    func patchElements(_ elements: [Element], original: [Element], parent: MarkupNode, path: String, rels: MarkupNode, strict: Bool, ids: inout Set<String>) throws {
        let shapeNodes = parent.children.filter { !($0.isP && ["nvGrpSpPr","grpSpPr"].contains($0.name)) }
        guard shapeNodes.count == original.count else { throw SlideError.unsafeEdit("図形と原本ノードの対応が不明です") }
        let old = Dictionary(uniqueKeysWithValues:zip(original,shapeNodes).map { ($0.0.id,($0.0,$0.1)) })
        var nodes: [MarkupNode] = []
        for e in elements {
            try Task.checkCancellation()
            if let (o,n) = old[e.id] { if e != o { try patchElement(e,original:o,node:n,path:path,rels:rels,strict:strict,ids:&ids) }; nodes.append(n) }
            else { nodes.append(try elementXML(e,id:nextID(&ids),rels:rels,strict:strict,ids:&ids)) }
        }
        let header = parent.content.filter { if case .node(let n) = $0 { n.isP && ["nvGrpSpPr","grpSpPr"].contains(n.name) } else { false } }
        parent.content = header + nodes.map(MarkupNode.Content.node)
    }
    func patchElement(_ e: Element, original o: Element, node: MarkupNode, path: String, rels: MarkupNode, strict: Bool, ids: inout Set<String>) throws {
        guard e.kind == o.kind, e.rawXML == o.rawXML, e.placeholder == o.placeholder, e.isTextBox == o.isTextBox else { throw SlideError.unsafeEdit("図形種類・未解釈XML・プレースホルダーの変更は未対応です") }
        guard e.customGeometry == o.customGeometry, e.effects == o.effects, e.chart == o.chart, e.diagram == o.diagram, e.media == o.media, e.nativeFeatures == o.nativeFeatures, e.image?.crop == o.image?.crop else { throw SlideError.unsafeEdit("読取専用の投影を変更できません") }
        guard e.nativeGeometry == o.nativeGeometry, e.nativeObjectID == o.nativeObjectID, e.sourceProperties == o.sourceProperties else { throw SlideError.unsafeEdit("native object・原本投影を変更できません") }
        guard e.model3D == o.model3D, e.spatialGeometry == o.spatialGeometry, e.scene3D == o.scene3D, e.shape3D == o.shape3D else { throw SlideError.unsafeEdit("読取専用の3D投影を変更できません") }
        guard e.transform2D == o.transform2D, e.textPath == o.textPath, e.geometryEngine == o.geometryEngine, e.enhancedGeometry == o.enhancedGeometry, e.equation == o.equation else { throw SlideError.unsafeEdit("読取専用のODP高度図形・数式を変更できません") }
        if e.kind == .opaque { throw SlideError.unsafeEdit("未解釈要素は編集できません") }
        let nv = node.children.first { $0.name.hasPrefix("nv") && $0.isP }
        if e.name != o.name { nv?.child("cNvPr")?.set("name",e.name) }
        let propsName = e.kind == .group ? "grpSpPr" : "spPr"
        var props = node.child(propsName)
        if props == nil && e.kind != .table { props = try MarkupNode.fragment("<p:\(propsName)/>",strict:strict); node.replace(propsName,with:props) }
        if e.frame != o.frame || e.rotation != o.rotation || e.isFlippedHorizontally != o.isFlippedHorizontally || e.isFlippedVertically != o.isFlippedVertically || e.childFrame != o.childFrame {
            let target = e.kind == .table ? node : props!
            if e.frame == nil { target.replace("xfrm",with:nil) }
            else { target.replace("xfrm",with:try MarkupNode.fragment(PPTXXML.transform(e,p:e.kind == .table),strict:strict),first:true) }
        }
        if e.geometry != o.geometry {
            guard o.customGeometry == nil else { throw SlideError.unsafeEdit("自由曲線をプリセットへ置換できません") }
            if let g = e.geometry, !PPTXXML.validPresets.contains(g.preset) { throw SlideError.invalidModel("未知の図形プリセット: \(g.preset)") }
            guard e.kind == .shape || e.kind == .connector else { throw SlideError.unsafeEdit("この要素のgeometry変更は未対応です") }
            props?.remove(["prstGeom","custGeom"])
            if let g = e.geometry { props?.content.append(.node(try MarkupNode.fragment("<a:prstGeom prst=\"\(escapeXML(g.preset))\"><a:avLst/></a:prstGeom>",strict:strict))) }
            warning(path,"geometry","図形の調整値を新しいプリセットへ置換しました")
        }
        if e.fill != o.fill {
            guard !isReadOnlyFill(e.fill), !isReadOnlyFill(o.fill) else { throw SlideError.unsafeEdit("追加の塗りを変更できません") }
            props?.remove(["solidFill","noFill","gradFill","blipFill","pattFill","grpFill"]); if let f = e.fill { props?.content.append(.node(try MarkupNode.fragment(PPTXXML.fill(f),strict:strict))) }; warning(path,"fill","塗りを指定値へ置換しました")
        }
        if e.stroke != o.stroke { props?.replace("ln",with:try MarkupNode.fragment(PPTXXML.line(e.stroke),strict:strict)); warning(path,"ln","線書式を指定値へ置換しました") }
        if e.geometry != o.geometry || e.fill != o.fill || e.stroke != o.stroke, let props {
            let order = ["xfrm", "prstGeom", "custGeom", "noFill", "solidFill", "gradFill", "blipFill", "pattFill", "grpFill", "ln", "effectLst", "effectDag", "scene3d", "sp3d", "extLst"]
            props.content = props.content.enumerated().sorted { lhs, rhs in
                func rank(_ item: MarkupNode.Content) -> Int { if case .node(let n) = item { return order.firstIndex(of:n.name) ?? order.count }; return order.count }
                let l = rank(lhs.element), r = rank(rhs.element); return l == r ? lhs.offset < rhs.offset : l < r
            }.map(\.element)
        }
        if e.text != o.text {
            guard !containsEquationSource(node.child("txBody")) else { throw SlideError.unsafeEdit("数式を含む文字領域の再構成は未対応です") }
            guard e.text?.listStyle == o.text?.listStyle else { throw SlideError.unsafeEdit("リスト既定書式の編集は未対応です") }
            let generated = try e.text.map { value in var value = value; value.listStyle = nil; return try MarkupNode.fragment(PPTXXML.text(value,relationship:{ try self.linkID($0,rels:rels,strict:strict) }),strict:strict) }
            if let existing = node.child("txBody"), let generated, let before = o.text, let after = e.text {
                // Preserve bodyPr and lstStyle exactly when only the paragraphs changed.
                if before.insets == after.insets, before.verticalAlignment == after.verticalAlignment, before.wrapsText == after.wrapsText {
                    existing.remove(["p"]); existing.content += generated.named("p").map(MarkupNode.Content.node)
                } else { if let list = existing.child("lstStyle") { generated.replace("lstStyle",with:list) }; node.replace("txBody",with:generated) }
            } else { node.replace("txBody",with:generated) }
            warning(path,"txBody","文字段落を再構成しました。未対応の文字領域内情報は引き継ぎません",feature:"TXT-002",elementID:e.id)
        }
        if e.image != o.image {
            guard let image = e.image, let blip = node.child("blipFill")?.child("blip") else { throw SlideError.unsafeEdit("画像の削除または外部参照編集は未対応です") }
            let rid = try imageID(image,rels:rels,strict:strict); blip.setRel("embed",rid,strict:strict); nv?.child("cNvPr")?.set("descr",image.alternativeText)
        }
        if e.table != o.table {
            guard let t = e.table, let target = node.child("graphic")?.child("graphicData") else { throw SlideError.unsafeEdit("表構造がありません") }
            guard t.rows.allSatisfy({$0.allSatisfy { $0.rowSpan == 1 && $0.columnSpan == 1 && !$0.isMergeContinuation }}) else { throw SlideError.unsafeEdit("結合表の編集保存は未対応です") }
            if let before = o.table, let tableNode = target.child("tbl"), try patchTable(t, original: before, node: tableNode, path: path, rels: rels, strict: strict) { return }
            guard !containsEquationSource(target.child("tbl")) else { throw SlideError.unsafeEdit("数式を含む表の再構成は未対応です") }
            target.replace("tbl",with:try MarkupNode.fragment(PPTXXML.table(t,relationship:{ try self.linkID($0,rels:rels,strict:strict) }),strict:strict)); warning(path,"tbl","表を再構成しました。未対応のセル書式は引き継ぎません",feature:"TBL-001",elementID:e.id)
        }
        if e.children != o.children { guard e.kind == .group else { throw SlideError.invalidModel("グループ以外にchildrenを指定できません") }; try patchElements(e.children,original:o.children,parent:node,path:path,rels:rels,strict:strict,ids:&ids) }
    }

    /// 同じ行列の局所編集ではセル書式と拡張を保持する。行列を作り直す際は投影を黙って捨てない。
    func patchTable(_ table: Table, original: Table, node: MarkupNode, path: String, rels: MarkupNode, strict: Bool) throws -> Bool {
        guard table.rows.count == original.rows.count, table.columnWidths.count == original.columnWidths.count,
              table.rows.indices.allSatisfy({ table.rows[$0].count == original.rows[$0].count }) else { return false }
        let rowNodes = node.named("tr"), columns = node.child("tblGrid")?.named("gridCol") ?? []
        guard rowNodes.count == table.rows.count, columns.count == table.columnWidths.count else { throw SlideError.unsafeEdit("表の原本行列との対応が不明です") }
        for i in columns.indices where table.columnWidths[i] != original.columnWidths[i] { columns[i].set("w",PPTXXML.emu(table.columnWidths[i])) }
        for i in table.rows.indices {
            if table.rowHeights[i] != original.rowHeights[i] { rowNodes[i].set("h",PPTXXML.emu(table.rowHeights[i])) }
            let cells = rowNodes[i].named("tc")
            guard cells.count == table.rows[i].count else { throw SlideError.unsafeEdit("表セルと原本の対応が不明です") }
            for j in table.rows[i].indices {
                let cell = table.rows[i][j], before = original.rows[i][j], source = cells[j]
                guard cell.nativeProperties == before.nativeProperties, cell.borders == before.borders, cell.value == before.value, cell.formula == before.formula, cell.nativeFormula == before.nativeFormula else { throw SlideError.unsafeEdit("個別罫線・型付きセル値・式の投影を変更できません") }
                if cell.text != before.text {
                    guard !containsEquationSource(source.child("txBody")) else { throw SlideError.unsafeEdit("数式を含むセルの再構成は未対応です") }
                    source.replace("txBody",with:try MarkupNode.fragment(PPTXXML.text(cell.text,p:false,relationship:{ try self.linkID($0,rels:rels,strict:strict) }),strict:strict))
                    warning(path,"txBody","表セルの文字領域を再構成しました",feature:"TXT-002")
                }
                if cell.fill != before.fill || cell.border != before.border || cell.insets != before.insets {
                    let properties: MarkupNode
                    if let existing = source.child("tcPr") { properties = existing }
                    else { properties = try MarkupNode.fragment("<a:tcPr/>",strict:strict); source.replace("tcPr",with:properties) }
                    if cell.fill != before.fill {
                        guard !isReadOnlyFill(cell.fill), !isReadOnlyFill(before.fill) else { throw SlideError.unsafeEdit("追加のセル塗りを変更できません") }
                        properties.remove(["noFill","solidFill","gradFill","blipFill","pattFill","grpFill"])
                        if let fill = cell.fill { properties.content.append(.node(try MarkupNode.fragment(PPTXXML.fill(fill),strict:strict))) }
                    }
                    if cell.border != before.border {
                        for name in ["lnL","lnR","lnT","lnB"] { properties.replace(name,with:try cell.border.map { try MarkupNode.fragment(PPTXXML.line($0,tag:name),strict:strict) }) }
                    }
                    if cell.insets != before.insets {
                        for (key,value) in [("marL",cell.insets?.left),("marR",cell.insets?.right),("marT",cell.insets?.top),("marB",cell.insets?.bottom)] { properties.set(key,value.map(PPTXXML.emu)) }
                    }
                    let order = ["lnL","lnR","lnT","lnB","lnTlToBr","lnBlToTr","cell3D","noFill","solidFill","gradFill","blipFill","pattFill","grpFill","headers","extLst"]
                    properties.content = properties.content.enumerated().sorted { a,b in
                        func rank(_ value: MarkupNode.Content) -> Int { if case .node(let n) = value { return order.firstIndex(of:n.name) ?? order.count }; return order.count }
                        let l = rank(a.element), r = rank(b.element); return l == r ? a.offset < b.offset : l < r
                    }.map(\.element)
                    warning(path,"tcPr","表セルの指定書式を変更しました",feature:"TBL-001")
                }
            }
        }
        if table.styleID != original.styleID {
            let pr: MarkupNode
            if let existing = node.child("tblPr") { pr = existing }
            else { pr = try MarkupNode.fragment("<a:tblPr/>",strict:strict); node.replace("tblPr",with:pr,first:true) }
            pr.replace("tableStyleId",with:try table.styleID.map { try MarkupNode.fragment("<a:tableStyleId>\(escapeXML($0))</a:tableStyleId>",strict:strict) })
        }
        return true
    }

    func isReadOnlyFill(_ fill: Fill?) -> Bool {
        switch fill { case .gradient, .pattern, .picture: true; default: false }
    }
}
