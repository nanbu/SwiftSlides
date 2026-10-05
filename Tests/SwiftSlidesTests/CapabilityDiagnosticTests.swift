import Foundation
import Testing
@testable import SlideCore
import SwiftSlides

@Test func featureCapabilitiesRequireExactEvidenceScope() throws {
    let pptx = try CodecSet.all.capabilities(for: .pptx)
    let font = pptx.capability(for: "TXT-003", operation: .read, profile: .ooxmlTransitional)
    #expect(font.status == .partial)
    #expect(font.evidence.map(\.test) == ["independentProducerOracle"])
    #expect(font.evidence.first?.fixture == "python-pptx.pptx")
    #expect(font.evidence.first?.fixtureSHA256.count == 64)
    // 詳細宣言のない機能は、形式全体のpartialや別profileから補完しない。
    #expect(pptx.capability(for: "TXT-003", operation: .read, profile: .ooxmlStrict).status == .unverified)
    #expect(pptx.capability(for: "TXT-003", operation: .create, profile: .ooxmlTransitional).status == .unverified)
    #expect(pptx.capability(for: "TXT-003", operation: .read, profile: "futureProfile").status == .unverified)
    #expect(pptx.capability(for: "FUTURE-001", operation: .read, profile: .ooxmlTransitional).evidence.isEmpty)
    let pptm = try CodecSet.all.capabilities(for: .pptm)
    #expect(pptm.capability(for: "TXT-003", operation: .read, profile: .ooxmlTransitional).status == .unverified)
    #expect(pptm.capability(for: "SEC-005", operation: .edit, profile: .ooxmlTransitional).status == .preserveOnly)
    #expect(throws: SlideError.noCodec(.keynote)) { try CodecSet.all.capabilities(for: .keynote) }
    let result = try JSONDecoder().decode(CodecCapabilities.self, from: JSONEncoder().encode(pptx))
    #expect(result == pptx)
}

