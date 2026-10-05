import Foundation
import Testing
@testable import SlideCore
import SwiftSlides

@Test func createRichPresentation() throws {
    var p = textPresentation(); p.theme.bodyFont.supplementalFamilies["Jpan"] = "Yu Gothic"
    p.slides[0].addShape(.chevron,frame:.init(x:50,y:130,width:150,height:100),fill:.solid(.theme("accent1")),stroke:.init(color:.rgb("112233"),width:2,dash:.dash))
    p.slides[0].addLine(from:(250,200),to:(450,120),stroke:.init(color:.blue,width:3,endArrow:.triangle))
    p.slides[0].addTable(.init(columnWidths:[150,200],rowHeights:[40],rows:[[TableCell("施策"),TableCell("評価")]]),frame:.init(x:40,y:300,width:350,height:40))
    p.slides[0].addImage(.init(data:try fixture("fixture.png"),contentType:"image/png",alternativeText:"Demo"),frame:.init(x:850,y:40,width:20,height:20))
    p.slides[0].notes = .init("Speaker notes")
    let q = try Presentation(data:p.data()); let e = q.slides[0].elements
    #expect(q.slides.count == 1); #expect(e.count == 5); #expect(e[0].text?.plainText == "Hello"); #expect(e[1].geometry == .chevron)
    #expect(e[2].flipVertical); #expect(e[2].stroke?.endArrow == .triangle); #expect(e[2].stroke?.width == 3)
    #expect(e[3].table?.rows[0][1].text.plainText == "評価"); #expect(e[4].image?.alternativeText == "Demo"); #expect(q.slides[0].notes?.plainText == "Speaker notes")
    #expect(q.sourceThemes[0].bodyFont.supplementalFamilies["Jpan"] == "Yu Gothic")
}
@Test(arguments:["python-pptx.pptx","strict.pptx","unknown.pptx","macro.pptm"])
func noOpIsByteIdentical(_ name: String) throws { let data = try fixture(name); #expect(try Presentation(data:data).data() == data) }
@Test func editTextPreservesOtherPartsAndNamespaces() throws {
    let data = try fixture("unknown.pptx"); var p = try Presentation(data:data); p.slides[0].elements[0].text = .init("Changed",style:.init(font:.init(size:24),bold:true))
    let result = try p.encoded(); #expect(result.warnings.contains { $0.code == .rewrittenContent })
    let original = try PackageArchive(data), output = try PackageArchive(result.data)
    for path in original.paths where path != "ppt/slides/slide1.xml" && path != "ppt/slides/_rels/slide1.xml.rels" { #expect(try original.compressedBytes(path) == output.compressedBytes(path)) }
    #expect(try Presentation(data:result.data).slides[0].elements[0].text?.plainText == "Changed")
    let xml = String(decoding:try output.read("ppt/slides/slide1.xml"),as:UTF8.self)
    #expect(xml.contains("mc:Ignorable=\"u\"")); #expect(xml.contains("u:data")); #expect(xml.contains("xmlns:u=\"urn:fictional:extension\""))
    #expect(throws:SlideError.self) { try p.data(options:.init(strict:true)) }
}
@Test func frameEditPreservesRichTextAndChart() throws { var p = try Presentation(data:fixture()); let old = p.slides[0].elements[0].text; p.slides[0].elements[0].frame?.x = 80; let result = try p.encoded(options:.init(strict:true)); #expect(result.warnings.isEmpty); let q = try Presentation(data:result.data); #expect(q.slides[0].elements[0].frame?.x == 80); #expect(q.slides[0].elements[0].text == old); #expect(q.slides[1].elements[0].rawXML?.contains("chart") == true) }
@Test func strictNamespaceEdit() throws { var p = try Presentation(data:fixture("strict.pptx")); p.slides[0].elements[0].frame?.y = 45; let q = try Presentation(data:p.data()); #expect(q.slides[0].elements[0].frame?.y == 45); #expect(q.plainText.contains("売上成長")) }
@Test func reorderAndAddSlides() throws { var p = try Presentation(data:fixture()); p.slides.reverse(); var s = Slide(name:"Added"); s.addText("New",frame:.init(x:20,y:20,width:300,height:80)); p.slides.append(s); let q = try Presentation(data:p.data()); #expect(q.slides.map(\.name) == ["Metrics","Strategy","Added"]); #expect(q.slides[2].plainText == "New") }
@Test func removalKeepsOpaquePartsAndWarns() throws { var p = try Presentation(data:fixture()); p.slides.removeLast(); let result = try p.encoded(); #expect(try Presentation(data:result.data).slides.count == 1); #expect(result.warnings.contains { $0.code == .orphanedParts }); #expect(try parts(result.data)["ppt/slides/slide2.xml"] != nil) }
@Test func groupEditingAndElementReorder() throws { var p = try Presentation(data:fixture()); p.slides[0].elements[6].children[0].frame?.x = 740; p.slides[0].elements.swapAt(0,1); let q = try Presentation(data:p.data()); #expect(q.slides[0].elements[0].name == "Initiative"); #expect(q.slides[0].elements[6].children[0].frame?.x == 740) }
@Test func newGroupCreation() throws { let a = Element(frame:.init(x:0,y:0,width:40,height:40),fill:.solid(.blue)); let g = Element(kind:.group,frame:.init(x:20,y:30,width:200,height:200),geometry:nil,children:[a],childFrame:.init(x:0,y:0,width:100,height:100)); let p = Presentation(slides:[Slide(elements:[g])]); let q = try Presentation(data:p.data()); #expect(q.slides[0].elements[0].children.count == 1); #expect(q.slides[0].elements[0].childFrame?.width == 100) }
@Test func editedImageRetainsPackage() throws { var p = try Presentation(data:fixture()); p.slides[0].elements[5].image = .init(data:try fixture("fixture.png"),contentType:"image/png",alternativeText:"Updated"); let q = try Presentation(data:p.data()); #expect(q.slides[0].elements[5].image?.alternativeText == "Updated") }
@Test func notesAndMetadataEditing() throws { var p = try Presentation(data:fixture()); p.slides[0].notes = .init("Updated notes"); p.metadata.title = "New & <Title>"; let q = try Presentation(data:p.data()); #expect(q.metadata.title == "New & <Title>"); #expect(q.slides[0].notes?.plainText == "Updated notes") }
@Test func duplicateSlideIdentityRefused() throws { var p = textPresentation(); p.slides.append(p.slides[0]); #expect(throws:SlideError.self) { try p.data() } }
@Test func opaqueMutationAndThemeMutationRefused() throws { var p = try Presentation(data:fixture()); p.slides[1].elements[0].frame?.x = 123; #expect(throws:SlideError.self) { try p.data() }; p = try Presentation(data:fixture()); p.theme.name = "Changed"; #expect(throws:SlideError.self) { try p.data() } }
@Test func signedPackageOnlyNoOpAllowed() throws { let d = try changedFixture { $0["_xmlsignatures/sig1.xml"] = Data("fake signature".utf8) }; var p = try Presentation(data:d); #expect(try p.data() == d); p.metadata.title = "Change"; #expect(throws:SlideError.self) { try p.data() } }
@Test func invalidModelsRefused() throws {
    var p = textPresentation(); p.size.width = .nan; #expect(throws:SlideError.self) { try p.data() }
    p = textPresentation(); p.slides[0].elements[0].frame?.width = -1; #expect(throws:SlideError.self) { try p.data() }
    p = textPresentation(); p.slides[0].elements[0].geometry = "UnknownPreset"; #expect(throws:SlideError.self) { try p.data() }
    p = textPresentation(); p.slides[0].elements[0].fill = .solid(.rgb("bad")); #expect(throws:SlideError.self) { try p.data() }
    p = textPresentation(); p.slides[0].elements[0].text = .init("bad\u{01}"); #expect(throws:SlideError.self) { try p.data() }
}
@Test func uncompressedCreationAndAtomicURLWrite() throws { let p = textPresentation(); let data = try p.data(options:.init(compress:false)); #expect(try Presentation(data:data).plainText == "Hello"); let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".pptx"); defer { try? FileManager.default.removeItem(at:url) }; let result = try p.write(to:url); #expect(result.warnings.isEmpty); #expect(try Presentation(contentsOf:url).plainText == "Hello") }

@Test func generatedNotesAndWhitespaceContract() throws {
    var p = textPresentation()
    p.slides[0].elements[0].text = TextBody(paragraphs:[Paragraph(runs:[TextRun("  spaced  ")],endTextStyle:.init(font:.init(size:22),bold:true))])
    p.slides[0].notes = .init("First notes")
    p.slides.append(Slide(name:"Second",notes:.init("Second notes")))
    let data = try p.data(), archive = try PackageArchive(data), q = try Presentation(data:data)
    #expect(q.slides[0].plainText == "  spaced  ")
    #expect(q.slides[0].elements[0].text?.paragraphs[0].endTextStyle.font.size == 22)
    #expect(q.slides[1].notes?.plainText == "Second notes")
    #expect(archive.paths.filter { $0.hasPrefix("ppt/notesMasters/") && $0.hasSuffix(".xml") }.count == 1)
    let main = String(decoding:try archive.read("ppt/presentation.xml"),as:UTF8.self)
    #expect(!main.contains("notesMasterIdLst"))
    let xml = String(decoding:try archive.read("ppt/slides/slide1.xml"),as:UTF8.self)
    #expect(!xml.contains("xml:space"))
}
@Test func editedShapePropertiesUseSchemaOrder() throws {
    var p = try Presentation(data:fixture()); p.slides[0].elements[1].geometry = .ellipse
    p.slides[0].elements[1].fill = .solid(.rgb("112233"))
    let archive = try PackageArchive(p.data())
    let root = try MarkupNode.parse(archive.read("ppt/slides/slide1.xml"),part:"test",limits:.init())
    let props = try #require(root.child("cSld")?.child("spTree")?.named("sp")[1].child("spPr"))
    let names = props.children.map(\.name)
    #expect(try #require(names.firstIndex(of:"prstGeom")) < #require(names.firstIndex(of:"solidFill")))
    #expect(try #require(names.firstIndex(of:"solidFill")) < #require(names.firstIndex(of:"ln")))
}
@Test func deletionOfAnimationTargetRefused() throws {
    let data = try changedFixture { parts in
        var xml = String(decoding:parts["ppt/slides/slide1.xml"]!,as:UTF8.self)
        xml = xml.replacingOccurrences(of:"</p:sld>",with:"<p:timing><p:tnLst><p:par><p:cTn id=\"1\"><p:childTnLst><p:set><p:cBhvr><p:cTn id=\"2\"/><p:tgtEl><p:spTgt spid=\"2\"/></p:tgtEl></p:cBhvr></p:set></p:childTnLst></p:cTn></p:par></p:tnLst></p:timing></p:sld>")
        parts["ppt/slides/slide1.xml"] = Data(xml.utf8)
    }
    var p = try Presentation(data:data); p.slides[0].elements.removeFirst()
    #expect(throws:SlideError.self) { try p.data() }
}
@Test func newMergedTableRefused() throws {
    var p = textPresentation(); var cell = TableCell("Merged"); cell.columnSpan = 2
    p.slides[0].addTable(.init(columnWidths:[50,50],rowHeights:[30],rows:[[cell,TableCell("")]]),frame:.init(x:0,y:0,width:100,height:30))
    #expect(throws:SlideError.self) { try p.data() }
}
@Test func libreOfficeFixtureReadAndFrameEdit() throws {
    var p = try Presentation(data:fixture("libreoffice.pptx"))
    #expect(p.slides.count == 2); #expect(p.plainText.contains("売上成長"))
    p.slides[0].elements[0].frame?.x = 65
    #expect(try Presentation(data:p.data()).slides[0].elements[0].frame?.x == 65)
}

@Test func addedNotesUseExistingMasterPlaceholderIndex() throws {
    let data = try changedFixture("libreoffice.pptx") { parts in
        let path = "ppt/slides/_rels/slide2.xml.rels"
        let root = try MarkupNode.parse(parts[path]!,part:path,limits:.init())
        root.content.removeAll { if case .node(let n) = $0 { n.attr("Type")?.hasSuffix("/notesSlide") == true } else { false } }
        parts[path] = Data(root.xml.utf8)
    }
    var p = try Presentation(data:data); p.slides[1].notes = .init("Added notes")
    let output = try p.data(), q = try Presentation(data:output), archive = try PackageArchive(output)
    #expect(q.slides[1].notes?.plainText == "Added notes")
    let notePath = try #require(q.storage?.notesPaths[q.slides[1].id])
    let root = try MarkupNode.parse(archive.read(notePath),part:notePath,limits:.init())
    #expect(root.descendants("ph").first { $0.attr("type") == "body" }?.attr("idx") == "0")
}
