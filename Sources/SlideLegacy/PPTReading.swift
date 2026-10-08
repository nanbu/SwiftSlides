import Foundation
import SlideCore

/// MS-PPTのCurrentUser→UserEdit→PersistDirectoryをたどる読取専用codec。
package struct PPTLegacyCodec: SlideReadingCodec {
    package let format = PresentationFormat.ppt
    package init() {}
    package var capabilities: CodecCapabilities { .init(format: format, operations: [.inspect: .partial, .read: .partial, .create: .unsupported, .edit: .unsupported, .preserve: .preserveOnly, .convert: .unsupported, .render: .unsupported, .play: .unsupported], notes: "現行persist directoryと文書順のslide/text。未知record・描画・書式は原本に保持", features: LegacyFeatureCapabilities.features(for: format)) }
    package func openSlides(_ data: Data, options: ReadOptions) throws -> any PresentationSlideSource { try LegacyPPTSource(data, options: options) }
    package func read(_ data: Data, options: ReadOptions) throws -> ReadResult { try LegacyPPTSource(data, options: options).read() }
    package func inspect(_ data: Data, options: InspectOptions) throws -> PresentationSummary { try LegacyPPTSource(data, options: .init(limits: options.limits)).summary }
    package func write(_ presentation: Presentation, options: WriteOptions) throws -> WriteResult { throw SlideError.unsafeEdit("旧PPTは読取専用です") }
}
extension Codec { public static let ppt = Codec(PPTLegacyCodec()) }

