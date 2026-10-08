import Foundation
import SlideCore

/// 旧Keynote XMLとOpenOffice Impress XMLの読取専用codec。
package struct LegacyXMLCodec: SlideReadingCodec {
    package let format: PresentationFormat
    package init(format: PresentationFormat) throws { guard [.keynoteLegacy, .sxi].contains(format) else { throw SlideError.invalidModel("旧XML codec形式") }; self.format = format }
    package var capabilities: CodecCapabilities { .init(format: format, operations: [.inspect: .partial, .read: .partial, .create: .unsupported, .edit: .unsupported, .preserve: .preserveOnly, .convert: .unsupported, .render: .unsupported, .play: .unsupported], notes: "旧XMLの文書順・文字・原本構造。高度書式/参照は原本に保持", features: LegacyFeatureCapabilities.features(for: format)) }
    package func openSlides(_ data: Data, options: ReadOptions) throws -> any PresentationSlideSource { try LegacyXMLSource(data, format: format, options: options) }
    package func inspect(_ data: Data, options: InspectOptions) throws -> PresentationSummary { try LegacyXMLSource(data, format: format, options: .init(limits: options.limits)).summary }
    package func read(_ data: Data, options: ReadOptions) throws -> ReadResult { try LegacyXMLSource(data, format: format, options: options).read() }
    package func write(_ presentation: Presentation, options: WriteOptions) throws -> WriteResult { throw SlideError.unsafeEdit("旧XML codecは読取専用です") }
}
extension Codec {
    public static let keynoteLegacy = Codec(try! LegacyXMLCodec(format: .keynoteLegacy))
    public static let sxi = Codec(try! LegacyXMLCodec(format: .sxi))
}
private struct LegacyXMLSource: PresentationSlideSource {
    let data: Data, archive: PackageArchive, options: ReadOptions, format: PresentationFormat, summary: PresentationSummary, main: String
    let pages: [SourceXMLNode], descriptors: [SlideDescriptor]
    var slideDescriptors: [SlideDescriptor] { descriptors }
    private static let key = "http://developer.apple.com/namespaces/keynote2"
    private static let sf = "http://developer.apple.com/namespaces/sf"
    private static let oldOffice = "http://openoffice.org/2000/office"
    init(_ data: Data, format: PresentationFormat, options: ReadOptions) throws {
        let archive: PackageArchive
        if data.starts(with: [0x50, 0x4b]) { archive = try PackageArchive(data, limits: options.limits) }
        else { archive = try PackageArchive(ZIPWriter.write(["index.apxl": LegacyXMLInput.decode(data, limits: options.limits)], compress: false), limits: options.limits) }
        let main: String
        if format == .sxi { main = "content.xml" }
        else { guard let path = LegacyXMLInput.paths.first(where: { archive.entries[$0] != nil }) else { throw SlideError.unknownFormat }; main = path }
        let root = try MarkupNode.parse(LegacyXMLInput.decode(archive.read(main), limits: options.limits), part: main, limits: options.limits)
        let nodes: [MarkupNode], size: Size
        if format == .sxi {
            guard root.namespace == Self.oldOffice, root.name == "document-content", root.attributes[Self.oldOffice + "|class"] == "presentation" else { throw SlideError.unknownFormat }
            guard let body = root.child("body", ns: Self.oldOffice) else { throw SlideError.corruptedPackage("SXI body不在") }
            nodes = body.children.filter { $0.namespace == "http://openoffice.org/2000/drawing" && $0.name == "page" }
            let styles = try MarkupNode.parse(archive.read("styles.xml"), part: "styles.xml", limits: options.limits)
            let props = styles.descendants("properties", ns: "http://openoffice.org/2000/style").first { $0.attributes["http://www.w3.org/1999/XSL/Format|page-width"] != nil }
            guard let props, let w = props.attributes["http://www.w3.org/1999/XSL/Format|page-width"], let h = props.attributes["http://www.w3.org/1999/XSL/Format|page-height"] else { throw SlideError.corruptedPackage("SXI page寸法不在") }
            size = try .init(width: Self.length(w), height: Self.length(h))
        } else {
            guard LegacyXMLInput.isKeynote(root) else { throw SlideError.unknownFormat }
            let list = root.child("slide-list", ns: root.namespace) ?? root.child("slides", ns: root.namespace)
            guard let list else { throw SlideError.corruptedPackage("旧Keynote slide-list不在") }
            nodes = list.children.filter { $0.name == "slide" && $0.namespace == root.namespace }
            if let s = root.child("size", ns: Self.key), let w = s.attributes[Self.sf + "|w"] ?? s.attr("width"), let h = s.attributes[Self.sf + "|h"] ?? s.attr("height"), let width = Double(w), let height = Double(h) { size = .init(width: width, height: height) }
            else if let w = root.attr("width"), let h = root.attr("height"), let width = Double(w), let height = Double(h) { size = .init(width: width, height: height) }
            else { throw SlideError.corruptedPackage("旧Keynote slide寸法不在") }
        }
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { throw SlideError.corruptedPackage("旧XML slide寸法") }
        var ids = Set<String>(), descriptors: [SlideDescriptor] = []
        for (i, node) in nodes.enumerated() { let id = node.attributes["http://developer.apple.com/namespaces/sfa|ID"] ?? node.attr("id") ?? "legacy-\(i + 1)"; guard ids.insert(id).inserted else { throw SlideError.corruptedPackage("旧XML slide ID重複") }; descriptors.append(.init(id: id, name: node.attr("name") ?? "", index: i)) }
        let parts = archive.paths.map { let e = archive.entries[$0]!; return PackagePart(path: $0, contentType: nil, compressedSize: e.compressedSize, expandedSize: e.expandedSize) }
        self.data = data; self.archive = archive; self.options = options; self.format = format; self.main = main; self.pages = try nodes.map(SourceXMLNode.init); self.descriptors = descriptors
        summary = .init(format: format, size: size, slideCount: nodes.count, metadata: .init(), parts: parts)
    }
    private static func length(_ raw: String) throws -> Double { let units: [(String, Double)] = [("cm", 72 / 2.54), ("mm", 72 / 25.4), ("in", 72), ("pt", 1)]; for (unit, scale) in units where raw.hasSuffix(unit) { guard let n = Double(raw.dropLast(unit.count)), n.isFinite else { break }; return n * scale }; throw SlideError.corruptedPackage("SXI長さ") }
    func slide(at index: Int) throws -> SlideReadResult {
        guard pages.indices.contains(index) else { throw SlideError.invalidModel("旧XML slide index") }
        let page = pages[index]; var elements: [Element] = [], noteTexts: [String] = [], textBytes = 0
        func visit(_ node: SourceXMLNode) throws {
            try Task.checkCancellation()
            if ["notes", "speaker-notes"].contains(node.name) {
                if options.includesNotes {
                    let text = node.descendants(named: "p").map(\.text).joined(separator: "\n")
                    guard text.utf8.count <= options.limits.maxExpandedBytes - textBytes else { throw SlideError.limitExceeded("旧XML notes予算") }; textBytes += text.utf8.count; noteTexts.append(text)
                }
                return
            }
            if node.name == "p", [Self.sf, "http://openoffice.org/2000/text"].contains(node.namespace) || node.name == "content" && node.namespace.isEmpty {
                guard node.text.utf8.count <= options.limits.maxExpandedBytes - textBytes else { throw SlideError.limitExceeded("旧XML文字予算") }; textBytes += node.text.utf8.count
                var e = Element(id: "text-\(elements.count)", kind: .opaque, geometry: nil, text: .init(node.text)); e.sourceProperties = node; elements.append(e); return
            }
            for child in node.children { try visit(child) }
        }
        try visit(page)
        var original = Element(id: "legacy-page-source", kind: .opaque, geometry: nil)
        original.sourceProperties = page; elements.append(original)
        let slide = Slide(id: descriptors[index].id, name: descriptors[index].name, elements: elements, notes: noteTexts.isEmpty ? nil : .init(noteTexts.joined(separator: "\n")))
        return .init(slide: slide, warnings: [.init(code: .unsupportedContent, part: main, element: "legacyXML", message: "旧XMLの高度書式・画像・参照・時間構造は原本に保持します", slideID: slide.id)])
    }
    func asset(at path: String) throws -> Data { try archive.read(path) }
    func read() throws -> ReadResult {
        var slides: [Slide] = [], warnings: [SlideWarning] = [], count = 0
        for index in pages.indices { let r = try slide(at: index); count += r.slide.plainText.utf8.count; guard count <= options.limits.maxExpandedBytes else { throw SlideError.limitExceeded("旧XML全文字予算") }; slides.append(r.slide); warnings += r.warnings }
        var p = Presentation(size: summary.size, slides: slides)
        p.preserve(.init(data: data, archive: archive, mainPart: main, limits: options.limits, originalSize: p.size, originalSlides: slides, originalMetadata: p.metadata, originalTheme: p.theme, slidePaths: Dictionary(uniqueKeysWithValues: slides.map { ($0.id, main) }), notesPaths: [:], notesOmitted: !options.includesNotes), format: format, warnings: warnings, parts: summary.parts, themes: [])
        return .init(presentation: p)
    }
}
