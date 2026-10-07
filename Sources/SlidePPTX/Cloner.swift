import Foundation
import SlideCore

enum PPTXCloner {
    static let cloneRelationships: Set<String> = ["slide", "slideLayout", "slideMaster", "notesSlide", "notesMaster", "theme", "image", "chart", "package", "hyperlink", "audio", "video"]
    static let shareRelationships: Set<String> = ["slideLayout", "slideMaster", "notesMaster", "theme", "image", "audio", "video"]
    static func fragment(_ target: String) -> String { target.firstIndex(of: "#").map { String(target[$0...]) } ?? "" }

    static func importSlide(id: String, source: Presentation, destination: inout Presentation, index: Int?,
                            options: SlideImportOptions, duplicate: Bool, format: PresentationFormat) throws -> String {
        try Task.checkCancellation()
        try source.validateIdentities()
        let insertion = index ?? destination.slides.count
        guard (0...destination.slides.count).contains(insertion) else { throw SlideError.invalidModel("取り込みの挿入位置が不正です") }
        guard let sourceIndex = source.slides.firstIndex(where: { $0.id == id }) else { throw SlideError.slideNotFound(id: id) }
        guard source.size == destination.size else { throw SlideError.unsafeEdit("異なるスライド寸法の取り込みは未対応です") }
        guard duplicate || (source.sourceFormat ?? .pptx) == .pptx && format == .pptx else {
            throw SlideError.unsafeEdit("別文書の取り込みはPPTX同士に限ります")
        }
        guard destination.storage?.archive.paths.contains(where: { $0.hasPrefix("_xmlsignatures/") }) != true,
              source.storage?.archive.paths.contains(where: { $0.hasPrefix("_xmlsignatures/") }) != true else {
            throw SlideError.unsafeEdit("署名付き文書のスライド取り込みは未対応です")
        }
        for (from, to) in options.slideLinks {
            guard source.slides.contains(where: { $0.id == from }), destination.slides.contains(where: { $0.id == to }), from != id else {
                throw SlideError.invalidModel("スライドリンク対応表の対象が不正です")
            }
        }
        let sourceFormat = source.sourceFormat ?? .pptx
        let encoded = try PPTXWriter(source, format: sourceFormat, options: .init()).write()
        let snapshot = try PPTXCodec(macroEnabled: sourceFormat == .pptm).read(encoded.data,
            options: .init(limits: source.storage?.limits ?? .init(), includeNotes: source.storage?.notesOmitted != true)).presentation
        guard let storage = snapshot.storage, let sourcePart = storage.slidePaths[snapshot.slides[sourceIndex].id] else {
            throw SlideError.unsafeEdit("取り込み原本のスライドがありません")
        }
        let package = try OPCPackage(encoded.data, limits: storage.limits)
        let root = try MarkupNode.parse(package.archive.read(sourcePart), part: sourcePart, limits: storage.limits)
        let destinationStrict: Bool
        if let target = destination.storage {
            destinationStrict = try MarkupNode.parse(target.archive.read(target.mainPart), part: target.mainPart, limits: target.limits).namespace == NS.strictP
        } else { destinationStrict = false }
        guard (root.namespace == NS.strictP) == destinationStrict else { throw SlideError.unsafeEdit("OOXMLプロファイルが異なる取り込みは未対応です") }

        let graph = try PPTXInventory.build(storage), newID = UUID().uuidString
        let fingerprint = try Fingerprint.hash(encoded.data)
        let sourceSlides = Dictionary(uniqueKeysWithValues: snapshot.slides.enumerated().map { (storage.slidePaths[$0.element.id]!, source.slides[$0.offset].id) })
        var slideTargets = options.slideLinks
        if duplicate { for slide in source.slides { slideTargets[slide.id] = slide.id } }
        slideTargets[id] = newID
        let sameOriginal = destination.storage?.data == source.storage?.data && destination.storage != nil
        let activeClones = destination.slideClones.filter { key, _ in destination.slides.contains { $0.id == key } }
        var origins: [String: String] = [:]
        for clone in activeClones.values { origins.merge(clone.origins, uniquingKeysWith: { first, _ in first }) }
        let existingCloneParts = Set(activeClones.values.flatMap { $0.parts.keys })
        var mapping: [String: String] = [:], copied: Set<String> = [], links: [CloneSlideLink] = [], serial = 0
        func allocate(_ part: String) -> String {
            serial += 1
            let directory = (part as NSString).deletingLastPathComponent
            let ext = (part as NSString).pathExtension
            return (directory.isEmpty ? "" : directory + "/") + "ssclone-\(newID.lowercased())-\(serial)" + (ext.isEmpty ? "" : "." + ext)
        }
        var notesMasters = Set<String>()
        if let target = destination.storage {
            let targetPackage = try OPCPackage(target.data, limits: target.limits)
            for rel in try targetPackage.relationships(from: target.mainPart).values where rel.type == "notesMaster" {
                if let path = rel.path { notesMasters.insert(path) }
            }
        }
        for clone in activeClones.values {
            notesMasters.formUnion(clone.contentTypes.filter { $0.value.hasSuffix("notesMaster+xml") }.keys)
        }
        func visit(_ part: String, via type: String) throws {
            try Task.checkCancellation()
            if mapping[part] != nil { return }
            let origin = fingerprint + ":" + part
            if shareRelationships.contains(type) {
                if sameOriginal && destination.storage?.archive.entries[part] != nil || duplicate && existingCloneParts.contains(part) {
                    mapping[part] = part; return
                }
                if duplicate && destination.storage == nil && ["ppt/slideLayouts/slideLayout1.xml", "ppt/slideMasters/slideMaster1.xml", "ppt/theme/theme1.xml"].contains(part) {
                    mapping[part] = part; return
                }
                if let existing = origins[origin] { mapping[part] = existing; return }
            }
            if type == "notesMaster", !notesMasters.isEmpty { throw SlideError.unsafeEdit("別のノートmasterが存在し、書式の整合を確認できません") }
            if let scope = graph.unresolvedScopes.first(where: { $0.part == part }) {
                throw SlideError.unsafeEdit("未知参照を含むパーツは取り込めません: \(scope.part) \(scope.path)")
            }
            if let unknown = graph.references.first(where: { $0.sourcePart == part && $0.knowledge == .unknown }) {
                throw SlideError.unsafeEdit("未知の参照は取り込めません: \(unknown.location.path)")
            }
            mapping[part] = allocate(part); copied.insert(part)
            if shareRelationships.contains(type) { origins[origin] = mapping[part]! }
            if type == "notesMaster" { notesMasters.insert(mapping[part]!) }
            for rel in try package.relationships(from: part).values.sorted(by: { $0.id < $1.id }) {
                guard cloneRelationships.contains(rel.type) else { throw SlideError.unsafeEdit("取り込み未対応のrelationship: \(rel.type)") }
                if rel.isExternal {
                    guard rel.type == "hyperlink" else { throw SlideError.unsafeEdit("外部資源の取り込みは未対応です") }
                    continue
                }
                guard let target = rel.path else { continue }
                if rel.type == "slide" {
                    guard let originalID = sourceSlides[target], let targetID = slideTargets[originalID] else {
                        throw SlideError.unsafeEdit("別スライドへのリンクには明示的な対応表が必要です")
                    }
                    links.append(.init(part: mapping[part]!, relationshipID: rel.id, slideID: targetID, fragment: fragment(rel.target)))
                } else { try visit(target, via: rel.type) }
            }
        }
        try visit(sourcePart, via: "slide")
        // Custom table styles are presentation-wide and cannot be copied as a slide-local dependency.
        if !duplicate && !sameOriginal, let styles = try package.relationships(from: package.mainPart).values.first(where: { $0.type == "tableStyles" })?.path {
            let tree = try MarkupNode.parse(package.archive.read(styles), part: styles, limits: storage.limits)
            if !tree.children.isEmpty { throw SlideError.unsafeEdit("独自table styleの取り込みは未対応です") }
        }
        var renewedFields: [String: [String: String]] = [:]
        var data: [String: Data] = [:], types: [String: String] = [:]
        for part in copied.sorted() {
            let target = mapping[part]!
            var partData = try package.archive.read(part)
            if part.hasSuffix(".xml") || package.type(of: part)?.hasSuffix("+xml") == true {
                let tree = try MarkupNode.parse(partData, part: part, limits: storage.limits)
                var changed = false
                func renewMetadata(_ node: MarkupNode) {
                    if PPTXInventory.metadataID(node) { node.set("val", String(UInt32.random(in: 0...UInt32.max))); changed = true }
                    if node.isA && node.name == "fld", let id = node.attr("id") { let new = "{" + UUID().uuidString + "}"; renewedFields[part,default:[:]][id] = new; node.set("id",new); changed = true }
                    for child in node.children { renewMetadata(child) }
                }
                renewMetadata(tree)
                if changed { partData = Data(tree.xml.utf8) }
            }
            data[target] = partData
            guard let contentType = package.type(of: part) else { throw SlideError.corruptedPackage("取り込みpartのContent-Typeがありません: \(part)") }
            types[target] = contentType
            let relPart = OPCPackage.relationshipPart(for: part)
            if package.archive.entries[relPart] != nil {
                let relRoot = try MarkupNode.parse(package.archive.read(relPart), part: relPart, limits: storage.limits)
                let rels = try package.relationships(from: part)
                for node in relRoot.children {
                    guard let relID = node.attr("Id"), let rel = rels[relID], !rel.isExternal else { continue }
                    if rel.type == "slide" { node.set("Target", OPCPackage.uri(for: "/" + mapping[sourcePart]!) + fragment(rel.target)) }
                    else if let path = rel.path, let mapped = mapping[path] { node.set("Target", OPCPackage.uri(for: "/" + mapped) + fragment(rel.target)) }
                    else { throw SlideError.unsafeEdit("取り込み参照の対応がありません") }
                }
                data[OPCPackage.relationshipPart(for: target)] = Data(relRoot.xml.utf8)
            }
        }
        var slide = snapshot.slides[sourceIndex]; slide.id = newID
        slide.layoutPath = slide.layoutPath.flatMap { mapping[$0] }
        slide.themeOverridePath = slide.themeOverridePath.map { mapping[$0] ?? $0 }
        func rebase(_ body: inout TextBody, part: String) throws {
            for p in body.paragraphs.indices {
                for r in body.paragraphs[p].runs.indices {
                    if let id = body.paragraphs[p].runs[r].field?.id, let renewed = renewedFields[part]?[id] { body.paragraphs[p].runs[r].field?.id = renewed }
                    if case .slide(let part) = body.paragraphs[p].runs[r].link {
                        guard let originalID = sourceSlides[part], let target = slideTargets[originalID] else { throw SlideError.unsafeEdit("モデルのリンク対応がありません") }
                        body.paragraphs[p].runs[r].link = .slide(target)
                    }
                }
            }
        }
        func rebaseReference(_ reference: inout PartReference?) { if let path = reference?.path { reference?.path = mapping[path] ?? path } }
        func rebaseElements(_ elements: inout [Element], part: String) throws {
            for i in elements.indices {
                if let path = elements[i].image?.path { elements[i].image?.path = mapping[path] ?? path }
                if var text = elements[i].text { try rebase(&text,part:part); elements[i].text = text }
                if var table = elements[i].table {
                    for row in table.rows.indices { for col in table.rows[row].indices { try rebase(&table.rows[row][col].text,part:part) } }
                    elements[i].table = table
                }
                if var chart = elements[i].chart {
                    if let path = chart.part.path { chart.part.path = mapping[path] ?? path }
                    rebaseReference(&chart.externalData); elements[i].chart = chart
                }
                if var diagram = elements[i].diagram {
                    let drawingPart = diagram.drawing?.path ?? part
                    rebaseReference(&diagram.data); rebaseReference(&diagram.layout); rebaseReference(&diagram.quickStyle)
                    rebaseReference(&diagram.colors); rebaseReference(&diagram.drawing)
                    try rebaseElements(&diagram.elements,part:drawingPart); elements[i].diagram = diagram
                }
                try rebaseElements(&elements[i].children,part:part)
            }
        }
        try rebaseElements(&slide.elements,part:sourcePart)
        if var notes = slide.notes { try rebase(&notes,part:storage.notesPaths[snapshot.slides[sourceIndex].id] ?? sourcePart); slide.notes = notes }
        func location(_ value: ReferenceLocation) -> ReferenceLocation {
            let part: String
            if let source = PPTXInventory.relationshipSource(value.part), let mapped = mapping[source] { part = OPCPackage.relationshipPart(for: mapped) }
            else { part = mapping[value.part] ?? value.part }
            return .init(part: part, path: value.path, attribute: value.attribute,
                  slideID: value.part == sourcePart ? newID : value.slideID, elementID: value.elementID)
        }
        let cloneGraph = PackageGraph(references: graph.references.filter { copied.contains($0.sourcePart) }.map {
            .init(kind: $0.kind, knowledge: $0.knowledge, location: location($0.location), value: $0.value,
                  sourcePart: mapping[$0.sourcePart] ?? $0.sourcePart,
                  relationshipType: $0.relationshipType, targetPart: $0.targetPart.map { mapping[$0] ?? $0 },
                  targetElementID: $0.targetElementID, isExternal: $0.isExternal)
        }, unresolvedScopes: graph.unresolvedScopes.filter { copied.contains($0.part) }.map(location))
        let clone = SlideClone(baseline: slide, slidePath: mapping[sourcePart]!,
            notesPath: storage.notesPaths[snapshot.slides[sourceIndex].id].flatMap { mapping[$0] }, notesOmitted: storage.notesOmitted,
            parts: data, contentTypes: types, links: links, graph: cloneGraph, origins: origins)
        var candidate = destination
        candidate.slides.insert(slide, at: insertion); candidate.slideClones[newID] = clone
        _ = try PPTXWriter(candidate, format: format, options: .init()).write()
        try Task.checkCancellation()
        destination = candidate; return newID
    }
}