private struct PPTRecord {
    let type: UInt16, instance: UInt16, version: UInt16, offset: Int, payload: Range<Int>
}
private struct LegacyPPTSource: PresentationSlideSource {
    let data: Data, stream: Data, current: Data, options: ReadOptions, summary: PresentationSummary
    let slides: [(id: String, record: PPTRecord, texts: [String])]
    var slideDescriptors: [SlideDescriptor] { slides.enumerated().map { .init(id: $0.element.id, index: $0.offset) } }
    init(_ data: Data, options: ReadOptions) throws {
        let compound = try CompoundFile(data: data, limits: options.limits), stream = try compound.stream("PowerPoint Document"), current = try compound.stream("Current User")
        let b = [UInt8](stream), user = [UInt8](current)
        guard user.count >= 28, LE.u16(user, 2) == 4086 else { throw SlideError.corruptedPackage("PPT CurrentUserAtom") }
        guard LE.u32(user, 12) == 0xE391C05F else { throw SlideError.unsupportedEncryption(detail: "旧PPTの暗号化") }
        func record(_ offset: Int) throws -> PPTRecord {
            guard offset >= 0, offset <= b.count - 8 else { throw SlideError.corruptedPackage("PPT record header範囲") }
            let size = Int(LE.u32(b, offset + 4)); guard size <= b.count - offset - 8 else { throw SlideError.corruptedPackage("PPT record payload切断") }
            let vi = LE.u16(b, offset); return .init(type: LE.u16(b, offset + 2), instance: vi >> 4, version: vi & 15, offset: offset, payload: offset + 8..<offset + 8 + size)
        }
        var persist: [UInt32: Int] = [:], edit = Int(LE.u32(user, 16)), seen = Set<Int>(), documentID: UInt32?
        while edit != 0 {
            try Task.checkCancellation(); guard seen.insert(edit).inserted, seen.count <= options.limits.maxEntries else { throw SlideError.corruptedPackage("PPT UserEdit循環/予算") }
            let e = try record(edit); guard e.type == 4085, e.payload.count >= 28 else { throw SlideError.corruptedPackage("PPT UserEditAtom") }
            let p = e.payload.lowerBound
            if documentID == nil { documentID = LE.u32(b, p + 16) }
            if e.payload.count >= 32 { throw SlideError.unsupportedEncryption(detail: "PPT encryption persist情報") }
            let directory = try record(Int(LE.u32(b, p + 12))); guard directory.type == 6002 else { throw SlideError.corruptedPackage("PPT PersistDirectoryAtom") }
            var localIDs = Set<UInt32>()
            var i = directory.payload.lowerBound
            while i < directory.payload.upperBound {
                guard i + 4 <= directory.payload.upperBound else { throw SlideError.corruptedPackage("PPT persist header切断") }
                let packed = LE.u32(b, i), count = Int(packed >> 20), start = packed & 0xfffff; i += 4
                guard count > 0, count <= (directory.payload.upperBound - i) / 4, UInt64(start) + UInt64(count) <= 0x100000 else { throw SlideError.corruptedPackage("PPT persist entry範囲") }
                for n in 0..<count { let id = start + UInt32(n), offset = Int(LE.u32(b, i)); guard id > 0, localIDs.insert(id).inserted else { throw SlideError.corruptedPackage("PPT persist ID重複/0") }; _ = try record(offset); if persist[id] == nil { persist[id] = offset }; i += 4 }
                guard persist.count <= options.limits.maxEntries else { throw SlideError.limitExceeded("PPT persist数") }
            }
            edit = Int(LE.u32(b, p + 8))
        }
        guard let documentID, let docOffset = persist[documentID] else { throw SlideError.corruptedPackage("PPT document persist不在") }
        let doc = try record(docOffset); guard doc.type == 1000, doc.version == 15 else { throw SlideError.corruptedPackage("PPT DocumentContainer") }
        func children(_ record: PPTRecord) throws -> [PPTRecord] { var i = record.payload.lowerBound, records: [PPTRecord] = []; while i < record.payload.upperBound { let r = try selfRecord(i); guard r.payload.upperBound <= record.payload.upperBound else { throw SlideError.corruptedPackage("PPT container境界") }; records.append(r); i = r.payload.upperBound; guard records.count <= options.limits.maxXMLNodes else { throw SlideError.limitExceeded("PPT record数") } }; return records }
        func selfRecord(_ i: Int) throws -> PPTRecord { try record(i) }
        var size: Size?, result: [(String, PPTRecord, [String])] = [], ids = Set<String>(), totalText = 0
        for child in try children(doc) {
            if child.type == 1001 { guard child.payload.count >= 8 else { throw SlideError.corruptedPackage("PPT DocumentAtom切断") }; let p = child.payload.lowerBound; let w = Double(Int32(bitPattern: LE.u32(b, p))) / 8, h = Double(Int32(bitPattern: LE.u32(b, p + 4))) / 8; guard w > 0, h > 0 else { throw SlideError.corruptedPackage("PPT slide寸法") }; size = .init(width: w, height: h) }
            if child.type == 4080, child.instance == 0 {
                var active: Int?
                for r in try children(child) {
                    if r.type == 1011 {
                        guard r.payload.count >= 20 else { throw SlideError.corruptedPackage("PPT SlidePersistAtom切断") }
                        let pid = LE.u32(b, r.payload.lowerBound), id = String(LE.u32(b, r.payload.lowerBound + 12)); guard let offset = persist[pid], ids.insert(id).inserted else { throw SlideError.corruptedPackage("PPT slide persist/ID") }
                        let slide = try record(offset); guard slide.type == 1006 else { throw SlideError.corruptedPackage("PPT SlideContainer") }; result.append((id, slide, [])); active = result.count - 1
                    } else if [4000, 4008].contains(r.type), let active {
                        let text = try Self.text(r, bytes: b); guard text.utf8.count <= options.limits.maxExpandedBytes - totalText else { throw SlideError.limitExceeded("PPT文字予算") }; totalText += text.utf8.count; result[active].2.append(text)
                    }
                }
            }
        }
        guard let size else { throw SlideError.corruptedPackage("PPT document寸法不在") }
        self.data = data; self.stream = stream; self.current = current; self.options = options; slides = result
        summary = .init(format: .ppt, size: size, slideCount: result.count, metadata: .init(), parts: [.init(path: "original.ppt", contentType: "application/vnd.ms-powerpoint", compressedSize: data.count, expandedSize: data.count)])
    }
    private static func text(_ record: PPTRecord, bytes: [UInt8]) throws -> String {
        let data = Data(bytes[record.payload]); let text: String?
        if record.type == 4000 { guard data.count.isMultiple(of: 2) else { throw SlideError.corruptedPackage("PPT UTF16切断") }; text = String(data: data, encoding: .utf16LittleEndian) }
        else { text = String(data: data, encoding: .windowsCP1252) }
        guard let text else { throw SlideError.corruptedPackage("PPT文字のencoding") }; return text.replacingOccurrences(of: "\r", with: "\n")
    }
    func slide(at index: Int) throws -> SlideReadResult {
        guard slides.indices.contains(index) else { throw SlideError.invalidModel("PPT slide index") }
        let s = slides[index], b = [UInt8](stream); var inline: [String] = [], count = 0
        func visit(_ range: Range<Int>, depth: Int) throws {
            guard depth < options.limits.maxXMLDepth else { throw SlideError.limitExceeded("PPT container深さ") }; var i = range.lowerBound
            while i < range.upperBound {
                try Task.checkCancellation(); count += 1; guard count <= options.limits.maxXMLNodes, i + 8 <= range.upperBound else { throw SlideError.corruptedPackage("PPT child record切断/予算") }
                let size = Int(LE.u32(b, i + 4)), vi = LE.u16(b, i); guard size <= range.upperBound - i - 8 else { throw SlideError.corruptedPackage("PPT child payload切断") }
                let r = PPTRecord(type: LE.u16(b, i + 2), instance: vi >> 4, version: vi & 15, offset: i, payload: i + 8..<i + 8 + size)
                if r.version == 15 { try visit(r.payload, depth: depth + 1) } else if [4000, 4008].contains(r.type) { inline.append(try Self.text(r, bytes: b)) }
                i = r.payload.upperBound
            }
        }
        try visit(s.record.payload, depth: 0)
        let texts = s.texts + inline
        guard texts.reduce(0, { $0 + $1.utf8.count }) <= options.limits.maxExpandedBytes else { throw SlideError.limitExceeded("PPT slide文字予算") }
        let slide = Slide(id: s.id, elements: texts.enumerated().map { Element(id: "text-\($0.offset)", kind: .opaque, geometry: nil, text: .init($0.element)) })
        return .init(slide: slide, warnings: [.init(code: .unsupportedContent, part: "PowerPoint Document", element: "record", message: "旧PPTの描画・書式・未知recordは原本に保持します", slideID: s.id)])
    }
    func asset(at path: String) throws -> Data { switch path { case "original.ppt": data; case "PowerPoint Document": stream; case "Current User": current; default: throw SlideError.missingPart(path) } }
    func read() throws -> ReadResult {
        var slides: [Slide] = [], warnings: [SlideWarning] = [], textCount = 0
        for i in self.slides.indices { let r = try slide(at: i); guard r.slide.plainText.utf8.count <= options.limits.maxExpandedBytes - textCount else { throw SlideError.limitExceeded("PPT全文字予算") }; textCount += r.slide.plainText.utf8.count; slides.append(r.slide); warnings += r.warnings }
        var p = Presentation(size: summary.size, slides: slides)
        let archive = try PackageArchive(ZIPWriter.write(["original.ppt": data], compress: false), limits: options.limits)
        p.preserve(.init(data: data, archive: archive, mainPart: "original.ppt", limits: options.limits, originalSize: p.size, originalSlides: slides, originalMetadata: p.metadata, originalTheme: p.theme, slidePaths: [:], notesPaths: [:], notesOmitted: !options.includesNotes), format: .ppt, warnings: warnings, parts: summary.parts, themes: [])
        return .init(presentation: p)
    }
}