@Test func legacyCapabilitiesAndWarningsRemainDecodable() throws {
    let oldCapabilities = Data(#"{"format":"pptx","operations":[],"notes":"legacy"}"#.utf8)
    let capabilities = try JSONDecoder().decode(CodecCapabilities.self, from: oldCapabilities)
    #expect(capabilities.features.isEmpty)
    #expect(capabilities[.read] == .unverified)
    let oldWarning = Data(#"{"code":"unsupportedContent","part":"slide.xml","element":"foreign","message":"kept","count":3}"#.utf8)
    let warning = try JSONDecoder().decode(SlideWarning.self, from: oldWarning)
    #expect(warning.feature == nil)
    #expect(warning.slideID == nil)
    #expect(warning.elementID == nil)
    let diagnostic = warning.diagnostic(stage: .read)
    #expect(diagnostic.count == 3)
    #expect(diagnostic.action == .preserved)
    #expect(diagnostic.location.sourceElement == "foreign")
    #expect(diagnostic.location.elementID == nil)
    let future = SlideDiagnostic(code: "future.code", feature: "FUTURE-001", stage: .read, action: .unverified,
                                 location: .init(part: "future.xml", sourceElement: "future"), message: "未検証")
    #expect(try JSONDecoder().decode(SlideDiagnostic.self, from: JSONEncoder().encode(future)) == future)
    #expect(String(decoding: try JSONEncoder().encode(future.code), as: UTF8.self) == #""future.code""#)
}

@Test func ambiguousFeatureDeclarationsRemainUnverified() {
    let row = FeatureCapability(feature: "TXT-001", profile: .ooxmlTransitional, operation: .read, status: .supported)
    let capabilities = CodecCapabilities(format: .pptx, operations: [.read: .supported], features: [row, row])
    let result = capabilities.capability(for: "TXT-001", operation: .read, profile: .ooxmlTransitional)
    #expect(result.status == .unverified)
    #expect(result.evidence.isEmpty)
}

@Test func diagnosticAggregationKeepsDistinctSubjects() {
    let collector = WarningCollector()
    for (feature, slide, element) in [("OBJ-011", "256", "2"), ("OBJ-011", "256", "2"),
                                      ("OBJ-011", "256", "3"), ("OBJ-011", "257", "2"), ("OBJ-009", "256", "2")] {
        collector.add(.unsupportedContent, part: "slide.xml", element: "graphicFrame", message: "原本保持",
                      feature: .init(rawValue: feature), slideID: slide, elementID: element)
    }
    #expect(collector.result.count == 4)
    #expect(collector.result.map(\.count) == [2, 1, 1, 1])
    #expect(collector.result.map { $0.diagnostic(stage: .read).count }.reduce(0, +) == 5)
    // 区切り文字を含む未知名でも別の位置として集約する。
    collector.add(.unsupportedContent, part: "a|b", element: "c", message: "保持")
    collector.add(.unsupportedContent, part: "a", element: "b|c", message: "保持")
    #expect(collector.result.count == 6)
}

@Test func readAndWriteDiagnosticsCarryKnownIdentity() throws {
    let source = try fixture("unknown.pptx")
    let read = try Presentation.read(source)
    #expect(read.diagnostics == read.presentation.readDiagnostics)
    #expect(read.diagnostics.count == read.warnings.count)
    #expect(read.diagnostics.map(\.count) == read.warnings.map(\.count))
    let opaque = try #require(read.diagnostics.first { $0.feature == "OBJ-011" })
    #expect(opaque.stage == .read)
    #expect(opaque.action == .preserved)
    #expect(opaque.location.part == "ppt/slides/slide2.xml")
    #expect(opaque.location.slideID == read.presentation.slides[1].id)
    #expect(opaque.location.elementID == read.presentation.slides[1].elements[0].id)
    #expect(opaque.location.sourceElement == "graphicFrame")
    var presentation = read.presentation
    presentation.slides[0].elements[0].text = .init("更新本文")
    let write = try presentation.encoded()
    let text = try #require(write.diagnostics.first { $0.feature == "TXT-002" })
    #expect(text.stage == .write)
    #expect(text.action == .rewritten)
    #expect(text.location.slideID == presentation.slides[0].id)
    #expect(text.location.elementID == presentation.slides[0].elements[0].id)
    #expect(text.location.sourceElement == "txBody")
    #expect(write.diagnostics.map(\.count) == write.warnings.map(\.count))
    #expect(throws: SlideError.self) { try presentation.encoded(options: .init(strict: true)) }
    #expect(try read.presentation.encoded().diagnostics.isEmpty)
    #expect(try read.presentation.data() == source)
}

@Test func diagnosticFeatureDoesNotGuessForeignNamespaceOrMessages() throws {
    let data = try changedFixture { parts in
        let path = "ppt/slides/slide1.xml"
        parts[path] = Data(String(decoding: parts[path]!, as: UTF8.self)
            .replacingOccurrences(of: "</p:sld>", with: "<u:timing xmlns:u=\"urn:fictional:extension\"/><p:timing/><p:transition/></p:sld>").utf8)
    }
    let result = try Presentation.read(data)
    let diagnostic = try #require(result.diagnostics.first { $0.location.sourceElement == "timing" })
    #expect(diagnostic.feature == nil)
    let timing = try #require(result.diagnostics.first { $0.feature == "ANI-005" })
    #expect(timing.action == .preserved)
    #expect(timing.location.slideID == result.presentation.slides[0].id)
    #expect(result.diagnostics.contains { $0.feature == "ANI-001" && $0.location.sourceElement == "transition" })
    let warning = SlideWarning(code: .unsupportedPart, part: "foreign.xml", element: "signature", message: "署名は検証しません")
    #expect(warning.diagnostic(stage: .read).action == .preserved)
    #expect(warning.diagnostic(stage: .read).feature == nil)
}

@Test func signatureMacrosAndOmissionHaveDistinctActions() throws {
    let signed = try changedFixture { $0["_xmlsignatures/sig1.xml"] = Data("fake signature".utf8) }
    let signature = try #require(Presentation.read(signed).diagnostics.first { $0.feature == "SEC-006" })
    #expect(signature.action == .unverified)
    let macro = try #require(Presentation.read(fixture("macro.pptm")).diagnostics.first { $0.feature == "SEC-005" })
    #expect(macro.action == .preserved)
    let omitted = try Presentation.read(fixture(), options: .init(includeNotes: false))
    let note = try #require(omitted.diagnostics.first { $0.code.rawValue == "notesOmitted" })
    #expect(note.action == .omitted)
    #expect(note.location.slideID == omitted.presentation.slides[0].id)
}
