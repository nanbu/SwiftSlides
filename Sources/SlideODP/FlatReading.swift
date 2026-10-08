import Foundation
import SlideCore

enum FlatODP {
    static func archive(_ data: Data, limits: PackageLimits) throws -> PackageArchive {
        guard data.count <= limits.maxPartBytes, data.count <= limits.maxExpandedBytes else { throw SlideError.limitExceeded("Flat ODP入力予算") }
        let root = try MarkupNode.parse(data,part:"flat.xml",limits:limits)
        guard root.namespace == ODF.office, root.name == "document", root.odf(ODF.office,"mimetype") == ODF.mime else { throw SlideError.unknownFormat }
        guard let version = root.odf(ODF.office,"version"), ["1.2","1.3","1.4"].contains(version) else { throw SlideError.unsupportedContainer("Flat ODP version") }
        var parts: [String:Data] = ["mimetype":Data(ODF.mime.utf8),"flat.xml":data], mediaTypes: [String:String] = [:], expanded = 0
        func visit(_ node: MarkupNode) throws {
            try Task.checkCancellation()
            if node.namespace == ODF.draw, node.name == "image", let binary = node.child("binary-data",ns:ODF.office) {
                guard node.odf(ODF.xlink,"href") == nil else { throw SlideError.corruptedPackage("Flat ODP画像参照とbinary-data併記") }
                let text = binary.text.filter { !$0.isWhitespace }
                guard let bytes = Data(base64Encoded:text), bytes.count <= limits.maxPartBytes, bytes.count <= limits.maxExpandedBytes-expanded else { throw SlideError.corruptedPackage("Flat ODP binary-data/予算") }
                expanded += bytes.count
                let path = "Pictures/embedded-\(mediaTypes.count+1).bin"
                parts[path] = bytes
                mediaTypes[path] = node.odf(ODF.draw,"mime-type") ?? (bytes.starts(with:[0x89,0x50,0x4e,0x47]) ? "image/png" : bytes.starts(with:[0xff,0xd8]) ? "image/jpeg" : "application/octet-stream")
                node.namespaces["xlink"] = ODF.xlink; node.attributes[ODF.xlink+"|href"] = path; node.attributeNames[ODF.xlink+"|href"] = "xlink:href"
                node.content.removeAll { if case .node(let child) = $0 { child === binary } else { false } }
            }
            for child in node.children { try visit(child) }
        }
        try visit(root)
        func document(_ name: String, select: (MarkupNode) -> Bool) -> Data {
            let node = MarkupNode(name:name,namespace:ODF.office,qualifiedName:"office:"+name,attributes:root.attributes,attributeNames:root.attributeNames,namespaces:root.namespaces)
            node.namespaces["office"] = ODF.office
            node.content = root.children.filter(select).map(MarkupNode.Content.node)
            return Data(node.xml.utf8)
        }
        parts["content.xml"] = document("document-content") { !["styles","master-styles","meta"].contains($0.name) || $0.namespace != ODF.office }
        parts["styles.xml"] = document("document-styles") { ["styles","master-styles","font-face-decls","automatic-styles"].contains($0.name) && $0.namespace == ODF.office }
        // 各索引でautomatic-stylesを一度だけ扱う。page-layoutはstyles側に必要。
        if let automatic = root.child("automatic-styles",ns:ODF.office) {
            let style = try MarkupNode.parse(parts["styles.xml"]!,part:"styles.xml",limits:limits)
            style.child("automatic-styles",ns:ODF.office)?.content = automatic.children.filter { $0.namespace == ODF.style && $0.name == "page-layout" }.map(MarkupNode.Content.node)
            parts["styles.xml"] = Data(style.xml.utf8)
            let content = try MarkupNode.parse(parts["content.xml"]!,part:"content.xml",limits:limits)
            content.child("automatic-styles",ns:ODF.office)?.content.removeAll { if case .node(let n) = $0 { n.namespace == ODF.style && n.name == "page-layout" } else { false } }
            parts["content.xml"] = Data(content.xml.utf8)
        }
        if root.child("meta",ns:ODF.office) != nil { parts["meta.xml"] = document("document-meta") { $0.namespace == ODF.office && $0.name == "meta" } }
        var entries = "<manifest:file-entry manifest:full-path=\"/\" manifest:media-type=\"\(ODF.mime)\"/>"
        for path in parts.keys.sorted() where path != "mimetype" { entries += "<manifest:file-entry manifest:full-path=\"\(escapeXML(path))\" manifest:media-type=\"\(mediaTypes[path] ?? "text/xml")\"/>" }
        parts["META-INF/manifest.xml"] = Data("<manifest:manifest xmlns:manifest=\"\(ODF.manifest)\" manifest:version=\"\(version)\">\(entries)</manifest:manifest>".utf8)
        return try PackageArchive(parts:parts,limits:limits)
    }
}
