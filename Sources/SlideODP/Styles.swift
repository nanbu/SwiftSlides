import Foundation
import SlideCore

package enum ODF {
    static let anim = "urn:oasis:names:tc:opendocument:xmlns:animation:1.0"
    static let smil = "urn:oasis:names:tc:opendocument:xmlns:smil-compatible:1.0"
    static let office = "urn:oasis:names:tc:opendocument:xmlns:office:1.0"
    static let draw = "urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
    static let style = "urn:oasis:names:tc:opendocument:xmlns:style:1.0"
    static let text = "urn:oasis:names:tc:opendocument:xmlns:text:1.0"
    static let presentation = "urn:oasis:names:tc:opendocument:xmlns:presentation:1.0"
    static let table = "urn:oasis:names:tc:opendocument:xmlns:table:1.0"
    static let svg = "urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0"
    static let fo = "urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
    static let xlink = "http://www.w3.org/1999/xlink"
    static let manifest = "urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"
    static let mime = "application/vnd.oasis.opendocument.presentation"
    static func key(_ ns: String, _ name: String) -> String { "\(ns)|\(name)" }
    static func length(_ value: String) throws -> Double {
        let units: [(String, Double)] = [("cm",72/2.54),("mm",72/25.4),("in",72),("pt",1),("pc",12)]
        for (unit, scale) in units where value.hasSuffix(unit) {
            guard let n = Double(value.dropLast(unit.count)), n.isFinite, (n * scale).isFinite else { break }
            return n * scale
        }
        if value == "0" { return 0 }
        throw SlideError.corruptedPackage("不正または未対応のODF長さ: \(value)")
    }
}
package extension MarkupNode {
    func odf(_ ns: String, _ name: String) -> String? { attr(ODF.key(ns,name)) }
    func children(_ ns: String, _ name: String) -> [MarkupNode] { children.filter { $0.namespace == ns && $0.name == name } }
}

/// 書式値の出典。property単位で上書きの由来を確認できる。
public struct ODPStyleOrigin: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable { case direct, automatic, named, defaultStyle, master }
    public let kind: Kind
    public let part: String
    public let name: String?
}
/// 書式の限定解決結果。値の欠如と未知の参照を分ける。
public struct ODPResolvedStyle: Sendable, Equatable, Codable {
    public let properties: [String: String]
    public let origins: [String: ODPStyleOrigin]
    public let unresolved: [String]
}
/// content/stylesのautomatic scope、family、named parentを分離した不変索引。
public struct ODPStyleIndex: Sendable {
    public init(data: Data, limits: PackageLimits = .init()) throws {
        self = try ODPDocument(data, options: .init(limits: limits)).styles
    }
    public init(contentsOf url: URL, limits: PackageLimits = .init()) throws {
        try self.init(data: PackageInput.read(url, limits: limits), limits: limits)
    }

