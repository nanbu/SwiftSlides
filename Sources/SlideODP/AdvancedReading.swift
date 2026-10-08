import Foundation
import SlideCore

extension ODPPageParser {
    func reference(_ href: String) throws -> PartReference {
        if href.hasPrefix("#") { return .init(relationshipID:href) }
        if href.contains(":") || href.hasPrefix("//") { return .init(relationshipID:href,externalTarget:href) }
        let path=try OPCPackage.resolve(href,from:"content.xml")
        if archive.entries[path] != nil { return .init(relationshipID:href,path:path) }
        let object=path.hasSuffix("/") ? path+"content.xml" : path+"/content.xml"
        guard archive.entries[object] != nil else { throw SlideError.missingPart(path) }
        return .init(relationshipID:href,path:object)
    }
    func nativeFeature(_ node: MarkupNode) throws -> NativeFeatureDescriptor {
        var references:[PartReference]=[],seen=Set<String>()
        func visit(_ node: MarkupNode) throws {
            try Task.checkCancellation()
            if let href=node.odf(ODF.xlink,"href"),!href.isEmpty,seen.insert(href).inserted { references.append(try reference(href)) }
            for child in node.children { try visit(child) }
        }
        try visit(node)
        return .init(part:"content.xml",name:node.name,namespace:node.namespace,xml:node.xml,references:references)
    }
    func media(_ node: MarkupNode) throws -> [MediaReference]? {
        var values:[MediaReference]=[]
        func visit(_ node: MarkupNode) throws {
            try Task.checkCancellation()
            if (node.namespace == ODF.draw && node.name == "plugin") || (node.namespace == ODF.anim && node.name == "audio") || (node.namespace == ODF.presentation && node.name == "sound") {
                guard let href=node.odf(ODF.xlink,"href") else { throw SlideError.corruptedPackage("ODP media参照なし") }
                let ref=try reference(href),mime=node.odf(ODF.draw,"mime-type") ?? ref.path.flatMap { contentTypes[$0] }
                let kind:MediaReference.Kind = node.name == "audio" || node.name == "sound" || mime?.hasPrefix("audio/") == true ? .audio : mime?.hasPrefix("video/") == true ? .video : .media
                values.append(.init(kind:kind,reference:ref,contentType:mime,rawXML:node.xml))
                warn(node,"媒体参照を読みます。外部取得・再生は行いません")
            }
            for child in node.children { try visit(child) }
        }
        try visit(node);return values.isEmpty ? nil : values
    }
    func readAdvanced(_ node: MarkupNode, into slide: inout Slide) throws {
        slide.nativeFeatures = [try nativeFeature(node)]
        let timeNodes=node.children.filter { $0.namespace == ODF.anim || ($0.namespace == ODF.presentation && $0.name == "animations") }
        if !timeNodes.isEmpty {
            var targets:[String]=[]
            func time(_ n:MarkupNode) throws -> TimingNode {
                try Task.checkCancellation()
                if let target=n.odf(ODF.smil,"targetElement") ?? n.odf(ODF.draw,"shape-id") { targets.append(target) }
                let text=n.content.compactMap { if case .text(let s) = $0 { s } else { nil } }.joined()
                return try .init(name:n.name,namespace:n.namespace,attributes:n.attributes,text:text.isEmpty ? nil : text,children:n.children.map(time))
            }
            let children=try timeNodes.map(time)
            slide.timing = .init(root:.init(name:"pageTiming",namespace:ODF.anim,children:children),targetElementIDs:targets,rawXML:timeNodes.map(\.xml).joined())
            for n in timeNodes { warn(n,"ODPの時間値・trigger・対象を字句値で保持します。再生評価は行いません") }
        }
        let annotations=node.descendants("annotation",ns:ODF.office)
        if !annotations.isEmpty {
            slide.comments=try annotations.map { n in
                let paragraphs=try n.children.filter { $0.namespace == ODF.text && ["p","h"].contains($0.name) }.map(paragraph)
                return .init(id:n.odf(ODF.office,"name"),authorName:n.child("creator",ns:NS.dc)?.text,dateTime:n.child("date",ns:NS.dc)?.text,
                    text:paragraphs.map(\.plainText).joined(separator:"\n"),part:"content.xml",rawXML:n.xml)
            }
        }
        // ページ時間構造の音を、図形のpluginと重複させず返す。
        var sounds:[MediaReference]=[]
        for n in timeNodes { sounds += try media(n) ?? [] }
        slide.media=sounds.isEmpty ? nil : sounds
    }
}
