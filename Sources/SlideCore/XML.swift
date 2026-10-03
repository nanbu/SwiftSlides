import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

package enum NS {
    package static let p = "http://schemas.openxmlformats.org/presentationml/2006/main"
    package static let a = "http://schemas.openxmlformats.org/drawingml/2006/main"
    package static let r = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    package static let strictP = "http://purl.oclc.org/ooxml/presentationml/main"
    package static let strictA = "http://purl.oclc.org/ooxml/drawingml/main"
    package static let strictR = "http://purl.oclc.org/ooxml/officeDocument/relationships"
    package static let rels = "http://schemas.openxmlformats.org/package/2006/relationships"
    package static let types = "http://schemas.openxmlformats.org/package/2006/content-types"
    package static let dc = "http://purl.org/dc/elements/1.1/"
    package static let core = "http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
}
package func escapeXML(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\r", with: "&#13;") }
/// 操作内部だけで使う可変ツリー。原本のQNameと名前空間スコープを保持する。
package final class MarkupNode {
    package enum Content { case text(String), node(MarkupNode) }
    package let name: String
    package let namespace: String
    package var qualifiedName: String
    package var attributes: [String: String]
    package var attributeNames: [String: String]
    package var namespaces: [String: String]
    package var content: [Content] = []
    package init(name: String, namespace: String, qualifiedName: String, attributes: [String: String] = [:], attributeNames: [String: String] = [:], namespaces: [String: String] = [:]) {
        self.name = name; self.namespace = namespace; self.qualifiedName = qualifiedName; self.attributes = attributes; self.attributeNames = attributeNames; self.namespaces = namespaces
    }
    package var children: [MarkupNode] { content.compactMap { if case .node(let n) = $0 { n } else { nil } } }
    package var text: String { content.map { switch $0 { case .text(let t): t; case .node(let n): n.text } }.joined() }
    package var isP: Bool { namespace == NS.p || namespace == NS.strictP }
    package var isA: Bool { namespace == NS.a || namespace == NS.strictA }
    package func child(_ name: String, ns: String? = nil) -> MarkupNode? { children.first { node in node.name == name && (ns.map { node.namespace == $0 } ?? (node.isP || node.isA)) } }
    package func named(_ name: String) -> [MarkupNode] { children.filter { $0.name == name && ($0.isA || $0.isP) } }
    package func descendants(_ name: String, ns: String? = nil) -> [MarkupNode] { children.flatMap { n in ((n.name == name && (ns.map { n.namespace == $0 } ?? (n.isA || n.isP))) ? [n] : []) + n.descendants(name, ns: ns) } }
    package func attr(_ name: String) -> String? { attributes[name] }
    package func rel(_ name: String) -> String? { attributes["\(NS.r)|\(name)"] ?? attributes["\(NS.strictR)|\(name)"] }
    package func set(_ name: String, _ value: String?) { attributes[name] = value; attributeNames[name] = value == nil ? nil : name }
    package func setRel(_ name: String, _ value: String, strict: Bool = false) { let uri = strict ? NS.strictR : NS.r; attributes["\(uri)|\(name)"] = value; attributeNames["\(uri)|\(name)"] = "ssr:\(name)"; namespaces["ssr"] = uri }
    package func remove(_ names: Set<String>) { content.removeAll { if case .node(let n) = $0 { names.contains(n.name) && (n.isA || n.isP) } else { false } } }
    package func replace(_ name: String, with node: MarkupNode?, first: Bool = false) {
        if let i = content.firstIndex(where: { if case .node(let n) = $0 { n.name == name && (n.isA || n.isP) } else { false } }) { if let node { content[i] = .node(node) } else { content.remove(at: i) } }
        else if let node { if first { content.insert(.node(node), at: 0) } else { content.append(.node(node)) } }
    }
    /// 差し替えXMLは別の接頭辞を宣言し、元のQName値に使う接頭辞を変更しない。
    package static func fragment(_ xml: String, strict: Bool = false) throws -> MarkupNode {
        let a = strict ? NS.strictA : NS.a, p = strict ? NS.strictP : NS.p, r = strict ? NS.strictR : NS.r
        let wrapped = "<wrapper xmlns:a=\"\(a)\" xmlns:p=\"\(p)\" xmlns:r=\"\(r)\">\(xml)</wrapper>"
        let root = try parse(Data(wrapped.utf8), part: "generated", limits: .init())
        guard root.children.count == 1, let node = root.children.first else { throw SlideError.invalidModel("生成XMLには一つのルートが必要です") }; return node
    }
    package var xml: String { serialized(parentNamespaces: [:]) }
    private func serialized(parentNamespaces: [String: String]) -> String {
        var declarations = ""
        for (prefix,uri) in namespaces.sorted(by: { $0.key < $1.key }) where parentNamespaces[prefix] != uri && prefix != "xml" {
            declarations += prefix.isEmpty ? " xmlns=\"\(escapeXML(uri))\"" : " xmlns:\(prefix)=\"\(escapeXML(uri))\""
        }
        let attrs = attributes.sorted(by: { $0.key < $1.key }).map { " \(attributeNames[$0.key] ?? $0.key)=\"\(escapeXML($0.value))\"" }.joined()
        let body = content.map { switch $0 { case .text(let t): escapeXML(t); case .node(let n): n.serialized(parentNamespaces: namespaces) } }.joined()
        return "<\(qualifiedName)\(declarations)\(attrs)>\(body)</\(qualifiedName)>"
    }
    package static func parse(_ data: Data, part: String, limits: PackageLimits) throws -> MarkupNode {
        guard limits.maxXMLDepth > 0, limits.maxXMLNodes > 0 else { throw SlideError.limitExceeded("XML limits") }
        // XML accepts UTF-8/16/32. Reject declarations before handing bytes to the platform parser.
        for encoding in [String.Encoding.utf8, .utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian] {
            for keyword in ["<!DOCTYPE", "<!ENTITY"] { if let pattern = keyword.data(using: encoding), data.range(of: pattern) != nil { throw SlideError.invalidXML(part: part, detail: "DTD / ENTITYは禁止です") } }
        }
        let d = XMLDelegate(part: part, limits: limits), parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true; parser.shouldReportNamespacePrefixes = true; parser.shouldResolveExternalEntities = false; parser.delegate = d
        let ok = parser.parse()
        if let error = d.failure { throw error }
        guard ok, parser.parserError == nil, d.completed, d.stack.isEmpty, let root = d.root else { throw SlideError.invalidXML(part: part, detail: parser.parserError?.localizedDescription ?? "不完全なXML") }; return root
    }
}
private final class XMLDelegate: NSObject, XMLParserDelegate {
    let part: String
    let limits: PackageLimits
    var root: MarkupNode?
    var stack: [MarkupNode] = []
    var prefixes: [String: [String]] = ["xml": ["http://www.w3.org/XML/1998/namespace"]]
    var failure: (any Error)?
    var nodes = 0
    var completed = false
    init(part: String, limits: PackageLimits) { self.part = part; self.limits = limits }
    func parserDidEndDocument(_ parser: XMLParser) { completed = true }
    func parser(_ parser: XMLParser, parseErrorOccurred error: any Error) { if failure == nil { failure = SlideError.invalidXML(part: part, detail: error.localizedDescription) } }
    func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI uri: String) { prefixes[prefix, default: []].append(uri) }
    func parser(_ parser: XMLParser, didEndMappingPrefix prefix: String) { _ = prefixes[prefix]?.popLast() }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes dict: [String: String]) {
        nodes += 1
        guard nodes <= limits.maxXMLNodes, stack.count < limits.maxXMLDepth else { failure = SlideError.limitExceeded("XML深さ/要素数: \(part)"); parser.abortParsing(); return }
        var attrs: [String: String] = [:], names: [String: String] = [:]
        for (k,v) in dict {
            let pieces = k.split(separator: ":", maxSplits: 1).map(String.init)
            let key: String
            if pieces.count == 2 { guard let uri = prefixes[pieces[0]]?.last else { failure = SlideError.invalidXML(part: part, detail: "未宣言の接頭辞"); parser.abortParsing(); return }; key = "\(uri)|\(pieces[1])" } else { key = k }
            attrs[key] = v; names[key] = k
        }
        let node = MarkupNode(name: name, namespace: namespaceURI ?? "", qualifiedName: qName ?? name, attributes: attrs, attributeNames: names, namespaces: prefixes.compactMapValues(\.last))
        if let parent = stack.last { parent.content.append(.node(node)) } else { guard root == nil else { failure = SlideError.invalidXML(part: part, detail: "複数ルート"); parser.abortParsing(); return }; root = node }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters s: String) { stack.last?.content.append(.text(s)) }
    func parser(_ parser: XMLParser, foundCDATA data: Data) { self.parser(parser, foundCharacters: String(decoding: data, as: UTF8.self)) }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard failure == nil, let node = stack.popLast(), node.name == name, node.namespace == (namespaceURI ?? "") else { if failure == nil { failure = SlideError.invalidXML(part: part, detail: "不正なXML境界") }; parser.abortParsing(); return }
    }
    func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?) { failure = SlideError.invalidXML(part: part, detail: "processing instructionは未対応です"); parser.abortParsing() }
}
