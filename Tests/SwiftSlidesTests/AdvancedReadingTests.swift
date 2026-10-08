import Foundation
import Testing
@testable import SlideCore
import SwiftSlides

private let advancedFixtures = ["advanced-reading.pptx", "advanced-reading-strict.pptx"]

@Test(arguments: advancedFixtures)
func advancedFillsCropAndCellBorders(_ name: String) throws {
    let p = try Presentation(data:fixture(name)), slide = p.slides[0]
    let e = try #require(slide.elements.first { $0.name == "Gradient" })
    guard case .gradient(let gradient) = e.fill else { Issue.record("gradient missing"); return }
    #expect(gradient.stops.map(\.position) == [0,0.75,1])
    #expect(gradient.stops[0].color == .rgb("FF0000"))
    #expect(gradient.angle == 90 && gradient.scaled == false && gradient.rotateWithShape == false)
    #expect(gradient.flip == "x" && gradient.rawXML.contains("gsLst"))
    guard case .pattern(let pattern) = slide.elements.first(where: { $0.name == "Pattern" })?.fill else { Issue.record("pattern missing"); return }
    #expect(pattern.preset == "pct20" && pattern.foreground == .rgb("123456") && pattern.background == .theme("bg1"))
    guard case .picture(let picture) = slide.elements.first(where: { $0.name == "Picture fill" })?.fill else { Issue.record("picture fill missing"); return }
    #expect(picture.image?.path == "ppt/media/image1.png" && picture.image?.externalTarget == nil && picture.isTiled)
    #expect(picture.crop?.left == 0.1 && picture.crop?.top == -0.05)
    #expect(try p.asset(at:#require(picture.image?.path)) == fixture("fixture.png"))
    let crop = try #require(slide.elements.first { $0.kind == .image }?.image?.crop)
    #expect(crop.left == 0.125 && crop.right == 0.25 && crop.top == -0.01 && crop.bottom == 0)
    let cell = try #require(slide.elements.first { $0.table != nil }?.table?.rows[0][0])
    #expect(cell.borders?.map(\.edge) == [.left,.right,.top,.bottom,.topLeftToBottomRight])
    #expect(cell.borders?.first { $0.edge == .right }?.stroke?.width == 2)
    #expect(cell.borders?.first { $0.edge == .top }?.isExplicitlyNone == true)
    #expect(cell.borders?.first { $0.edge == .top }?.stroke == nil)
    #expect(try p.data() == fixture(name))
}

@Test(arguments: advancedFixtures)
func transitionsTimingMediaAndComments(_ name: String) throws {
    let p = try Presentation(data:fixture(name)), slide = p.slides[0]
    let transition = try #require(slide.transition)
    #expect(transition.effect == "push" && transition.speed == "slow")
    #expect(transition.advanceOnClick == false && transition.advanceAfterMilliseconds == 1500 && transition.durationMilliseconds == 750)
    let timing = try #require(slide.timing)
    #expect(timing.targetElementIDs == ["30"])
    let rootTime = try #require(timing.root.children.first?.children.first?.children.first)
    #expect(rootTime.name == "cTn" && rootTime.attributes["dur"] == "indefinite")
    #expect(timing.rawXML.contains("onClick") && timing.rawXML.contains("bldP"))
    let poster = try #require(slide.elements.first { $0.name == "Audio poster" })
    #expect(poster.media?.map(\.kind) == [.audio,.media])
    #expect(poster.media?.allSatisfy { $0.reference.path == "ppt/media/fictional.wav" && $0.contentType == "audio/wav" } == true)
    #expect(try p.asset(at:"ppt/media/fictional.wav").prefix(4) == Data("RIFF".utf8))
    #expect(poster.nativeFeatures?.contains { $0.namespace.contains("drawingml") && $0.name == "audioFile" } == true)
    let comment = try #require(slide.comments?.first)
    #expect(comment.text == "Fictional review comment" && comment.authorName == "Fictional Reviewer" && comment.authorInitials == "FR")
    #expect(comment.authorID == "7" && comment.id == "1" && comment.dateTime == "2026-01-01T12:00:00Z")
    #expect(comment.x == 100 && comment.y == 50)
    #expect(slide.nativeFeatures?.contains { $0.part == "ppt/comments/advanced.xml" } == true)
    let reader = try SlideReader(data:fixture(name))
    #expect(try reader.slide(id:reader.slideDescriptors[0].id).slide == slide)
    #expect(p.readDiagnostics.contains { $0.feature == "ANI-005" && $0.location.slideID == slide.id })
}

