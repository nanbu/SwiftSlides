import Foundation
import SlideCore

final class TableReadBudget {
    private var used = 0
    func consume(_ count: Int, limit: Int) throws {
        guard count >= 0, used <= limit, count <= limit - used else { throw SlideError.limitExceeded("PPTX tableセル数") }
        used += count
    }
}

extension PPTXReader {
    func finite(_ value: String?, part: String, name: String) throws -> Double? {
        guard let value else { return nil }
        guard let n = Double(value), n.isFinite else { throw SlideError.corruptedPackage("不正な数値 \(name): \(part)") }
        return n
    }
    func imageCrop(_ node: MarkupNode?, part: String) throws -> ImageCrop? {
        guard let node else { return nil }
        func edge(_ name: String) throws -> Double? {
            guard let raw = node.attr(name) else { return nil }
            guard let n = percentage(raw), n.isFinite else { throw SlideError.corruptedPackage("不正な画像crop: \(part)") }; return n
        }
        return try .init(top: edge("t"), left: edge("l"), bottom: edge("b"), right: edge("r"))
    }
    func drawingChild(_ node: MarkupNode?, _ name: String) -> MarkupNode? { node?.children.first { $0.isA && $0.name == name } }
    func fill(_ node: MarkupNode?, part: String) throws -> Fill? {
        guard let node else { return nil }
        if drawingChild(node,"noFill") != nil { return Fill.none }
        if let c = color(drawingChild(node,"solidFill"), part: part) { return .solid(c) }
        if let gradient = drawingChild(node,"gradFill") {
            var stops: [GradientStop] = []
            for stop in drawingChild(gradient,"gsLst")?.children.filter({ $0.isA && $0.name == "gs" }) ?? [] {
                try Task.checkCancellation()
                guard let pos = percentage(stop.attr("pos")), pos.isFinite, (0...1).contains(pos), let c = color(stop, part: part) else {
                    throw SlideError.corruptedPackage("不正なgradient stop: \(part)")
                }
                stops.append(.init(position: pos, color: c))
            }
            if stops.isEmpty { warn(part,gradient,.uninterpretedFormatting,"gradientの直接stopが省略されています。継承で補いません") }
            let linear = drawingChild(gradient,"lin")
            return .gradient(try .init(stops: stops, angle: finite(linear?.attr("ang"), part: part, name: "ang").map { $0 / 60_000 },
                scaled: boolean(linear?.attr("scaled")), path: drawingChild(gradient,"path")?.attr("path"), flip: gradient.attr("flip"), rotatesWithShape: boolean(gradient.attr("rotWithShape")), rawXML: gradient.xml))
        }
        if let pattern = drawingChild(node,"pattFill") {
            return .pattern(.init(preset: pattern.attr("prst"), foreground: color(drawingChild(pattern,"fgClr"),part:part), background: color(drawingChild(pattern,"bgClr"),part:part), rawXML: pattern.xml))
        }
        if let picture = drawingChild(node,"blipFill") {
            let blip = drawingChild(picture,"blip")
            let reference: PartReference?
            if let id = blip?.rel("embed") ?? blip?.rel("link") {
                reference = try partReference(id, rels: relationships(from: part), part: part, expected: "image")
                if reference?.externalTarget != nil { warn(part, picture, .unsupportedContent, "外部画像塗りは取得しません") }
            } else { reference = nil; warn(part,picture,.uninterpretedFormatting,"画像塗りの直接参照が省略されています。継承で補いません") }
            return .picture(try .init(part: part, image: reference, crop: imageCrop(drawingChild(picture,"srcRect"),part:part), isTiled: drawingChild(picture,"tile") != nil, rotatesWithShape: boolean(picture.attr("rotWithShape")), rawXML: picture.xml))
        }
        return nil
    }
    func nativeFeature(_ node: MarkupNode, rels: [String: Relationship], part: String) throws -> NativeFeatureDescriptor {
        var references: [PartReference] = [], seen = Set<String>()
        func visit(_ node: MarkupNode) throws {
            try Task.checkCancellation()
            for (key, id) in node.attributes.sorted(by: { $0.key < $1.key }) where key.hasPrefix(NS.r + "|") || key.hasPrefix(NS.strictR + "|") {
                if seen.insert(id).inserted {
                    if rels[id] != nil { references.append(try partReference(id,rels:rels,part:part)) }
                    else { references.append(.init(relationshipID:id)); warn(part,node,.unsupportedContent,"未知内容の参照先が未解決です。参照IDを保持します") }
                }
            }
            for child in node.children { try visit(child) }
        }
        try visit(node)
        return .init(part: part, name: node.name, namespace: node.namespace, xml: node.xml, references: references)
    }
    func transition(_ node: MarkupNode?, part: String, slideID: String) throws -> SlideTransition? {
        guard let node else { return nil }
        func time(_ raw: String?) throws -> UInt32? {
            guard let raw else { return nil }; guard let value = UInt32(raw) else { throw SlideError.corruptedPackage("不正なtransition時刻: \(part)") }; return value
        }
        let effect = node.children.first { !($0.isP && ["sndAc", "extLst"].contains($0.name)) }
        warn(part,node,.unsupportedContent,"遷移の記述を読みます。固有効果の再生は行いません",feature:"ANI-001",slideID:slideID)
        return try .init(effect: effect?.name, effectNamespace: effect?.namespace, speed: node.attr("spd"), advancesOnClick: boolean(node.attr("advClick")),
            advanceAfterMilliseconds: time(node.attr("advTm")), durationMilliseconds: time(node.attributes["http://schemas.microsoft.com/office/powerpoint/2010/main|dur"]), rawXML: node.xml)
    }
    func timing(_ node: MarkupNode?, part: String, slideID: String) throws -> SlideTiming? {
        guard let node else { return nil }
        var targets: [String] = []
        func project(_ node: MarkupNode) throws -> TimingNode {
            try Task.checkCancellation()
            if node.isP, node.name == "spTgt", let id = node.attr("spid") { targets.append(id) }
            let text = node.content.compactMap { if case .text(let s) = $0 { s } else { nil } }.joined()
            return .init(name: node.name, namespace: node.namespace, attributes: node.attributes, text: text.isEmpty ? nil : text, children: try node.children.map(project))
        }
        let root = try project(node)
        warn(part,node,.unsupportedContent,"時間構造・対象・パラメータを読みます。再生・トリガー評価は行いません",feature:"ANI-005",slideID:slideID)
        return .init(root: root, targetElementIDs: targets, rawXML: node.xml)
    }
    func media(in node: MarkupNode?, rels: [String: Relationship], part: String) throws -> [MediaReference]? {
        guard let node else { return nil }
        var result: [MediaReference] = []
        func visit(_ node: MarkupNode) throws {
            try Task.checkCancellation()
            let kind: MediaReference.Kind?
            if node.isA, ["audioFile", "wavAudioFile", "snd"].contains(node.name) { kind = .audio }
            else if node.isA, ["videoFile", "quickTimeFile"].contains(node.name) { kind = .video }
            else if node.namespace == "http://schemas.microsoft.com/office/powerpoint/2010/main", node.name == "media" { kind = .media }
            else { kind = nil }
            if let kind {
                guard let id = node.rel("embed") ?? node.rel("link") else { throw SlideError.invalidRelationship(part: part, detail: "メディア参照がありません") }
                let reference = try partReference(id,rels:rels,part:part)
                let expected = kind == .audio ? ["audio", "media"] : kind == .video ? ["video", "media"] : ["audio", "video", "media"]
                guard let type = rels[id]?.type, (expected.contains(type) || type == "http://schemas.microsoft.com/office/2007/relationships/media") else { throw SlideError.invalidRelationship(part:part,detail:"メディア参照型が不正です") }
                result.append(.init(kind:kind,reference:reference,contentType:reference.path.flatMap { extraTypes[$0] ?? package.type(of:$0) },rawXML:node.xml))
                warn(part,node,.unsupportedContent,"メディア参照を読みます。デコード・再生は行いません")
            }
            for child in node.children { try visit(child) }
        }
        try visit(node); return result.isEmpty ? nil : result
    }
    func comments(rels: [String: Relationship], part: String, slideID: String) throws -> (comments: [SlideComment], native: [NativeFeatureDescriptor]) {
        var result: [SlideComment] = [], native: [NativeFeatureDescriptor] = []
        let commentTypes = ["comments", "comment", "http://schemas.microsoft.com/office/2018/10/relationships/comments"]
        let commentRels = rels.values.filter { commentTypes.contains($0.type) }.sorted { $0.id < $1.id }
        guard !commentRels.isEmpty else { return (result,native) }
        var authors: [String: (String?, String?)] = [:]
        for rel in try relationships(from:package.mainPart).values.filter({ $0.type == "commentAuthors" }).sorted(by: { $0.id < $1.id }) {
            guard let path = rel.path else { throw SlideError.invalidRelationship(part:part,detail:"外部commentAuthors") }
            let root = try tree(path)
            guard root.isP, root.name == "cmAuthorLst" else { native.append(try nativeFeature(root,rels:relationships(from:path),part:path)); continue }
            for author in root.children where author.isP && author.name == "cmAuthor" {
                guard let id = author.attr("id"), UInt32(id) != nil, authors[id] == nil else { throw SlideError.corruptedPackage("comment作者ID不正または重複") }
                authors[id] = (author.attr("name"),author.attr("initials"))
            }
        }
        for rel in commentRels {
            guard let path = rel.path else { throw SlideError.invalidRelationship(part:part,detail:"外部comments") }
            let root = try tree(path)
            native.append(try nativeFeature(root,rels:relationships(from:path),part:path))
            guard root.isP, root.name == "cmLst" else {
                if root.name == "cmLst", root.namespace == "http://schemas.microsoft.com/office/powerpoint/2018/8/main" { continue }
                warn(path,root,.unsupportedContent,"このコメント形式の意味は未解釈です。XMLと参照を保持します",slideID:slideID); continue
            }
            var identities = Set<String>()
            for comment in root.children where comment.isP && comment.name == "cm" {
                let author = comment.attr("authorId"), index = comment.attr("idx")
                guard let author, UInt32(author) != nil, let index, UInt32(index) != nil, identities.insert(author + "/" + index).inserted, let text = comment.children.first(where:{ $0.isP && $0.name == "text" }) else { throw SlideError.corruptedPackage("commentの必須値・identityが不正") }
                let position = comment.child("pos")
                result.append(try .init(id:index,authorID:author,authorName:authors[author]?.0,authorInitials:authors[author]?.1,dateTime:comment.attr("dt"),
                    x:finite(position?.attr("x"),part:path,name:"comment x").map { $0 / 8 },y:finite(position?.attr("y"),part:path,name:"comment y").map { $0 / 8 },text:text.text,part:path,rawXML:comment.xml))
                if authors[author] == nil { warn(path,comment,.unsupportedContent,"コメント作者の参照が未解決です",slideID:slideID) }
                for child in comment.children where !(child.isP && ["text","pos"].contains(child.name)) { warn(path,child,.unsupportedContent,"コメントの追加属性はXMLで保持します",slideID:slideID) }
            }
        }
        return (result,native)
    }
}
