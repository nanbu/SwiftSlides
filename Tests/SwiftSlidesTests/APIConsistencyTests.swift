import Foundation
import Testing
import SwiftSlides

private struct APIProbeCodec: SlideReadingCodec {
    let format: PresentationFormat
    let marker: String
    func read(_ data: Data, options: ReadOptions) throws -> ReadResult {
        .init(presentation: Presentation(metadata: .init(title: marker, subject: String(options.includesNotes))))
    }
    func inspect(_ data: Data, options: InspectOptions) throws -> PresentationSummary {
        .init(format: format, size: .widescreen, slideCount: 1,
              metadata: .init(title: marker, subject: String(options.limits.maxPartBytes), description: String(Thread.isMainThread)), parts: [])
    }
    func write(_ presentation: Presentation, options: WriteOptions) throws -> WriteResult { .init(data: Data(marker.utf8)) }
    func openSlides(_ data: Data, options: ReadOptions) throws -> any PresentationSlideSource {
        APIProbeSource(summary: try inspect(data, options: .init(limits: options.limits)), marker: marker, includesNotes: options.includesNotes)
    }
}

private struct APIProbeSource: PresentationSlideSource {
    let summary: PresentationSummary
    let marker: String
    let includesNotes: Bool
    var slideDescriptors: [SlideDescriptor] { [.init(id: "probe", index: 0)] }
    func slide(at index: Int) throws -> SlideReadResult { .init(slide: Slide(id: "probe", name: marker, notes: includesNotes ? .init("notes") : nil)) }
    func asset(at path: String) throws -> Data { Data(marker.utf8) }
}

@Test func savePlanRefusesChangedCodecRegistrationButAcceptsSameChoice() throws {
    let first = Codec(APIProbeCodec(format: .keynote, marker: "first"))
    let replacement = Codec(APIProbeCodec(format: .keynote, marker: "replacement"))
    let original = CodecSet([first]), changed = CodecSet([first, replacement])
    let deck = Presentation()
    let plan = try original.planWrite(deck, as: .keynote)
    #expect(plan.canSave)
    #expect(try original.write(deck, using: plan).data == Data("first".utf8))
    #expect(throws: SlideError.stalePlan) { try changed.write(deck, using: plan) }
    let copy = original
    #expect(try copy.write(deck, using: plan).data == Data("first".utf8))
    let sameChoice = CodecSet([try original.codec(for: .keynote)])
    #expect(try sameChoice.write(deck, using: plan).data == Data("first".utf8))
    let builtIn = CodecSet([.pptx]), builtInPlan = try builtIn.planWrite(deck)
    #expect(try CodecSet.all.write(deck, using: builtInPlan).warnings.isEmpty)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".key")
    let sentinel = Data("保持".utf8); try sentinel.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(throws: SlideError.stalePlan) { try changed.write(deck, to: url, using: plan) }
    #expect(try Data(contentsOf: url) == sentinel)
}

@Test func codecRegistrationOrderAndLastImplementationMatchSwiftSheets() throws {
    let set = CodecSet([Codec(APIProbeCodec(format: .keynote, marker: "first")), .pptx,
                        Codec(APIProbeCodec(format: .keynote, marker: "last"))])
    #expect(set.formats == [.keynote, .pptx])
    #expect(set.contains(.keynote) && !set.contains(.odp))
    #expect(try set.codec(for: .keynote).format == .keynote)
    #expect(try set.read(Data(), format: .keynote).presentation.metadata.title == "last")
    #expect(CodecSet([]).formats.isEmpty)
    #expect(throws: SlideError.noCodec(for: .odp)) { try set.codec(for: .odp) }
}

@Test func explicitDataFormatOptionsAndReaderDispatchShareContract() throws {
    let set = CodecSet([Codec(APIProbeCodec(format: .keynote, marker: "explicit"))])
    let options = ReadOptions(limits: .init(maxPartBytes: 73), includesNotes: false)
    #expect(try set.read(Data(), format: .keynote, options: options).presentation.metadata.subject == "false")
    #expect(try set.inspect(Data(), format: .keynote, options: .init(limits: options.limits)).metadata.subject == "73")
    let reader = try set.slideReader(Data(), format: .keynote, options: options)
    #expect(reader.summary.metadata.subject == "73")
    #expect(try reader.slide(id: "probe").slide.notes == nil)
    #expect(try reader.asset(at: "asset") == Data("explicit".utf8))
    #expect(throws: SlideError.slideNotFound(id: "missing")) { try reader.slide(id: "missing") }
    #expect(throws: SlideError.unknownFormat) { try set.inspect(Data()) }
    #expect(throws: SlideError.self) { try Presentation.read(Data(), format: .keynote) }
    #expect(throws: SlideError.self) { try Presentation.inspect(Data(), format: .keynote) }
    #expect(throws: SlideError.self) { try SlideReader(data: Data(), format: .keynote) }

    let bytes = try fixture()
    #expect(try Presentation(data: bytes, format: .pptx, options: .init(includesNotes: false)).slides[0].notes == nil)
    #expect(try Presentation.read(bytes, format: .pptx).presentation.slides.count == 2)
    #expect(try Presentation.inspect(bytes, format: .pptx).slideCount == 2)
    #expect(try SlideReader(data: bytes, format: .pptx, options: .init(includesNotes: false)).slide(id: "256").slide.notes == nil)
    #expect(throws: SlideError.self) { try CodecSet.all.slideReader(bytes, options: options) }
}

