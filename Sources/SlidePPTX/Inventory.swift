import Foundation
import SlideCore

enum PPTXInventory {
    static let knownRelationships: Set<String> = ["officeDocument", "core-properties", "extended-properties", "custom-properties",
        "slide", "slideLayout", "slideMaster", "notesSlide", "notesMaster", "theme", "image", "hyperlink", "chart", "package",
        "audio", "video", "media", "tableStyles", "presProps", "viewProps", "vbaProject", "handoutMaster"]
    static let chartNamespaces: Set<String> = ["http://schemas.openxmlformats.org/drawingml/2006/chart", "http://purl.oclc.org/ooxml/drawingml/chart"]
    static func relationshipSource(_ path: String) -> String? {
        if path == "_rels/.rels" { return "" }
        let segments = path.split(separator: "/").map(String.init)
        guard segments.count >= 2, segments[segments.count - 2] == "_rels", let last = segments.last, last.hasSuffix(".rels") else { return nil }
        return (Array(segments.dropLast(2)) + [String(last.dropLast(5))]).joined(separator: "/")
    }
    static func knownNamespace(_ uri: String) -> Bool {
        [NS.p, NS.strictP, NS.a, NS.strictA, NS.core, NS.dc, NS.types, NS.rels,
         "http://purl.org/dc/terms/", "http://www.w3.org/2001/XMLSchema-instance",
         "http://schemas.openxmlformats.org/officeDocument/2006/extended-properties",
         "http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"].contains(uri) || chartNamespaces.contains(uri)
    }
    // MS-PPTX 2.3.1.4 / 2.3.3.21: random creation metadata, not a shape/slide reference.
    static func metadataID(_ node: MarkupNode) -> Bool {
        node.namespace == "http://schemas.microsoft.com/office/powerpoint/2010/main" && ["creationId", "modId"].contains(node.name)
            && node.children.isEmpty && Set(node.attributes.keys) == ["val"] && node.attr("val").flatMap(UInt32.init) != nil
    }
    // MS-PPTX 2.3.1.5/6: scalar image-saving settings with no document references.
    static func imageSetting(_ node: MarkupNode) -> Bool {
        guard node.namespace == "http://schemas.microsoft.com/office/powerpoint/2010/main", node.children.isEmpty,
              Set(node.attributes.keys) == ["val"], let value = node.attr("val") else { return false }
        return node.name == "defaultImageDpi" && UInt32(value) != nil
            || node.name == "discardImageEditData" && ["0", "1", "false", "true"].contains(value)
    }
    static func build(_ storage: Preservation) throws -> PackageGraph {
        let package = try OPCPackage(storage.data, limits: storage.limits)
        let slides = Dictionary(uniqueKeysWithValues: storage.slidePaths.map { ($0.value, $0.key) })
        let notes = Dictionary(storage.notesPaths.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
        var references: [PackageReference] = [], scopes: [ReferenceLocation] = [], uninspected: [String] = [], identities: [SourceIdentity] = []
        func addIdentity(_ elements: [Element], slide: String, part: String) {
            for element in elements {
                identities.append(.init(slideID: slide, elementID: element.id, part: part, sourceID: UInt32(element.id) == nil ? nil : element.id))
                addIdentity(element.children, slide: slide, part: part)
            }
        }
        for slide in storage.originalSlides {
            guard let part = storage.slidePaths[slide.id] else { continue }
            identities.append(.init(slideID: slide.id, part: part, sourceID: slide.id))
            addIdentity(slide.elements, slide: slide.id, part: part)
        }
        for part in package.parts.sorted(by: { $0.path < $1.path }) {
            try Task.checkCancellation()
            if let source = relationshipSource(part.path) {
                for rel in try package.relationships(from: source).values.sorted(by: { $0.id < $1.id }) {
                    references.append(.init(kind: .relationship, knowledge: knownRelationships.contains(rel.type) ? .known : .unknown,
                        location: .init(part: part.path, path: "{\(NS.rels)}Relationships[1]/{\(NS.rels)}Relationship[@Id=\(rel.id)]", attribute: "Target", slideID: slides[source] ?? notes[source]),
                        value: rel.target, sourcePart: source, relationshipType: rel.type, targetPart: rel.path, isExternal: rel.isExternal))
                }
                continue
            }
            guard part.path.hasSuffix(".xml") || part.contentType?.hasSuffix("+xml") == true || part.contentType == "application/xml" else {
                uninspected.append(part.path); continue
            }
            let root = try MarkupNode.parse(package.archive.read(part.path), part: part.path, limits: storage.limits)
            let rels = try package.relationships(from: part.path)
            let slideID = slides[part.path] ?? notes[part.path]
            var owners: [ObjectIdentifier: String] = [:]
            func bind(_ elements: [Element], to parent: MarkupNode) throws {
                let nodes = parent.children.filter { !($0.isP && ["nvGrpSpPr", "grpSpPr"].contains($0.name)) }
                guard nodes.count == elements.count else { throw SlideError.unsafeEdit("原本要素の位置対応が不明です") }
                for (element, node) in zip(elements, nodes) {
                    owners[ObjectIdentifier(node)] = element.id
                    if element.kind == .group { try bind(element.children, to: node) }
                }
            }
            if let id = slides[part.path], let slide = storage.originalSlides.first(where: { $0.id == id }), let tree = root.child("cSld")?.child("spTree") {
                try bind(slide.elements, to: tree)
            }
            func walk(_ node: MarkupNode, path: String, owner: String?) throws {
                try Task.checkCancellation()
                // Bind by the reader's node correspondence, including synthetic opaque IDs.
                // Structural spTree headers and notes IDs are not model element identities.
                let elementID = owners[ObjectIdentifier(node)] ?? owner
                let unknown = !knownNamespace(node.namespace) && !metadataID(node) && !imageSetting(node)
                let location = ReferenceLocation(part: part.path, path: path, slideID: slideID, elementID: elementID)
                if unknown { scopes.append(location) }
                for (key, value) in node.attributes.sorted(by: { $0.key < $1.key }) {
                    let attrLocation = ReferenceLocation(part: part.path, path: path, attribute: key, slideID: slideID, elementID: elementID)
                    if key.hasPrefix(NS.r + "|") || key.hasPrefix(NS.strictR + "|") {
                        guard let rel = rels[value] else { throw SlideError.invalidRelationship(part: part.path, detail: "XML属性の参照がありません: \(value)") }
                        let recognized = node.isP && ["sldId", "sldMasterId", "notesMasterId", "sldLayoutId", "handoutMasterId", "snd"].contains(node.name)
                            || node.isA && ["blip", "hlinkClick", "hlinkHover", "audioFile", "videoFile"].contains(node.name)
                            || chartNamespaces.contains(node.namespace) && ["chart", "externalData"].contains(node.name)
                        references.append(.init(kind: .relationshipAttribute, knowledge: !recognized || !knownRelationships.contains(rel.type) ? .unknown : .known,
                            location: attrLocation, value: value, relationshipType: rel.type, targetPart: rel.path, isExternal: rel.isExternal))
                    } else if node.isP && ["spTgt", "bldP", "bldDgm", "bldOleChart", "bldGraphic"].contains(node.name) && key == "spid" {
                        references.append(.init(kind: .timing, knowledge: .known, location: attrLocation, value: value, targetPart: part.path, targetElementID: value))
                    } else if node.isA && ["stCxn", "endCxn"].contains(node.name) && key == "id" {
                        references.append(.init(kind: .connector, knowledge: .known, location: attrLocation, value: value, targetPart: part.path, targetElementID: value))
                    } else if unknown || key.contains("|") && !knownNamespace(String(key.split(separator: "|")[0])) && !key.hasPrefix("http://www.w3.org/XML/1998/namespace|") || key == "spid"
                        || (key == "target" || key == "id" || key.hasSuffix("Id") || key.hasSuffix("ID") || key == "ref" || key.hasSuffix("Ref") || key.hasSuffix("Reference"))
                            && !(key == "id" && (node.isP && ["cNvPr", "cTn", "sldId", "sldMasterId", "sldLayoutId"].contains(node.name) || node.isA && node.name == "fld")) {
                        references.append(.init(kind: .unknown, knowledge: .unknown, location: attrLocation, value: value))
                        if !unknown { scopes.append(attrLocation) }
                    }
                }
                var counts: [String: Int] = [:]
                for child in node.children {
                    let name = "{\(child.namespace)}\(child.name)"
                    counts[name, default: 0] += 1
                    try walk(child, path: path + "/" + name + "[\(counts[name]!)]", owner: elementID)
                }
            }
            try walk(root, path: "{\(root.namespace)}\(root.name)[1]", owner: nil)
        }
        return .init(parts: package.parts, identities: identities, references: references, unresolvedScopes: scopes, uninspectedParts: uninspected)
    }

    static func validateDeletion(_ graph: PackageGraph, part: String, removed: Set<String>) throws {
        for reference in graph.references where reference.targetPart == part && reference.targetElementID.map(removed.contains) == true {
            if reference.location.elementID.map(removed.contains) != true {
                throw SlideError.unsafeEdit("削除要素を参照しています: \(reference.location.path)")
            }
        }
        for reference in graph.references where reference.knowledge == .unknown && reference.targetPart == part {
            if reference.location.elementID.map(removed.contains) != true { throw SlideError.unsafeEdit("削除要素への未知参照を判断できません: \(reference.location.path)") }
        }
        for scope in graph.unresolvedScopes where (scope.part == part || scope.slideID == nil) && scope.elementID.map(removed.contains) != true {
            throw SlideError.unsafeEdit("削除要素への未知参照を判断できません: \(scope.path)")
        }
    }
}
