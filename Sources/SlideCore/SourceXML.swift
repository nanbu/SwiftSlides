import Foundation

/// 名前空間と混在内容の順序を保つ、不変の原本XML。意味解釈済みのモデルとは区別する。
public struct SourceXMLNode: Sendable, Equatable, Codable {
    public enum Content: Sendable, Equatable, Codable { case text(String), element(SourceXMLNode) }
    public let name: String
    public let namespace: String
    /// 原本の接頭辞を含むQName。
    public let qualifiedName: String
    /// この要素で有効な接頭辞→URI。QNameを含む属性値の解釈に使う。
    public let namespaceBindings: [String: String]
    /// 名前空間つき属性のキーはURI|localName。
    public let attributes: [String: String]
    /// attributesのキー→原本の属性QName。
    public let attributeNames: [String: String]
    public let content: [Content]
    public var children: [SourceXMLNode] { content.compactMap { if case .element(let n) = $0 { n } else { nil } } }
    public var text: String { content.map { switch $0 { case .text(let s): s; case .element(let n): n.text } }.joined() }
    public func descendants(named name:String, namespace:String? = nil) -> [SourceXMLNode] {
        var result: [SourceXMLNode] = []
        var pending = [content.makeIterator()]
        while !pending.isEmpty {
            guard let item = pending[pending.count - 1].next() else { pending.removeLast(); continue }
            if case .element(let node) = item {
                if node.name == name && (namespace == nil || node.namespace == namespace) { result.append(node) }
                pending.append(node.content.makeIterator())
            }
        }
        return result
    }
    package init(_ node: MarkupNode) throws {
        try Task.checkCancellation()
        name = node.name; namespace = node.namespace; qualifiedName = node.qualifiedName
        namespaceBindings = node.namespaces; attributes = node.attributes; attributeNames = node.attributeNames
        content = try node.content.map { switch $0 { case .text(let s): .text(s); case .node(let n): .element(try SourceXMLNode(n)) } }
    }
}
public struct SourceXMLReadResult: Sendable {
    public let part: String
    public let root: SourceXMLNode
    public let warnings: [SlideWarning]
    public var diagnostics: [SlideDiagnostic] { warnings.map { $0.diagnostic(stage: .read) } }
    package init(part: String, root: SourceXMLNode) {
        self.part = part; self.root = root
        warnings = [.init(code: .unsupportedContent, part: part, element: root.name, message: "原本のXML構造を返します。全属性の意味解釈・描画は保証しません")]
    }
}
extension Presentation {
    /// 任意の保持XMLを読み取る。外部参照は取得しない。
    public func readSourceXML(at path: String) throws -> SourceXMLReadResult {
        let bytes = try asset(at: path), limits = storage?.limits ?? PackageLimits()
        guard bytes.count <= limits.maxPartBytes else { throw SlideError.limitExceeded("source XML part") }
        return try .init(part: path, root: SourceXMLNode(MarkupNode.parse(bytes, part: path, limits: limits)))
    }
    @concurrent public func readSourceXML(at path: String) async throws -> SourceXMLReadResult { try sourceXMLSync(at: path) }
    private func sourceXMLSync(at path: String) throws -> SourceXMLReadResult { try readSourceXML(at: path) }
}

/// Officeの新コメント。replyの順序・省略属性・anchor/taskの構造を維持する。
public struct CommentThread: Sendable, Equatable, Codable {
    public let id: String
    public let authorID: String
    public let authorName: String?
    public let authorInitials: String?
    public let authorProperties: [String: String]?
    public let created: String?
    public let status: String?
    public let text: TextBody
    public let x: Double?
    public let y: Double?
    public let attributes: [String: String]
    public let anchors: [SourceXMLNode]
    public let replies: [CommentThread]
    public let part: String
    public let rawXML: String
    public init(id: String, authorID: String, authorName: String? = nil, authorInitials: String? = nil, authorProperties: [String: String]? = nil, created: String? = nil, status: String? = nil, text: TextBody, x: Double? = nil, y: Double? = nil, attributes: [String: String] = [:], anchors: [SourceXMLNode] = [], replies: [CommentThread] = [], part: String, rawXML: String = "") {
        self.id = id; self.authorID = authorID; self.authorName = authorName; self.authorInitials = authorInitials; self.authorProperties = authorProperties; self.created = created; self.status = status; self.text = text; self.x = x; self.y = y; self.attributes = attributes; self.anchors = anchors; self.replies = replies; self.part = part; self.rawXML = rawXML
    }
}