    private struct Record: Sendable {
        let name: String
        let family: String
        let parent: String?
        let properties: [String: String]
        let origin: ODPStyleOrigin
    }
    private struct Master: Sendable { let style: String?; let layout: String? }
    private var named: [String: Record] = [:]
    private var automatic: [String: Record] = [:]
    private var defaults: [String: Record] = [:]
    private var masters: [String: Master] = [:]
    private let inheritanceLimit: Int
    private var layouts: [String: [String: String]] = [:]
    private static func key(_ family: String, _ name: String) -> String { "\(family)|\(name)" }
    package init(content: MarkupNode, styles: MarkupNode, limits: PackageLimits) throws {
        inheritanceLimit = limits.maxXMLDepth
        for (root, part) in [(styles,"styles.xml"),(content,"content.xml")] {
            for container in root.children where container.namespace == ODF.office && ["styles","automatic-styles"].contains(container.name) {
                for node in container.children where node.namespace == ODF.style {
                    if node.name == "page-layout", let name = node.odf(ODF.style,"name") {
                        guard layouts[name] == nil else { throw SlideError.corruptedPackage("重複page-layout: \(name)") }
                        layouts[name] = Self.properties(node)
                        continue
                    }
                    guard ["style","default-style"].contains(node.name), let family = node.odf(ODF.style,"family") else { continue }
                    let name = node.odf(ODF.style,"name") ?? ""
                    let kind: ODPStyleOrigin.Kind = node.name == "default-style" ? .defaultStyle : container.name == "automatic-styles" ? .automatic : .named
                    let record = Record(name:name,family:family,parent:node.odf(ODF.style,"parent-style-name"),properties:Self.properties(node),origin:.init(kind:kind,part:part,name:name.isEmpty ? nil : name))
                    let key = Self.key(family,name)
                    switch kind {
                    case .defaultStyle:
                        guard defaults[family] == nil else { throw SlideError.corruptedPackage("重複default style") }; defaults[family] = record
                    case .named:
                        guard !name.isEmpty, named[key] == nil else { throw SlideError.corruptedPackage("重複named style") }; named[key] = record
                    default:
                        let scoped = "\(part)|\(key)"
                        guard !name.isEmpty, automatic[scoped] == nil else { throw SlideError.corruptedPackage("重複automatic style") }; automatic[scoped] = record
                    }
                }
            }
        }
        for node in styles.child("master-styles",ns:ODF.office)?.children(ODF.style,"master-page") ?? [] {
            guard let name = node.odf(ODF.style,"name"), masters[name] == nil else { throw SlideError.corruptedPackage("不正または重複master-page") }
            masters[name] = .init(style:node.odf(ODF.draw,"style-name"),layout:node.odf(ODF.style,"page-layout-name"))
        }
        // 使用されない循環も壊れたstyle graphとして拒否する。
        for record in named.values { _ = try resolve(name:record.name,family:record.family) }
    }
    private static func properties(_ node: MarkupNode) -> [String:String] {
        var result: [String:String] = [:]
        for child in node.children where child.namespace == ODF.style && child.name.hasSuffix("-properties") {
            result.merge(child.attributes) { _, new in new }
        }
        return result
    }
    /// masterはdrawing-pageだけに適用する。directPropertiesは最優先。
    public func resolve(name: String? = nil, family: String, part: String = "content.xml", masterPage: String? = nil, directProperties: [String:String] = [:]) throws -> ODPResolvedStyle {
        var values: [String:String] = [:], origins: [String:ODPStyleOrigin] = [:], unresolved: [String] = []
        func apply(_ record: Record, master: String? = nil) {
            for (key,value) in record.properties {
                values[key] = value
                origins[key] = master.map { .init(kind:.master,part:"styles.xml",name:$0) } ?? record.origin
            }
        }
        func chain(_ record: Record, visited: Set<String>, master: String? = nil) throws {
            var seen = visited, records: [Record] = [], current: Record? = record
            while let value = current {
                let key = "\(value.origin.part)|\(value.origin.kind.rawValue)|\(value.family)|\(value.name)"
                guard seen.insert(key).inserted else { throw SlideError.corruptedPackage("ODP styleの循環: \(value.name)") }
                guard records.count < inheritanceLimit else { throw SlideError.limitExceeded("ODP style継承の深さ") }
                records.append(value)
                if let parent = value.parent {
                    current = named[Self.key(family,parent)]
                    if current == nil { unresolved.append("parent:\(family):\(parent)") }
                } else { current = nil }
            }
            for value in records.reversed() { apply(value,master:master) }
        }
        if let record = defaults[family] { apply(record) }
        if let masterPage, family == "drawing-page" {
            if let master = masters[masterPage] {
                if let style = master.style {
                    if let record = automatic["styles.xml|\(Self.key(family,style))"] ?? named[Self.key(family,style)] { try chain(record,visited:[],master:masterPage) }
                    else { unresolved.append("master-style:\(style)") }
                }
            } else { unresolved.append("master:\(masterPage)") }
        }
        if let name {
            if let record = automatic["\(part)|\(Self.key(family,name))"] ?? named[Self.key(family,name)] { try chain(record,visited:[]) }
            else { unresolved.append("style:\(family):\(name)") }
        }
        for (key,value) in directProperties { values[key] = value; origins[key] = .init(kind:.direct,part:part,name:nil) }
        return .init(properties:values,origins:origins,unresolved:unresolved)
    }
    package func direct(name: String?, family: String, part: String = "content.xml") -> [String:String] {
        guard let name else { return [:] }; return automatic["\(part)|\(Self.key(family,name))"]?.properties ?? [:]
    }
    package func pageSize(master: String?) throws -> Size {
        guard let master, let layoutName = masters[master]?.layout, let props = layouts[layoutName],
              let w = props[ODF.key(ODF.fo,"page-width")], let h = props[ODF.key(ODF.fo,"page-height")] else {
            throw SlideError.corruptedPackage("ODPのmaster/page-layout寸法が解決できません")
        }
        let width = try ODF.length(w), height = try ODF.length(h)
        guard width > 0, height > 0 else { throw SlideError.corruptedPackage("不正なODPページ寸法") }
        return .init(width:width,height:height)
    }
}
