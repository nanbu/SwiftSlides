import Foundation
import SlideCore

private let modernCommentNS = "http://schemas.microsoft.com/office/powerpoint/2018/8/main"
private let modernCommentRel = "http://schemas.microsoft.com/office/2018/10/relationships/"
extension PPTXReader {
    func commentThreads(rels: [String: Relationship], slideID: String) throws -> [CommentThread] {
        let commentParts = rels.values.filter { $0.type == modernCommentRel + "comments" }.sorted { $0.id < $1.id }
        guard !commentParts.isEmpty else { return [] }
        var authors: [String: [String: String]] = [:]
        for rel in try relationships(from: package.mainPart).values.filter({ $0.type == modernCommentRel + "authors" }).sorted(by: { $0.id < $1.id }) {
            guard let path = rel.path else { throw SlideError.invalidRelationship(part: package.mainPart, detail: "外部コメント作者") }
            let root = try tree(path)
            guard root.namespace == modernCommentNS, root.name == "authorLst" else { throw SlideError.corruptedPackage("新コメント作者rootが不正") }
            for n in root.children where n.namespace == modernCommentNS && n.name == "author" {
                guard let id = n.attr("id"), !id.isEmpty, authors[id] == nil else { throw SlideError.corruptedPackage("新コメント作者ID不正/重複") }
                authors[id] = n.attributes
            }
        }
        var result: [CommentThread] = [], ids = Set<String>()
        for rel in commentParts {
            guard let path = rel.path else { throw SlideError.invalidRelationship(part: package.mainPart, detail: "外部コメント") }
            let root = try tree(path), relationships = try relationships(from: path)
            guard root.namespace == modernCommentNS, root.name == "cmLst" else {
                warn(path, root, .unsupportedContent, "未知の新コメントrootを原本に保持します", slideID: slideID); continue
            }
            func read(_ n: MarkupNode) throws -> CommentThread {
                try Task.checkCancellation()
                guard let id = n.attr("id"), !id.isEmpty, ids.insert(id).inserted, let author = n.attr("authorId"), !author.isEmpty,
                      let body = n.child("txBody", ns: modernCommentNS) else { throw SlideError.corruptedPackage("新コメントの必須値/identityが不正") }
                if authors[author] == nil { warn(path, n, .unsupportedContent, "新コメント作者が未解決です", slideID: slideID) }
                let pos = n.child("pos", ns: modernCommentNS)
                let anchors = n.children.filter { !($0.namespace == modernCommentNS && ["pos", "txBody", "replyLst"].contains($0.name)) }
                return try .init(id: id, authorID: author, authorName: authors[author]?["name"], authorInitials: authors[author]?["initials"], authorProperties: authors[author],
                    created: n.attr("created"), status: n.attr("status"), text: text(body, rels: relationships, part: path),
                    x: finite(pos?.attr("x"), part: path, name: "comment x").map { $0 / 12_700 }, y: finite(pos?.attr("y"), part: path, name: "comment y").map { $0 / 12_700 }, attributes: n.attributes,
                    anchors: anchors.map { try SourceXMLNode($0) }, replies: (n.child("replyLst", ns: modernCommentNS)?.children ?? []).filter { $0.namespace == modernCommentNS && $0.name == "reply" }.map(read), part: path, rawXML: n.xml)
            }
            for n in root.children {
                if n.namespace == modernCommentNS, n.name == "cm" { result.append(try read(n)) }
                else { warn(path, n, .unsupportedContent, "新コメント追加構造を原本に保持します", slideID: slideID) }
            }
        }
        return result
    }
}
