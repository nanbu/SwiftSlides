import Testing
import SlideCore
import SlidePPTX
import SlideODP

@Test func independentProductsHaveSameFacade() throws { let codecs = CodecSet([.pptx]); var slide = Slide(); slide.addText("Separate modules",frame:.init(x:10,y:10,width:400,height:80)); let result = try codecs.write(Presentation(slides:[slide])); #expect(try codecs.read(result.data).presentation.plainText == "Separate modules") }

@Test func independentProductsSupportAsyncIO() async throws {
    let codecs = CodecSet([.pptx])
    var slide = Slide()
    slide.addText("Async modules", frame: .init(x: 10, y: 10, width: 400, height: 80))
    let encoded = try await codecs.write(Presentation(slides: [slide]))
    let read = try await codecs.read(encoded.data)
    #expect(read.presentation.plainText == "Async modules")
    #expect(read.preservationSummary.hasOriginal)
    let reader = try await codecs.slideReader(encoded.data, format: .pptx)
    #expect(try await reader.slide(id: reader.slideDescriptors[0].id).slide.plainText == "Async modules")
    let plan = try await codecs.planWrite(read.presentation)
    #expect(try await codecs.write(read.presentation, using: plan).data == encoded.data)
    #expect(try codecs.capabilities(for: .pptx)[.play] == .unsupported)
}

@Test func independentProductsExposeDetailedCapabilitiesAndDiagnostics() throws {
    let codecs = CodecSet([.pptx])
    let capabilities = try codecs.capabilities(for: .pptx)
    let feature = capabilities.capability(for: "TXT-003", operation: .read, profile: .ooxmlTransitional)
    #expect(feature.status == .partial)
    #expect(!feature.evidence.isEmpty)
    let diagnostic = SlideWarning(code: .rewrittenContent, part: "slide.xml", element: "txBody", message: "再構成",
                                  feature: "TXT-002", slideID: "256", elementID: "2").diagnostic(stage: .write)
    #expect(diagnostic.feature == "TXT-002")
    #expect(diagnostic.location.elementID == "2")
    #expect(diagnostic.action == .rewritten)
}

@Test func independentProductsExposePlansInventoryAndCloning() throws {
    let codecs = CodecSet([.pptx])
    var slide = Slide(); slide.addText("保存計画", frame: .init(x: 20, y: 20, width: 200, height: 50))
    var p = try codecs.read(codecs.write(Presentation(slides: [slide])).data).presentation
    let transaction = try codecs.transaction(&p) { candidate in
        try candidate.editSlide(id: candidate.slides[0].id) { $0.name = "編集を確定" }
    }
    #expect(transaction.warnings.isEmpty && p.slides[0].name == "編集を確定")
    #expect(try !codecs.inspectPreservation(p).identities.isEmpty)
    try codecs.duplicateSlide(id: p.slides[0].id, in: &p)
    let plan = try codecs.planWrite(p)
    #expect(plan.canSave && plan.profile == .ooxmlTransitional)
    #expect(try codecs.read(codecs.write(p, using: plan).data).presentation.slides.count == 2)
}

@Test func independentODPProductAndReaderStayReadOnly() throws {
    let set = CodecSet([.odp])
    let capabilities = try set.capabilities(for: .odp)
    #expect(try set.capabilities(for:.odp)[.create] == .unsupported)
    #expect(capabilities.capability(for:"TXT-001",operation:.read,profile:.odf13).status == .partial)
    #expect(capabilities.capability(for:"TXT-001",operation:.read,profile:.odf12).status == .unverified)
    #expect(throws:SlideError.self) { try set.write(Presentation(),as:.odp) }
    let bytes = try CodecSet([.pptx]).write(Presentation(slides:[Slide()])).data
    let reader = try SlideReader(data:bytes,codecs:CodecSet([.pptx]))
    #expect(reader.summary.slideCount == 1)
    #expect(try reader.slide(id:reader.slideDescriptors[0].id).slide.elements.isEmpty)
}
