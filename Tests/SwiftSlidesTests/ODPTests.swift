import Foundation
import Testing
import SwiftSlides
@testable import SlideCore

private let drawNS = "urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
private let foNS = "urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
@Test func odpStylesResolveDirectNamedAutomaticAndMaster() throws {
    let index = try ODPCodec().styleIndex(fixture("styles.odp"))
    let inherited = try index.resolve(name:"Direct",family:"graphic")
    #expect(inherited.properties[drawNS+"|fill"] == "none")
    #expect(inherited.properties[drawNS+"|fill-color"] == "#123456")
    #expect(inherited.origins[drawNS+"|fill"]?.kind == .automatic)
    #expect(inherited.origins[drawNS+"|fill-color"]?.name == "Base")
    #expect(inherited.properties[foNS+"|font-size"] == "18pt")
    let direct = try index.resolve(name:"Direct",family:"graphic",directProperties:[drawNS+"|fill-color":"#987654"])
    #expect(direct.origins[drawNS+"|fill-color"]?.kind == .direct)
    #expect(direct.properties[drawNS+"|fill-color"] == "#987654")
    let page = try index.resolve(family:"drawing-page",masterPage:"Master")
    #expect(page.properties[drawNS+"|fill-color"] == "#102030")
    #expect(page.origins[drawNS+"|fill-color"]?.kind == .master)
    #expect(try index.resolve(name:"Scoped",family:"graphic").properties[drawNS+"|fill-color"] == "#FEDCBA")
    #expect(try index.resolve(name:"Scoped",family:"graphic",part:"styles.xml").properties[drawNS+"|fill-color"] == "#ABCDEF")
    #expect(try index.resolve(name:"Missing",family:"graphic").unresolved == ["style:graphic:Missing"])
    #expect(try index.resolve(name:"Direct",family:"text").unresolved == ["style:text:Direct"])
}
@Test func odpBasicReadPreservesOriginalAndSeparatesInheritedValues() throws {
    let data = try fixture("styles.odp"), p = try Presentation(data:data)
    #expect(p.sourceFormat == .odp); #expect(p.slides.count == 2); #expect(abs(p.size.width-960) < 0.00001); #expect(p.size.height == 540)
    #expect(p.metadata.title == "Fictional ODP")
    let first = p.slides[0], rect = first.elements[0]
    #expect(rect.text?.plainText == "Hello  世界\tlink\nEnd")
    #expect(rect.fill == Fill.none); #expect(first.background == nil)
    #expect(rect.text?.paragraphs[0].runs[0].style.font.size == nil)
    #expect(rect.text?.paragraphs[0].runs[0].style.bold == true)
    #expect(rect.text?.paragraphs[0].runs.first(where: { $0.text == "世界" })?.style.font.size == 24)
    #expect(rect.text?.paragraphs[0].runs.first(where: { $0.text == "link" })?.link == .external("https://example.com/fictional"))
    #expect(first.elements[1].children[0].kind == .shape)
    #expect(first.elements[2].image?.alternativeText == "Fictional image")
    #expect(try p.asset(at:"Pictures/fixture.png") == fixture("fixture.png"))
    #expect(first.elements[3].table?.rows[0].map { $0.text.plainText } == ["A","B"])
    #expect(first.notes?.plainText == "Fictional notes")
    #expect(p.preservationSummary.originalBytes == data.count)
    #expect(!p.readDiagnostics.isEmpty)
    #expect(throws:SlideError.self) { try p.data() }
    #expect(throws:SlideError.self) { try p.data(as:.pptx) }
    #expect(try p.planWrite().canSave == false)
    #expect(try Presentation.inspect(data).slideCount == 2)
}
@Test func odpUnknownExternalAndNotesOmissionRemainVisible() throws {
    let data = try changedFixture("styles.odp") { parts in
        var xml = String(decoding:parts["content.xml"]!,as:UTF8.self)
        xml = xml.replacingOccurrences(of:"Pictures/fixture.png",with:"https://example.com/external.png")
        xml = xml.replacingOccurrences(of:"<draw:g ",with:"<draw:custom-shape ").replacingOccurrences(of:"</draw:g>",with:"</draw:custom-shape>")
        parts["content.xml"] = Data(xml.utf8)
    }
    let p = try Presentation(data:data,options:.init(includeNotes:false))
    #expect(p.slides[0].elements[1].kind == .opaque); #expect(p.slides[0].elements[2].kind == .opaque)
    #expect(p.slides[0].elements[2].rawXML?.contains("external.png") == true)
    #expect(p.slides[0].notes == nil); #expect(p.readWarnings.contains { $0.code == .notesOmitted })
}
@Test func odpRejectsBrokenReferencesCyclesVersionEncryptionAndRepeatBomb() throws {
    for replacement in [
        ("style:parent-style-name=\"Base\"","style:parent-style-name=\"Named\"","styles.xml"),
        ("office:version=\"1.3\"","office:version=\"9.9\"","content.xml"),
        ("xml:id=\"ellipse-one\"","xml:id=\"rect-one\"","content.xml"),
        ("table:number-columns-repeated=\"2\"","table:number-columns-repeated=\"2000000000\"","content.xml"),
        ("Pictures/fixture.png","Pictures/missing.png","content.xml"),
        ("<draw:rect","<foreign:rect","content.xml")
    ] {
        let data = try changedFixture("styles.odp") { parts in parts[replacement.2] = Data(String(decoding:parts[replacement.2]!,as:UTF8.self).replacingOccurrences(of:replacement.0,with:replacement.1).utf8) }
        #expect(throws:SlideError.self) { try Presentation(data:data) }
    }
    let encrypted = try changedFixture("styles.odp") { parts in
        parts["META-INF/manifest.xml"] = Data(String(decoding:parts["META-INF/manifest.xml"]!,as:UTF8.self).replacingOccurrences(of:"</manifest:manifest>",with:"<manifest:file-entry manifest:full-path=\"Encrypted\" manifest:media-type=\"\"><manifest:encryption-data/></manifest:file-entry></manifest:manifest>").utf8)
    }
    #expect(throws:SlideError.self) { try Presentation(data:encrypted) }
    let missing = try changedFixture("styles.odp") { $0["styles.xml"] = nil }
    #expect(throws:SlideError.self) { try Presentation(data:missing) }
    #expect(throws:SlideError.self) { try Presentation(data:fixture("styles.odp"),options:.init(limits:.init(maxTableCells:1))) }
}
@Test func libreOfficeODPProducerIsReadableWithLocatedWarnings() throws {
    let p = try Presentation(data:fixture("libreoffice.odp"))
    #expect(p.slides.count == 2)
    #expect(p.plainText.contains("売上成長"))
    #expect(p.slides[0].notes?.plainText.contains("架空データ") == true)
    #expect(p.readWarnings.allSatisfy { !$0.part.isEmpty })
    #expect(p.readWarnings.contains { $0.code == .unsupportedContent })
}
@Test func odpRejectsAggregateSpaceExpansionAndDTD() throws {
    let bomb = try changedFixture("styles.odp") { parts in
        let xml = String(decoding:parts["content.xml"]!,as:UTF8.self).replacingOccurrences(of:"<text:p>Second page</text:p>",with:"<text:p><text:s text:c=\"15000\"/></text:p><text:p><text:s text:c=\"15000\"/></text:p>")
        parts["content.xml"] = Data(xml.utf8)
    }
    #expect(throws:SlideError.self) { try Presentation(data:bomb,options:.init(limits:.init(maxPartBytes:20000))) }
    let dtd = try changedFixture("styles.odp") { parts in parts["content.xml"] = Data("<!DOCTYPE root [<!ENTITY x 'value'>]><root/>".utf8) }
    #expect(throws:SlideError.self) { try Presentation(data:dtd) }
}
@Test func odpStyleDepthAndAnonymousIdentityAreBounded() throws {
    let deep = try changedFixture("styles.odp") { parts in
        let chain = (0..<130).map { i in "<style:style style:name=\"Depth\(i)\" style:family=\"graphic\"" + (i > 0 ? " style:parent-style-name=\"Depth\(i-1)\"" : "") + "/>" }.joined()
        parts["styles.xml"] = Data(String(decoding:parts["styles.xml"]!,as:UTF8.self).replacingOccurrences(of:"</office:styles>",with:chain+"</office:styles>").utf8)
    }
    #expect(throws:SlideError.self) { try Presentation(data:deep) }
    let anonymous = try changedFixture("styles.odp") { parts in
        var xml = String(decoding:parts["content.xml"]!,as:UTF8.self)
        xml = xml.replacingOccurrences(of:"xml:id=\"page-one\" draw:id=\"page-one\"",with:"")
        xml = xml.replacingOccurrences(of:"page-two",with:"odf-page-1")
        xml = xml.replacingOccurrences(of:"xml:id=\"rect-one\" draw:id=\"rect-one\"",with:"")
        xml = xml.replacingOccurrences(of:"ellipse-one",with:"odf-element-1")
        parts["content.xml"] = Data(xml.utf8)
    }
    let p = try Presentation(data:anonymous)
    #expect(p.slides[0].id != p.slides[1].id)
    #expect(p.slides[0].elements[0].id != p.slides[0].elements[1].children[0].id)
    #expect(p.slides[0].elements[2].image?.contentType == "image/png")
}
