import Foundation
import Testing
@testable import SlideCore
import SwiftSlides

@Test func duplicatePreservesNotesChartAssetsAndLocalReferences() throws {
    let data = try fixture()
    var p = try Presentation(data: data)
    let original = p.slides[0]
    let id = try p.duplicateSlide(id: original.id, at: 1)
    #expect(p.slides[1].id == id && id != original.id)
    #expect(p.slides[1].elements == original.elements)
    let chartID = try p.duplicateSlide(id: p.slides[2].id)
    let output = try p.data(), q = try Presentation(data: output), archive = try PackageArchive(output), oldArchive = try PackageArchive(data)
    #expect(q.slides.count == 4)
    #expect(q.slides[1].notes == original.notes)
    #expect(q.slides[3].elements[0].rawXML == p.slides[3].elements[0].rawXML)
    let clonedChart = try #require(p.slideClones[chartID])
    let chartParts = clonedChart.contentTypes.filter { $0.value.hasSuffix("chart+xml") }.keys
    #expect(chartParts.count == 1)
    #expect(try archive.read(chartParts.first!) == oldArchive.read("ppt/charts/chart1.xml"))
    let workbooks = clonedChart.contentTypes.filter { $0.value == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }.keys
    #expect(workbooks.count == 1)
    #expect(try archive.read(workbooks.first!) == oldArchive.read("ppt/embeddings/Microsoft_Excel_Sheet1.xlsx"))
    let imagePath = try #require(q.slides[0].elements[5].image?.path)
    #expect(q.slides[1].elements[5].image?.path == imagePath)
    #expect(try q.asset(at: imagePath) == p.asset(at: imagePath))
    let originalNote = try #require(q.storage?.notesPaths[q.slides[0].id])
    let clonedNote = try #require(q.storage?.notesPaths[q.slides[1].id])
    #expect(originalNote != clonedNote)
    #expect(try archive.read(originalNote) == archive.read(clonedNote))
    for path in oldArchive.paths where !["ppt/presentation.xml", "ppt/_rels/presentation.xml.rels", "[Content_Types].xml"].contains(path) {
        #expect(try oldArchive.compressedBytes(path) == archive.compressedBytes(path))
    }
    p.slides[1].notes = .init("Independent cloned note")
    #expect(try Presentation(data: p.data()).slides[0].notes == original.notes)
    #expect(try Presentation(data: p.data()).slides[1].notes?.plainText == "Independent cloned note")
}

@Test func importRebasesMasterAssetsAndRequiresSlideLinkMapping() throws {
    var source = try Presentation(data: fixture())
    let linkedSlideID = source.slides[1].id
    source.slides[0].elements[0].text?.paragraphs[0].runs[0].link = .slide(linkedSlideID)
    var destination = textPresentation()
    destination.size = source.size
    let before = destination.slides
    #expect(throws: SlideError.self) { try destination.importSlide(id: source.slides[0].id, from: source) }
    #expect(destination.slides == before && destination.slideClones.isEmpty)
    let id = try destination.importSlide(id: source.slides[0].id, from: source, options: .init(slideLinks: [source.slides[1].id: destination.slides[0].id]))
    let imported = destination.slides.last!
    #expect(imported.id == id)
    let path = try #require(imported.elements[5].image?.path)
    #expect(path != source.slides[0].elements[5].image?.path)
    #expect(try destination.asset(at: path) == source.asset(at: source.slides[0].elements[5].image!.path!))
    let output = try destination.data(), q = try Presentation(data: output), graph = try q.inspectPreservation()
    #expect(q.slides.count == 2 && q.slides[1].plainText.contains("売上成長"))
    #expect(q.slides[1].notes == source.slides[0].notes)
    #expect(q.slides[1].layoutPath != q.slides[0].layoutPath)
    #expect(q.slides[1].elements[0].text?.paragraphs[0].runs[0].link == .slide(q.storage!.slidePaths[q.slides[0].id]!))
    #expect(graph.references.contains { $0.relationshipType == "slideMaster" && $0.targetPart?.contains("ssclone") == true })
    #expect(q.packageParts.filter { $0.contentType?.hasSuffix("notesMaster+xml") == true }.count == 1)
    let stale = try destination.planWrite()
    destination.slides[1].elements[0].frame?.x = 123
    #expect(throws: SlideError.stalePlan) { try destination.encoded(using: stale) }
    #expect(try Presentation(data: destination.data()).slides[1].elements[0].frame?.x == 123)
}