@Test func formatExtensionsAndURLWritesRefuseImplicitConversion() throws {
    for format in [PresentationFormat.pptx, .pptm, .odp, .keynote] {
        #expect(PresentationFormat(fileExtension: format.fileExtension.uppercased()) == format)
    }
    #expect(PresentationFormat(fileExtension: "bin") == nil)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let deck = textPresentation(), plan = try deck.planWrite()
    for ext in ["pptm", "odp", "key"] {
        let url = directory.appendingPathComponent("output." + ext)
        let original = Data("既存内容".utf8)
        try original.write(to: url)
        let error = SlideError.outputFormatMismatch(format: .pptx, fileExtension: ext)
        #expect(throws: error) { try deck.write(to: url) }
        #expect(throws: error) { try CodecSet.all.write(deck, to: url, as: .pptx) }
        #expect(throws: error) { try deck.write(to: url, using: plan) }
        #expect(try Data(contentsOf: url) == original)
    }
    let macro = try Presentation(data: fixture("macro.pptm"))
    let mismatched = directory.appendingPathComponent("macro.pptx")
    #expect(throws: SlideError.outputFormatMismatch(format: .pptm, fileExtension: "pptx")) { try macro.write(to: mismatched) }
    #expect(!FileManager.default.fileExists(atPath: mismatched.path))
    for name in ["output.PPTX", "output", "output.bin"] {
        let url = directory.appendingPathComponent(name)
        let result = try deck.write(to: url)
        #expect(result.warnings.isEmpty)
        #expect(try Presentation(contentsOf: url).sourceFormat == .pptx)
    }
    // URL読取は拡張子が違っても内容から判定する。
    let wrongName = directory.appendingPathComponent("input.odp")
    try fixture().write(to: wrongName)
    #expect(try Presentation(contentsOf: wrongName).sourceFormat == .pptx)
    #expect(try SlideReader(contentsOf: wrongName).summary.format == .pptx)
}

@MainActor @Test func asyncReaderAndPlanEncodingMatchSynchronousEntryPoints() async throws {
    let probe = CodecSet([Codec(APIProbeCodec(format: .keynote, marker: "async"))])
    let opened = try await probe.slideReader(Data(), format: .keynote)
    #if os(macOS)
    #expect(opened.summary.metadata.description == "false")
    #endif
    let bytes = try fixture()
    let reader = try await CodecSet.all.slideReader(bytes, format: .pptx, options: .init(includesNotes: false))
    #expect(try await reader.slide(id: "256").slide.notes == nil)
    let imagePath = try #require(try await reader.slide(id: "256").slide.elements[5].image?.path)
    #expect(try await reader.asset(at: imagePath) == fixture("fixture.png"))
    let deck = try await Presentation.read(bytes, format: .pptx).presentation
    #expect(try await Presentation.inspect(bytes, format: .pptx).slideCount == 2)
    let plan = try await deck.planWrite()
    #expect(try await deck.write(using: plan).data == bytes)
    #expect(try await CodecSet.all.write(deck, using: plan).data == bytes)
    var changed = deck; changed.metadata.title = "変更"
    await #expect(throws: SlideError.stalePlan) { try await changed.write(using: plan) }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".odp")
    let sentinel = Data("保持".utf8); try sentinel.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    await #expect(throws: SlideError.outputFormatMismatch(format: .pptx, fileExtension: "odp")) { try await deck.write(to: url) }
    await #expect(throws: SlideError.outputFormatMismatch(format: .pptx, fileExtension: "odp")) { try await deck.write(to: url, using: plan) }
    #expect(try Data(contentsOf: url) == sentinel)
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await deck.write(using: plan)
    }
    await #expect(throws: CancellationError.self) { try await task.value }
}
