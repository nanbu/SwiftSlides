import Foundation
import SlideCore

package struct KeynoteCodec: SlideReadingCodec {
    package let format = PresentationFormat.keynote
    package init() {}
    package var capabilities: CodecCapabilities { .init(format:.keynote,operations:[.inspect:.partial,.read:.partial,.create:.unsupported,.edit:.unsupported,.preserve:.unsupported,.convert:.unsupported,.render:.unsupported,.play:.unsupported],notes:"確認したIWA構造の基本要素・文字run/style・v5表セル・chart grid・build/transition。未知objectと未解釈属性はwire索引で取得。保存は提供しません",features:KeynoteFeatureCapabilities.features(for:.keynote)) }
    package func inspectObjects(_ data: Data, limits: PackageLimits = .init()) throws -> KeynoteInventory { try KeynoteSource(data,options:.init(limits:limits)).inventory }
    package func inspect(_ data: Data, options: InspectOptions = .init()) throws -> PresentationSummary { try KeynoteSource(data,options:.init(limits:options.limits)).summary }
    package func openSlides(_ data: Data, options: ReadOptions) throws -> any PresentationSlideSource { try KeynoteSource(data,options:options) }
    package func read(_ data: Data, options: ReadOptions) throws -> ReadResult {
        let source=try KeynoteSource(data,options:options)
        var slides:[Slide]=[],warnings=source.warnings,totalText=0,totalCells=0
        for index in source.slideDescriptors.indices {
            let result=try source.slide(at:index),count=result.slide.plainText.utf8.count+(result.slide.notes?.plainText.utf8.count ?? 0)
            guard count <= options.limits.maxExpandedBytes-totalText else { throw SlideError.limitExceeded("Keynote全文字の展開量") };totalText += count
            func cells(_ elements:[Element]) -> Int { elements.reduce(0) { $0+($1.table?.rows.reduce(0) { $0+$1.count } ?? 0)+cells($1.children) } }
            let cellCount=cells(result.slide.elements)
            guard cellCount <= options.limits.maxTableCells-totalCells else { throw SlideError.limitExceeded("Keynote全表のセル展開量") };totalCells += cellCount
            slides.append(result.slide);warnings += result.warnings
        }
        var p=Presentation(size:source.summary.size,slides:slides)
        p.preserve(.init(data:source.data,archive:source.archive,mainPart:"Index/Document.iwa",limits:options.limits,originalSize:p.size,originalSlides:slides,originalMetadata:p.metadata,originalTheme:p.theme,slidePaths:Dictionary(uniqueKeysWithValues:source.slideIDs.map { (String($0),source.index.byID[$0]![0].part) }),notesPaths:[:],notesOmitted:!options.includesNotes),format:.keynote,warnings:warnings,parts:source.summary.parts,themes:[])
        return .init(presentation:p)
    }
    package func write(_ presentation: Presentation, options: WriteOptions) throws -> WriteResult { throw SlideError.unsafeEdit("Keynote codecは読取専用です") }
}
extension Codec { public static let keynote = Codec(KeynoteCodec()) }
extension Presentation {
    public func readKeynoteObjects() throws -> KeynoteInventory {
        guard sourceFormat == .keynote, let storage else { throw SlideError.unsupportedContainer("Keynote原本なし") }
        return try KeynoteCodec().inspectObjects(storage.data,limits:storage.limits)
    }
    @concurrent public func readKeynoteObjects() async throws -> KeynoteInventory { try keynoteObjectsSync() }
    private func keynoteObjectsSync() throws -> KeynoteInventory { try readKeynoteObjects() }
}
struct KeynoteSource: PresentationSlideSource {
    var cacheStatistics: ReadingCacheStatistics? { archive.cacheStatistics.adding(index.cacheStatistics) }
    let data: Data, archive: PackageArchive, options: ReadOptions, index: KeynoteObjectIndex, slideIDs: [UInt64], hidden: [UInt64:Bool], summary: PresentationSummary
    let dataReferences: [KeynoteDataReference], warnings: [SlideWarning]
    var inventory: KeynoteInventory { get throws { try .init(objects:index.locations.map { try index.object($0) },dataReferences:dataReferences,warnings:warnings) } }
    let assets: [UInt64:String]
    var slideDescriptors: [SlideDescriptor] { slideIDs.enumerated().map { .init(id:String($0.element),index:$0.offset) } }
    init(_ input: Data, options: ReadOptions, archive supplied: PackageArchive? = nil) throws {
        guard options.limits.maxTableCells >= 0,options.limits.maxXMLNodes > 0,options.limits.maxXMLDepth > 0 else { throw SlideError.limitExceeded("Keynote読取予算不正") }
        self.options=options
        let snapshot = input
        var archive=try supplied ?? PackageArchive(input,limits:options.limits)
        if archive.paths.contains(where: { $0 == ".iwpv2" || $0.hasSuffix("/.iwpv2") || $0 == ".iwph" || $0.hasSuffix("/.iwph") }) { throw SlideError.unsupportedEncryption(detail: "Keynote .iwpv2保護") }
        if archive.entries["Index/Document.iwa"] == nil, archive.entries["Index.zip"] != nil {
            let nested=try PackageArchive(archive.read("Index.zip"),limits:options.limits)
            archive = try PackageArchive(outer: archive, nested: nested, excluding: "Index.zip", prefix: "Index/", limits: options.limits)
        }
        guard archive.entries["Index/Document.iwa"] != nil else { throw SlideError.unknownFormat }
        let index = try KeynoteObjectIndex(archive:archive,options:options)
        let objects = index.locations
        func object(_ id: UInt64, _ type: UInt32) throws -> KeynoteObject {
            let value = try index.object(id)
            guard value.type == type else { throw SlideError.corruptedPackage("Keynote object参照/type不整合: \(id)") }; return value
        }
        func child(_ fields:[KeynoteField],_ n:UInt32) throws -> [KeynoteField] { try Wire.fields(Self.bytes(fields,n),limit:options.limits.maxXMLNodes) }
        func ref(_ fields:[KeynoteField],_ n:UInt32) throws -> UInt64 { try Wire.scalar(child(fields,n),1) }
        let docs=objects.filter { $0.type == 1 && $0.part == "Index/Document.iwa" }
        guard docs.count == 1 else { throw SlideError.unknownFormat }
        let show=try object(ref(index.object(docs[0]).fields,2),2),sizeFields=try child(show.fields,4)
        let size=try Size(width:Self.float(sizeFields,1),height:Self.float(sizeFields,2))
        guard size.width > 0, size.height > 0 else { throw SlideError.corruptedPackage("Keynote slide寸法不正") }
        let tree=try child(show.fields,3);var ids:[UInt64]=[],states:[UInt64:Bool]=[:],seen=Set<UInt64>()
        func walk(_ id: UInt64, depth: Int) throws {
            try Task.checkCancellation()
            guard depth < options.limits.maxXMLDepth, seen.insert(id).inserted else { throw SlideError.corruptedPackage("Keynote slideTree循環/深さ超過") }
            let node=try object(id,4)
            if node.fields.contains(where:{ $0.number == 2 }) { let sid=try ref(node.fields,2);_ = try object(sid,5);guard states[sid] == nil else { throw SlideError.corruptedPackage("Keynote slide重複") };ids.append(sid);states[sid]=try Self.optionalInteger(node.fields,4).map { $0 != 0 } ?? false }
            for f in node.fields where f.number == 1 { try walk(Wire.scalar(Wire.fields(f.bytes ?? Data(),limit:options.limits.maxXMLNodes),1),depth:depth+1) }
        }
        let treeRefs=tree.filter { $0.number == 2 }
        if treeRefs.isEmpty, tree.contains(where:{ $0.number == 1 }) { try walk(ref(tree,1),depth:0) }
        else { for f in treeRefs { try walk(Wire.scalar(Wire.fields(f.bytes ?? Data(),limit:options.limits.maxXMLNodes),1),depth:0) } }
        var assets:[UInt64:String]=[:],dataReferences:[KeynoteDataReference]=[],dataIDs=Set<UInt64>()
        for location in objects where location.type == 11006 {
            let meta = try index.object(location)
            for field in meta.fields where field.number == 4 {
                let f=try Wire.fields(field.bytes ?? Data(),limit:options.limits.maxXMLNodes),id=try Wire.scalar(f,1)
                guard dataIDs.insert(id).inserted else { throw SlideError.corruptedPackage("Keynote data identity重複") }
                let filename=try Self.string(f,4) ?? Self.string(f,3)
                if let filename {
                    let path=filename.hasPrefix("Data/") ? filename : "Data/"+filename
                    guard !path.split(separator:"/").contains(".."), !path.hasPrefix("/"), !path.contains(":"), !path.contains("\\") else { throw SlideError.corruptedPackage("Keynote dataパス不正") }
                    if archive.entries[path] != nil { guard assets[id] == nil || assets[id] == path else { throw SlideError.corruptedPackage("Keynote data identity重複") };assets[id]=path }
                }
                dataReferences.append(try .init(id:id,path:assets[id],remoteURL:Self.string(f,7),fields:f,rawData:field.bytes ?? Data()))
            }
        }
        var warnings:[SlideWarning]=[.init(code:.unsupportedContent,part:"Index/Document.iwa",element:"IWA",message:"Keynoteの未解釈書式・式tokenの追加属性・固有build・未知objectをwire索引に保持します。全機能の意味解釈・外観は未検証")]
        for object in objects {
            let missing=object.objectReferences.filter { index.byID[$0] == nil }
            if !missing.isEmpty { warnings.append(.init(code:.unsupportedContent,part:object.part,element:"object \(object.id)",message:"未知object参照が未解決: \(missing)")) }
            let missingData=object.dataReferences.filter { assets[$0] == nil }
            if !missingData.isEmpty { warnings.append(.init(code:.unsupportedContent,part:object.part,element:"object \(object.id)",message:"data参照のパーツが未解決: \(missingData)")) }
        }
        for data in dataReferences where data.path == nil { warnings.append(.init(code:.unsupportedContent,part:"Index/Metadata.iwa",element:"data \(data.id)",message:"dataのパーツは未解決です。remoteURLとmetadataを保持し、外部取得はしません")) }
        self.data=snapshot;self.archive=archive;self.dataReferences=dataReferences;self.warnings=warnings;self.index=index;slideIDs=ids;hidden=states;self.assets=assets
        summary = .init(format:.keynote,size:size,slideCount:ids.count,metadata:.init(),parts:archive.paths.filter { !$0.hasSuffix("/") }.map { let e=archive.entries[$0]!;return .init(path:$0,contentType:nil,compressedSize:e.compressedSize,expandedSize:e.expandedSize) })
    }
    static func bytes(_ fields:[KeynoteField],_ n:UInt32) throws -> Data {
        let f=fields.filter { $0.number == n };guard f.count == 1, f[0].wireType == 2, let b=f[0].bytes else { throw SlideError.corruptedPackage("Keynote必須message \(n)不正") };return b
    }
    static func optionalInteger(_ fields:[KeynoteField],_ n:UInt32) throws -> UInt64? {
        guard fields.contains(where:{ $0.number == n }) else { return nil };return try Wire.scalar(fields,n)
    }
    static func float(_ fields:[KeynoteField],_ n:UInt32) throws -> Double {
        let f=fields.filter { $0.number == n };guard f.count == 1, f[0].wireType == 5, let b=f[0].bytes, b.count == 4 else { throw SlideError.corruptedPackage("Keynote float不正") }
        let value=Double(Float(bitPattern:b.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8*$1.offset) }));guard value.isFinite else { throw SlideError.corruptedPackage("Keynote非有限数") };return value
    }
    static func string(_ fields:[KeynoteField],_ n:UInt32) throws -> String? {
        let f=fields.filter { $0.number == n };guard !f.isEmpty else { return nil };guard f.count == 1, f[0].wireType == 2, let b=f[0].bytes, let s=String(data:b,encoding:.utf8) else { throw SlideError.corruptedPackage("Keynote文字列不正") };return s
    }
    func object(_ id:UInt64) throws -> KeynoteObject { try index.object(id) }
    func fields(_ bytes:Data) throws -> [KeynoteField] { try Wire.fields(bytes,limit:options.limits.maxXMLNodes) }
    func ref(_ fields:[KeynoteField],_ n:UInt32) throws -> UInt64 { try Wire.scalar(self.fields(Self.bytes(fields,n)),1) }
    func text(_ id:UInt64, budget:inout Int) throws -> TextBody {
        let o=try object(id);guard o.type == 2001 else { throw SlideError.corruptedPackage("Keynote text storage型不正") }
        var strings=""
        for f in o.fields where f.number == 3 {
            try Task.checkCancellation()
            guard let b=f.bytes,let s=String(data:b,encoding:.utf8) else { throw SlideError.corruptedPackage("Keynote text UTF8不正") }
            guard b.count <= options.limits.maxPartBytes-budget else { throw SlideError.limitExceeded("Keynote slide文字の展開量") };budget += b.count;strings += s
        }
        return try attributedText(strings,storage:o)
    }
    func slide(at index:Int) throws -> SlideReadResult {
        guard slideIDs.indices.contains(index) else { throw SlideError.invalidModel("Keynote slide index範囲外") }
        let id=slideIDs[index],o=try object(id);var ids=Set<UInt64>(),warnings:[SlideWarning]=[],textBudget=0,cellBudget=0
        func element(_ id:UInt64,depth:Int) throws -> Element {
            try Task.checkCancellation()
            guard depth < options.limits.maxXMLDepth,ids.insert(id).inserted else { throw SlideError.corruptedPackage("Keynote drawable循環/重複") }
            let object=try object(id);var f=object.fields
            var e=Element(id:String(id),kind:.opaque,geometry:nil);e.nativeObjectID=id
            let placeholder=[7,12].contains(object.type)
            if placeholder { f=try fields(Self.bytes(f,1));e.placeholder = .init(kind:String(try Self.optionalInteger(object.fields,2) ?? 0)) }
            if [2011,3004,3009].contains(object.type) || placeholder {
                if object.type == 2011 || placeholder {
                    if f.contains(where:{ $0.number == 4 }) { e.text=try text(ref(f,4),budget:&textBudget) }
                    else if f.contains(where:{ $0.number == 2 }) { e.text=try text(ref(f,2),budget:&textBudget) }
                    e.isTextBox=(try Self.optionalInteger(f,6)) == 1
                    f=try fields(Self.bytes(f,1))
                } else if object.type == 3009 { f=try fields(Self.bytes(f,1)) }
                e.kind = object.type == 3009 ? .connector : .shape
                if f.contains(where:{ $0.number == 2 }) { try shapeStyle(ref(f,2),element:&e) }
                if let path=try child(f,3) {
                    e.isFlippedHorizontally=(try Self.optionalInteger(path,1)) == 1;e.isFlippedVertically=(try Self.optionalInteger(path,2)) == 1
                    e.customGeometry=try nativeGeometry(path); e.nativeGeometry=try parameterizedGeometry(path)
                }
                f=try fields(Self.bytes(f,1))
            } else if object.type == 6000 {
                do { e.table=try nativeTable(object,budget:&textBudget,cellBudget:&cellBudget);e.kind = .table }
                catch SlideError.unsupportedContainer(let message) { warnings.append(.init(code:.unsupportedContent,part:object.part,element:"table",message:message,slideID:String(o.id),elementID:String(id))) }
                f=try fields(Self.bytes(f,1))
            } else if object.type == 5021 {
                e.chart=try nativeChart(object);f=try fields(Self.bytes(f,1))
            } else if [3005,3007,3008].contains(object.type) {
                if object.type == 3008 { e.kind = .group;e.children=try object.fields.filter { $0.number == 2 }.map { try element(Wire.scalar(fields($0.bytes ?? Data()),1),depth:depth+1) } }
                if object.type == 3005,object.fields.contains(where:{ $0.number == 11 }),let path=assets[try ref(object.fields,11)] { e.kind = .image;e.image = .init(path:path) }
                if object.type == 3007 {
                    let dataID=object.fields.contains(where:{ $0.number == 14 }) ? try ref(object.fields,14) : nil
                    let remote=try Self.string(object.fields,17),kind:MediaReference.Kind=(try Self.optionalInteger(object.fields,9)) == 1 ? .audio : .video
                    if dataID != nil || remote != nil { e.media=[.init(kind:kind,reference:.init(relationshipID:dataID.map(String.init) ?? String(id),path:dataID.flatMap { assets[$0] },externalTarget:remote))] }
                }
                f=try fields(Self.bytes(f,1))
            } else { warnings.append(.init(code:.unsupportedContent,part:object.part,element:"type \(object.type)",message:"未知drawableをobject索引に保持します",slideID:String(o.id),elementID:String(id)));return e }
            if f.contains(where:{ $0.number == 1 }) {
                let g=try fields(Self.bytes(f,1))
                if g.contains(where:{ $0.number == 1 }),g.contains(where:{ $0.number == 2 }) {
                    let p=try fields(Self.bytes(g,1)),s=try fields(Self.bytes(g,2));let width=try Self.float(s,1),height=try Self.float(s,2)
                    guard width >= 0,height >= 0 else { throw SlideError.corruptedPackage("Keynote負の図形寸法") }
                    e.frame=try .init(x:Self.float(p,1),y:Self.float(p,2),width:width,height:height)
                }
                if g.contains(where:{ $0.number == 4 }) { e.rotation=try Self.float(g,4)*180 / .pi }
            }
            if e.image != nil { e.image?.alternativeText=try Self.string(f,8) ?? "" }
            warnings.append(.init(code:.uninterpretedFormatting,part:object.part,element:"drawable",message:"Keynote固有書式・geometry・refはobject索引で取得できます",slideID:String(o.id),elementID:String(id)))
            return e
        }
        let order=o.fields.contains(where:{ $0.number == 42 }) ? UInt32(42) : 7
        var slide=Slide(id:String(id),name:try Self.string(o.fields,10) ?? "",elements:try o.fields.filter { $0.number == order }.map { try element(Wire.scalar(fields($0.bytes ?? Data()),1),depth:0) })
        slide.isHidden=hidden[id] ?? false
        try nativeTime(o,slide:&slide)
        if o.fields.contains(where:{ $0.number == 27 }) {
            if options.includesNotes { let note=try object(ref(o.fields,27));guard note.type == 15 else { throw SlideError.corruptedPackage("Keynote note型不正") };slide.notes=try text(ref(note.fields,1),budget:&textBudget) }
            else { warnings.append(.init(code:.notesOmitted,part:o.part,element:"note",message:"Keynoteノート読取を省略しました",slideID:String(id))) }
        }
        return .init(slide:slide,warnings:warnings)
    }
    func asset(at path:String) throws -> Data { try archive.read(path) }
}


extension KeynoteCodec: FileSlideReadingCodec {
    package func openSlides(contentsOf url: URL, options: ReadOptions, cacheBytes: Int) throws -> any PresentationSlideSource {
        try KeynoteSource(Data(), options: options, archive: PackageArchive(contentsOf: url, limits: options.limits, cacheBytes: cacheBytes))
    }
}