@Test func duplicateSelfLinksAndTimingPreserveIdentityScope() throws {
    var source = textPresentation()
    let selfID = source.slides[0].id
    source.slides[0].elements[0].text?.paragraphs[0].runs[0].link = .slide(selfID)
    let initial = try source.data()
    var pp = try parts(initial)
    pp["ppt/slides/slide1.xml"] = pp["ppt/slides/slide1.xml"]!.replacingUTF8("</p:sld>", "<p:timing><p:tnLst><p:par><p:cTn id=\"1\"><p:childTnLst><p:set><p:cBhvr><p:cTn id=\"2\"/><p:tgtEl><p:spTgt spid=\"2\"/></p:tgtEl></p:cBhvr></p:set></p:childTnLst></p:cTn></p:par></p:tnLst></p:timing></p:sld>")
    var p = try Presentation(data: ZIPWriter.write(pp, compress: true))
    let id = try p.duplicateSlide(id: p.slides[0].id)
    let q = try Presentation(data: p.data())
    #expect(q.slides[1].elements[0].text?.paragraphs[0].runs[0].link == .slide(q.storage!.slidePaths[q.slides[1].id]!))
    #expect(try q.inspectPreservation().references.filter { $0.kind == .timing }.count == 2)
    let clonedIndex = try #require(p.slides.firstIndex { $0.id == id })
    p.slides[clonedIndex].elements.removeFirst()
    #expect(try !p.planWrite().canSave)
}

@Test func cloneRefusesUnknownConflictingMastersAndProfiles() throws {
    var unknown = try Presentation(data: fixture("unknown.pptx"))
    let before = unknown.slides
    #expect(throws: SlideError.self) { try unknown.duplicateSlide(id: unknown.slides[0].id) }
    #expect(unknown.slides == before && unknown.slideClones.isEmpty)
    var source = textPresentation(); source.slides[0].notes = .init("Source notes")
    var destination = try Presentation(data: source.data())
    #expect(throws: SlideError.self) { try destination.importSlide(id: source.slides[0].id, from: source) }
    #expect(destination.slides.count == 1)
    #expect(throws: SlideError.self) { try destination.duplicateSlide(id: destination.slides[0].id, at: 99) }
    #expect(throws: SlideError.self) { try destination.duplicateSlide(id: "missing") }
    let strict = try Presentation(data: fixture("strict.pptx"))
    var target = Presentation(size: strict.size)
    #expect(throws: SlideError.self) { try target.importSlide(id: strict.slides[0].id, from: strict) }
    var dupStrict = strict
    try dupStrict.duplicateSlide(id: strict.slides[0].id)
    #expect(try Presentation(data: dupStrict.data()).slides.count == 3)
    var differentSize = Presentation(size: .standard)
    #expect(throws: SlideError.self) { try differentSize.importSlide(id: source.slides[0].id, from: source) }
    let macro = try Presentation(data: fixture("macro.pptm"))
    #expect(throws: SlideError.self) { try target.importSlide(id: macro.slides[0].id, from: macro) }
}

@Test func stagedCloneLinksCannotSilentlyPointToRemovedSlides() throws {
    var p = textPresentation()
    var second = Slide(); second.addText("Second", frame: .init(x: 0, y: 0, width: 100, height: 50))
    p.slides.append(second)
    p.slides[0].elements[0].text?.paragraphs[0].runs[0].link = .slide(second.id)
    try p.duplicateSlide(id: p.slides[0].id)
    p.slides.remove(at: 1)
    #expect(try !p.planWrite().canSave)
}