@Test(arguments: advancedFixtures)
func advancedProjectionPreservesUnrelatedEditsAndRefusesMutations(_ name: String) throws {
    let source = try fixture(name), p = try Presentation(data:source)
    var moved = p; moved.slides[0].elements[0].frame?.x = 72
    let reread = try Presentation(data:moved.data(options:.init(strict:true)))
    #expect(reread.slides[0].transition == p.slides[0].transition && reread.slides[0].timing == p.slides[0].timing)
    #expect(reread.slides[0].comments == p.slides[0].comments)
    #expect(reread.slides[0].elements.first { $0.name == "Gradient" }?.fill == p.slides[0].elements.first { $0.name == "Gradient" }?.fill)
    let mutations: [(inout Presentation) -> Void] = [
        { $0.slides[0].transition?.advanceOnClick = true },
        { $0.slides[0].timing?.targetElementIDs = [] },
        { $0.slides[0].comments?[0].text = "changed" },
        { let i = $0.slides[0].elements.firstIndex { $0.name == "Gradient" }!; $0.slides[0].elements[i].fill = .solid(.white) },
        { let i = $0.slides[0].elements.firstIndex { $0.name == "Pattern" }!; $0.slides[0].elements[i].fill = nil },
        { let i = $0.slides[0].elements.firstIndex { $0.name == "Picture fill" }!; $0.slides[0].elements[i].fill = nil },
        { let i = $0.slides[0].elements.firstIndex { $0.kind == .image }!; $0.slides[0].elements[i].image?.crop?.left = 0 },
        { let i = $0.slides[0].elements.firstIndex { $0.name == "Audio poster" }!; $0.slides[0].elements[i].media = nil },
        { $0.slides[0].nativeFeatures = nil }
    ]
    for mutate in mutations { var candidate = p; mutate(&candidate); #expect(throws:SlideError.self) { try candidate.data() } }
    let shape = try #require(p.slides[0].elements.first { $0.name == "Gradient" })
    #expect(throws:SlideError.self) { try Presentation(slides:[Slide(elements:[shape])]).data() }
}

@Test func tableTextPatchKeepsDistinctBordersAndAdditionalXML() throws {
    let data = try changedFixture("advanced-reading.pptx") { parts in
        let path = "ppt/slides/slide1.xml", root = try MarkupNode.parse(parts[path]!,part:path,limits:.init())
        let properties = try #require(root.descendants("tcPr").first)
        properties.content.append(.node(try MarkupNode.fragment("<a:extLst><a:ext uri=\"urn:fictional:cell\"><u:cellExtra xmlns:u=\"urn:fictional:cell\" flag=\"keep\">Fictional extension</u:cellExtra></a:ext></a:extLst>")))
        parts[path] = Data(root.xml.utf8)
    }
    var p = try Presentation(data:data)
    let i = try #require(p.slides[0].elements.firstIndex { $0.table != nil })
    let before = p.slides[0].elements[i].table!.rows[0][0].borders
    p.slides[0].elements[i].table?.rows[0][0].text = .init("Changed fictional cell")
    let result = try p.encoded(), q = try Presentation(data:result.data)
    #expect(q.slides[0].elements[i].table?.rows[0][0].borders == before)
    #expect(q.slides[0].elements[i].table?.rows[0][0].text.plainText == "Changed fictional cell")
    #expect(q.slides[0].transition == p.slides[0].transition)
    let sourcePart = try #require(parts(result.data)["ppt/slides/slide1.xml"])
    let extra = try #require(MarkupNode.parse(sourcePart,part:"slide1.xml",limits:.init()).descendants("cellExtra",ns:"urn:fictional:cell").first)
    #expect(extra.text == "Fictional extension" && extra.attr("flag") == "keep")
    p.slides[0].elements[i].table?.rows[0][0].borders = nil
    #expect(throws:SlideError.self) { try p.data() }
    for field in ["value","formula"] {
        var candidate = q
        if field == "value" { candidate.slides[0].elements[i].table?.rows[0][0].value = .init(type:"float",lexicalValue:"42") }
        else { candidate.slides[0].elements[i].table?.rows[0][0].formula = "of:=1+1" }
        #expect(throws:SlideError.self) { try candidate.data() }
    }
}

@Test func pptxTableBudgetAppliesAcrossSlidesAndSelectedReader() throws {
    let source = try fixture("advanced-reading.pptx")
    #expect(throws:SlideError.self) { try Presentation(data:source,options:.init(limits:.init(maxTableCells:1))) }
    let reader = try SlideReader(data:source,options:.init(limits:.init(maxTableCells:1)))
    #expect(throws:SlideError.self) { try reader.slide(id:reader.slideDescriptors[0].id) }
    // Two copies are individually within budget; a full document exceeds it.
    var p = Presentation(slides:[Slide()])
    p.slides[0].addTable(.init(columnWidths:[20],rowHeights:[20],rows:[[TableCell("A")]]),frame:.init(x:0,y:0,width:20,height:20))
    var second = p.slides[0]; second.id = "second"; p.slides.append(second)
    let data = try p.data()
    #expect(throws:SlideError.self) { try Presentation(data:data,options:.init(limits:.init(maxTableCells:1))) }
    let selected = try SlideReader(data:data,options:.init(limits:.init(maxTableCells:1)))
    #expect(try selected.slide(id:selected.slideDescriptors[1].id).slide.elements.count == 1)
}

@Test func malformedAdvancedValuesAndMediaReferencesRefused() throws {
    for pair in [("pos=\"75000\"","pos=\"NaN\""),("advTm=\"1500\"","advTm=\"-1\""),("l=\"12500\"","l=\"inf\"")] {
        let data = try changedFixture("advanced-reading.pptx") { parts in
            let path = "ppt/slides/slide1.xml"
            parts[path] = Data(String(decoding:parts[path]!,as:UTF8.self).replacingOccurrences(of:pair.0,with:pair.1).utf8)
        }
        #expect(throws:SlideError.self) { try Presentation(data:data) }
    }
    let data = try changedFixture("advanced-reading.pptx") { parts in
        let path = "ppt/slides/_rels/slide1.xml.rels"
        parts[path] = Data(String(decoding:parts[path]!,as:UTF8.self).replacingOccurrences(of:"relationships/audio",with:"relationships/image").utf8)
    }
    #expect(throws:SlideError.self) { try Presentation(data:data) }
}

@Test func externalPictureFillIsReferencedWithoutFetching() throws {
    let data = try changedFixture("advanced-reading.pptx") { parts in
        let path = "ppt/slides/_rels/slide1.xml.rels", root = try MarkupNode.parse(parts[path]!,part:path,limits:.init())
        let rel = try #require(root.children.first { $0.attr("Id") == "advancedImage" })
        rel.set("Target","https://example.com/fictional.png"); rel.set("TargetMode","External"); parts[path] = Data(root.xml.utf8)
    }
    let p = try Presentation(data:data)
    guard case .picture(let picture) = p.slides[0].elements.first(where: { $0.name == "Picture fill" })?.fill else { Issue.record("missing fill"); return }
    #expect(picture.image?.path == nil && picture.image?.externalTarget == "https://example.com/fictional.png")
    #expect(try p.data() == data)
}

@Test func odpTypedCellsKeepLexicalValuesAndFormulaSeparateFromText() throws {
    let data = try changedFixture("styles.odp") { parts in
        let path = "content.xml"
        let cells = "<table:table-cell office:value-type=\"float\" office:value=\"12.50\" table:formula=\"of:=SUM([.A1:.A2])\"><text:p>Rounded display</text:p></table:table-cell><table:table-cell office:value-type=\"boolean\" office:boolean-value=\"false\"><text:p>No</text:p></table:table-cell>"
        parts[path] = Data(String(decoding:parts[path]!,as:UTF8.self).replacingOccurrences(of:"<table:table-cell><text:p>A</text:p></table:table-cell><table:table-cell><text:p>B</text:p></table:table-cell>",with:cells).utf8)
    }
    let p = try Presentation(data:data), row = try #require(p.slides[0].elements.first { $0.table != nil }?.table?.rows[0])
    #expect(row[0].value?.lexicalValue == "12.50" && row[0].value?.number == 12.5)
    #expect(row[0].formula == "of:=SUM([.A1:.A2])" && row[0].text.plainText == "Rounded display")
    #expect(row[1].value?.boolean == false && row[1].text.plainText == "No")
    #expect(try p.asset(at:"content.xml") == parts(data)["content.xml"])
    #expect(TableCellValue(type:"string",lexicalValue:"123").number == nil)
    #expect(TableCellValue(type:"float",lexicalValue:"NaN").number == nil)
}

@Test func optionalFillDefinitionsAndForeignNamespacesStayExplicit() throws {
    let data = try changedFixture("advanced-reading.pptx") { parts in
        let path = "ppt/slides/slide1.xml", root = try MarkupNode.parse(parts[path]!,part:path,limits:.init())
        let gradient = try #require(root.descendants("gradFill").first)
        gradient.remove(["gsLst","lin"])
        gradient.content.append(.node(try MarkupNode.fragment("<a:path path=\"circle\"><a:fillToRect l=\"20000\"/></a:path>")))
        let picture = try #require(root.descendants("blipFill").first { $0.isA })
        picture.remove(["blip"])
        let pattern = try #require(root.descendants("pattFill").first)
        let foreign = try MarkupNode.fragment("<p:pattFill prst=\"pct20\"/>")
        let owner = try #require(root.descendants("spPr").first { $0.child("pattFill") === pattern })
        owner.replace("pattFill",with:foreign)
        root.content.append(.node(try MarkupNode.parse(Data("<u:timing xmlns:u=\"urn:fictional:extension\"><u:spTgt spid=\"999\"/></u:timing>".utf8),part:path,limits:.init())))
        parts[path] = Data(root.xml.utf8)
    }
    let p = try Presentation(data:data), slide = p.slides[0]
    guard case .gradient(let gradient) = slide.elements.first(where: { $0.name == "Gradient" })?.fill,
          case .picture(let picture) = slide.elements.first(where: { $0.name == "Picture fill" })?.fill else { Issue.record("missing fill"); return }
    #expect(gradient.stops.isEmpty && gradient.angle == nil && gradient.path == "circle" && gradient.rawXML.contains("fillToRect"))
    #expect(picture.image == nil && picture.rawXML.contains("tile"))
    #expect(slide.elements.first { $0.name == "Pattern" }?.fill == nil)
    #expect(slide.elements.first { $0.name == "Pattern" }?.nativeFeatures?.contains { $0.name == "pattFill" && $0.namespace == NS.p } == true)
    #expect(slide.timing?.targetElementIDs == ["30"])
    #expect(slide.nativeFeatures?.contains { $0.name == "timing" && $0.namespace == "urn:fictional:extension" } == true)
    #expect(p.readDiagnostics.contains { $0.message.contains("直接stop") })
    #expect(try p.data() == data)
}

@Test func modernCommentsAndExternalVideoRetainDescriptors() throws {
    let data = try changedFixture("advanced-reading.pptx") { parts in
        let path = "ppt/slides/_rels/slide1.xml.rels", root = try MarkupNode.parse(parts[path]!,part:path,limits:.init())
        let comments = try #require(root.children.first { $0.attr("Id") == "advancedComments" })
        comments.set("Type","http://schemas.microsoft.com/office/2018/10/relationships/comments")
        let audio = try #require(root.children.first { $0.attr("Id") == "advancedAudio" })
        audio.set("Type",NS.r + "/video"); audio.set("Target","https://example.com/fictional.mp4"); audio.set("TargetMode","External")
        parts[path] = Data(root.xml.utf8)
        let slide = "ppt/slides/slide1.xml"
        parts[slide] = Data(String(decoding:parts[slide]!,as:UTF8.self).replacingOccurrences(of:"audioFile",with:"videoFile").utf8)
        parts["ppt/comments/advanced.xml"] = Data("<m:cmLst xmlns:m=\"http://schemas.microsoft.com/office/powerpoint/2018/8/main\"><m:cm id=\"fictional\"><m:text>Fictional modern comment</m:text></m:cm></m:cmLst>".utf8)
    }
    let p = try Presentation(data:data), slide = p.slides[0]
    #expect(slide.comments == nil)
    #expect(slide.nativeFeatures?.contains { $0.part == "ppt/comments/advanced.xml" && $0.xml.contains("Fictional modern comment") } == true)
    let video = try #require(slide.elements.first { $0.name == "Audio poster" }?.media?.first)
    #expect(video.kind == .video && video.reference.path == nil && video.reference.externalTarget == "https://example.com/fictional.mp4")
    #expect(p.readDiagnostics.contains { $0.message.contains("コメント形式") })
    #expect(try p.data() == data)
}

@Test func libreOfficeAdvancedOutputReadsProducerValues() throws {
    let data = try fixture("libreoffice-advanced.pptx"), p = try Presentation(data:data), slide = p.slides[0]
    #expect(p.slides.count == 2 && slide.transition?.effect == "push")
    let gradientElement = try #require(slide.elements.first { $0.name == "Gradient" })
    guard case .gradient(let gradient) = gradientElement.fill else { Issue.record("producer gradient missing"); return }
    #expect(gradient.stops.count == 3 && gradient.angle == 90)
    #expect(slide.timing?.targetElementIDs.contains(gradientElement.id) == true)
    #expect(slide.elements.contains { if case .pattern = $0.fill { true } else { false } })
    #expect(slide.elements.contains { if case .picture = $0.fill { true } else { false } })
    #expect(slide.elements.contains { $0.media?.contains { $0.kind == .audio && $0.reference.path != nil } == true })
    #expect(slide.comments?.first?.text == "Fictional review comment" && slide.comments?.first?.authorName == "Fictional Reviewer")
    #expect(try p.data() == data)
}

@Test func advancedModelPropertiesDecodeWhenAbsentInExistingJSON() throws {
    let source = Slide(id:"old",elements:[Element(id:"element",image:Image(path:"fictional.png"),table:Table(columnWidths:[10],rowHeights:[10],rows:[[TableCell("A")]]))])
    let encoded = try JSONEncoder().encode(source)
    #expect(!String(decoding:encoded,as:UTF8.self).contains("nativeFeatures"))
    let decoded = try JSONDecoder().decode(Slide.self,from:encoded)
    #expect(decoded == source && decoded.transition == nil && decoded.elements[0].image?.crop == nil)
    #expect(decoded.elements[0].table?.rows[0][0].value == nil)
}
