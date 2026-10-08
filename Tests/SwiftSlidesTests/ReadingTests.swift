import Foundation
import Testing
@testable import SlideCore
import SwiftSlides

func fixture(_ name: String = "python-pptx.pptx") throws -> Data { try Data(contentsOf:Bundle.module.url(forResource:name,withExtension:nil,subdirectory:"Fixtures")!) }
func parts(_ data: Data) throws -> [String:Data] { let z = try PackageArchive(data); return try Dictionary(uniqueKeysWithValues:z.paths.filter { !$0.hasSuffix("/") }.map { ($0,try z.read($0)) }) }
func changedFixture(_ name: String = "python-pptx.pptx", _ edit: (inout [String:Data]) throws -> Void) throws -> Data { var p = try parts(fixture(name)); try edit(&p); return try ZIPWriter.write(p,compress:true) }
func textPresentation() -> Presentation { var s = Slide(name:"Proposal"); s.addText("Hello",frame:.init(x:40,y:30,width:400,height:60),style:.init(font:.init(family:"Aptos",size:24,eastAsianFamily:"Yu Gothic"),bold:true)); return Presentation(slides:[s]) }

@Test func independentProducerOracle() throws {
    let p = try Presentation(data:fixture())
    let oracle = try JSONSerialization.jsonObject(with:fixture("producer-oracle.json")) as! [String:Any]
    #expect(p.slides.count == oracle["slides"] as! Int)
    #expect(abs(p.size.width - (oracle["width"] as! Double)) < 0.0001)
    #expect(p.size.height == oracle["height"] as! Double)
    #expect(p.metadata.title == oracle["title"] as? String)
    #expect(p.slides[0].elements[0].text?.plainText == oracle["headline"] as? String)
    let run = try #require(p.slides[0].elements[0].text?.paragraphs[0].runs[0])
    #expect(run.style.font.family == oracle["font"] as? String)
    #expect(run.style.font.size == oracle["font_size"] as? Double)
    #expect(run.style.bold == true); #expect(run.link == .external("https://example.com/strategy"))
    #expect(p.slides[0].elements[0].text?.paragraphs[0].style.alignment == .center)
}
@Test(arguments:["python-pptx.pptx","stored.pptx","zip64.pptx","strict.pptx","relocated.pptx"])
func readContainers(_ name: String) throws { let p = try Presentation(data:fixture(name)); #expect(p.slides.count == 2); #expect(p.plainText.contains("売上成長")); #expect(p.sourceFormat == .pptx) }
@Test func geometryImagesGroupsTablesAndNotes() throws {
    let p = try Presentation(data:fixture()); let e = p.slides[0].elements
    #expect(e[1].geometry == .roundedRectangle); #expect(e[1].frame == .init(x:60,y:140,width:240,height:100)); #expect(e[1].stroke?.width == 2)
    #expect(e[2].kind == .connector); #expect(e[3].geometry == .chevron)
    #expect(e[4].table?.rows[1][2].text.plainText == "作業時間")
    let image = try #require(e[5].image); #expect(try p.asset(at:image.path!).starts(with:[137,80,78,71]))
    #expect(e[6].kind == .group); #expect(e[6].children.count == 2); #expect(e[6].plainText == "A\nB")
    #expect(p.slides[0].notes?.plainText == "架空データの提案資料です。")
}
@Test func themeFontsRead() throws { let p = try Presentation(data:fixture()); #expect(!p.sourceThemes.isEmpty); #expect(p.sourceThemes[0].bodyFont.family != nil); #expect(p.sourceThemes[0].bodyFont.supplementalFamilies["Jpan"] != nil); #expect(p.sourceThemes[0].colors["accent1"] != nil) }
@Test func opaqueChartIsWarnedAndPreserved() throws { let p = try Presentation(data:fixture()); #expect(p.slides[1].elements[0].kind == .opaque); #expect(p.slides[1].elements[0].rawXML?.contains("chart") == true); #expect(p.readWarnings.contains { $0.code == .unsupportedContent }) }
@Test func inspectWithoutSlideParsing() throws { let data = try changedFixture { $0["ppt/slides/slide1.xml"] = Data("broken".utf8) }; #expect(try Presentation.inspect(data).slideCount == 2); #expect(throws:SlideError.self) { try Presentation(data:data) } }
@Test func omittedNotesRetainOriginal() throws { let data = try fixture(); var p = try Presentation(data:data,options:.init(includesNotes:false)); #expect(p.slides[0].notes == nil); #expect(p.readWarnings.contains { $0.code == .notesOmitted }); #expect(try p.write().data == data); p.slides[0].notes = .init("Change"); #expect(throws:SlideError.self) { try p.write().data } }
@Test func odpMarkerWithoutDocumentIsRejected() throws { #expect(try PresentationFormat.detect(fixture("impress.odp")) == .odp); #expect(throws:SlideError.missingPart("META-INF/manifest.xml")) { try Presentation(data:fixture("impress.odp")) } }
@Test func keynoteMarkerIsNotMisidentified() throws { let d = try ZIPWriter.write(["Index/Document.iwa":Data([1,2,3])],compress:false); #expect(throws:SlideError.unknownFormat) { try PresentationFormat.detect(d) } }
@Test func macrosPreserved() throws { let data = try fixture("macro.pptm"); var p = try Presentation(data:data); #expect(p.sourceFormat == .pptm); #expect(p.readWarnings.contains { $0.code == .macrosPreserved }); p.metadata.title = "Updated"; let out = try p.write().data; #expect(try parts(out)["ppt/vbaProject.bin"] == parts(data)["ppt/vbaProject.bin"]); #expect(throws:SlideError.self) { try p.write(as:.pptx).data } }
@Test func simultaneousReads() async throws { let data = try fixture(); let count = try await withThrowingTaskGroup(of:Int.self) { group in for _ in 0..<8 { group.addTask { try Presentation(data:data).slides.count } }; var count = 0; for try await n in group { count += n }; return count }; #expect(count == 16) }