@Test func repeatedImportsShareDependenciesAndRetainRemovedCloneAssets() throws {
    let source = try Presentation(data: fixture())
    var target = Presentation(size: source.size)
    let first = try target.importSlide(id: source.slides[0].id, from: source)
    try target.importSlide(id: source.slides[1].id, from: source)
    let output = try target.data(), read = try Presentation(data: output)
    #expect(read.packageParts.filter { $0.contentType?.hasSuffix("notesMaster+xml") == true }.count == 1)
    #expect(read.packageParts.filter { $0.contentType?.hasSuffix("slideMaster+xml") == true }.count == 2)
    let archive = try PackageArchive(output)
    var layoutIDs: [String] = []
    for part in read.packageParts where part.contentType?.hasSuffix("slideMaster+xml") == true {
        layoutIDs += try MarkupNode.parse(archive.read(part.path), part: part.path, limits: .init()).descendants("sldLayoutId").compactMap { $0.attr("id") }
    }
    #expect(Set(layoutIDs).count == layoutIDs.count)
    target.slides.removeAll { $0.id == first }
    #expect(try Presentation(data: target.data()).slides.count == 1)
}

@Test func importPreservesURIFragmentsAndEscapesPartPaths() throws {
    let original = try parts(fixture())
    var data = Dictionary(uniqueKeysWithValues: original.map { key, value in
        (key.hasPrefix("ppt/") ? key.replacingOccurrences(of: "ppt/", with: "space folder/") : key, value)
    })
    data["[Content_Types].xml"] = data["[Content_Types].xml"]!.replacingUTF8("/ppt/", "/space%20folder/")
    data["_rels/.rels"] = data["_rels/.rels"]!.replacingUTF8("ppt/presentation.xml", "space%20folder/presentation.xml")
    let relPath = "space folder/slides/_rels/slide1.xml.rels"
    let rels = try MarkupNode.parse(data[relPath]!, part: relPath, limits: .init())
    let ref = try MarkupNode.parse(Data("<Relationship xmlns=\"\(NS.rels)\" Id=\"fragmentSlide\" Type=\"\(NS.r)/slide\" Target=\"slide1.xml#fictional\"/>".utf8), part: relPath, limits: .init())
    rels.content.append(.node(ref)); data[relPath] = Data(rels.xml.utf8)
    let slidePath = "space folder/slides/slide1.xml"
    let root = try MarkupNode.parse(data[slidePath]!, part: slidePath, limits: .init())
    try #require(root.descendants("hlinkClick").first).setRel("id", "fragmentSlide")
    data[slidePath] = Data(root.xml.utf8)
    let source = try Presentation(data: ZIPWriter.write(data, compress: true))
    var target = Presentation(size: source.size)
    let id = try target.importSlide(id: source.slides[0].id, from: source)
    let clonedPart = try #require(target.slideClones[id]?.slidePath)
    let read = try Presentation(data: target.data())
    let graph = try read.inspectPreservation()
    #expect(graph.references.contains { $0.sourcePart == clonedPart && $0.kind == .relationship && $0.value.hasSuffix("#fictional") && $0.targetPart == clonedPart })
    #expect(graph.references.filter { $0.kind == .relationship && !$0.isExternal }.allSatisfy { !$0.value.contains("space folder") })
    #expect(read.slides[0].elements[5].image?.path?.contains("space folder") == true)
}

@Test func macroDuplicatePreservesVBAAndCloneCancellationIsAtomic() async throws {
    let input = try fixture("macro.pptm")
    var macro = try Presentation(data: input)
    try macro.duplicateSlide(id: macro.slides[0].id)
    let output = try await macro.data()
    let original = try PackageArchive(input), result = try PackageArchive(output)
    for path in original.paths where path.hasSuffix("vbaProject.bin") { #expect(try original.compressedBytes(path) == result.compressedBytes(path)) }
    #expect(try Presentation(data: output).slides.count == 3)
    let p = textPresentation()
    let task = Task {
        var candidate = p
        withUnsafeCurrentTask { $0?.cancel() }
        do { try candidate.duplicateSlide(id: p.slides[0].id); Issue.record("キャンセル済みの複製が成功しました") }
        catch is CancellationError { #expect(candidate.slides == p.slides && candidate.slideClones.isEmpty) }
    }
    try await task.value
}
