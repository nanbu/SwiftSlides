import Foundation
import Testing
import SwiftSlides
import SlideDecrypt

@Test func canonicalWriteAndURLFormatTwinsPreserveWarningsAndSelection() throws {
    let p = textPresentation()
    let encoded = try p.write(as: .pptx)
    #expect(try Presentation(data: encoded.data).plainText == p.plainText)
    let plan = try p.planWrite()
    #expect(try p.write(using: plan).data == CodecSet.all.write(p, using: plan).data)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bin")
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(try p.write(to: url, using: plan).warnings == encoded.warnings)
    #expect(try Presentation(contentsOf: url, format: .pptx).plainText == p.plainText)
    #expect(try Presentation.read(contentsOf: url, format: .pptx).presentation.plainText == p.plainText)
    #expect(try Presentation.inspect(contentsOf: url, format: .pptx).format == .pptx)
    #expect(try SlideReader(contentsOf: url, format: .pptx).summary.format == .pptx)
    #expect(throws: SlideError.self) { try Presentation.read(contentsOf: url, format: .pptm) }
    #expect(throws: SlideError.self) { try Presentation.inspect(contentsOf: url, format: .pptm) }
    #expect(throws: SlideError.self) { try SlideReader(contentsOf: url, format: .pptm) }
    #expect(throws: SlideError.self) { try CodecSet.all.fileSlideReader(contentsOf: url, format: .pptm) }
    // Password twins must forward format even when no decryption is needed.
    #expect(throws: SlideError.self) { try Presentation(contentsOf: url, password: "unused", format: .pptm) }
    #expect(throws: SlideError.self) { try Presentation.inspect(contentsOf: url, password: "unused", format: .pptm) }
    #expect(throws: SlideError.self) { try CodecSet.all.slideReader(contentsOf: url, password: "unused", format: .pptm) }
}

@Test func sharedCacheBudgetIsAvailableAtEveryReaderEntrance() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".odp")
    try fixture("styles.odp").write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let budget = ReaderCacheBudget(totalBytes: 1001)
    let readers = [try SlideReader(fileBackedURL: url, cacheBudget: budget),
                   try await CodecSet.all.fileSlideReader(contentsOf: url, cacheBudget: budget)]
    for reader in readers {
        for descriptor in reader.slideDescriptors { _ = try await reader.slide(id: descriptor.id) }
        let stats = try #require(reader.cacheStatistics)
        #expect(stats.retainedBytes <= budget.totalBytes && stats.peakRetainedBytes <= budget.totalBytes)
    }
    let zero = try SlideReader(fileBackedURL: url, cacheBudget: .init(totalBytes: 0))
    _ = try await zero.readSlides()
    #expect(zero.cacheStatistics?.retainedBytes == 0)
    #expect(throws: SlideError.self) { try SlideReader(fileBackedURL: url, cacheBudget: .init(totalBytes: -1)) }
}

@Test func emptySlideSelectionStillObservesCancellation() async throws {
    let reader = try SlideReader(data: fixture())
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await reader.readSlides(selection: .ids([]))
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(try await reader.readSlides(selection: .ids([])).isEmpty)
    await #expect(throws: SlideError.self) { try await reader.readSlides(selection: .ids([]), maxConcurrentReads: 0) }
}

@Test func cacheEvictionReplacementAndZeroBudgetRemainBounded() {
    let cache = ReadingDataCache(limit: 6)
    cache.insert(Data([1, 2]), for: "a")
    cache.insert(Data([3, 4]), for: "b")
    cache.insert(Data([5, 6]), for: "c")
    #expect(cache.value(for: "a") == Data([1, 2]))
    cache.insert(Data([7, 8, 9]), for: "d")
    #expect(cache.value(for: "b") == nil && cache.value(for: "c") == nil)
    #expect(cache.value(for: "a") == Data([1, 2]))
    cache.insert(Data([0]), for: "a")
    #expect(cache.statistics.retainedBytes == 4)
    cache.insert(Data(repeating: 1, count: 7), for: "a")
    #expect(cache.value(for: "a") == nil && cache.statistics.retainedBytes == 3)
    cache.insert(Data(), for: "d")
    #expect(cache.value(for: "d") == nil && cache.statistics.retainedBytes == 0)
    #expect(cache.statistics.peakRetainedBytes == 6)
    let zero = ReadingDataCache(limit: 0)
    for i in 0..<1000 { zero.insert(Data(), for: String(i)) }
    #expect(zero.value(for: "0") == nil && zero.statistics.retainedBytes == 0)
}

@Test func renamedModelPropertiesPreserveExistingJSONKeys() throws {
    var slide = Slide(id: "s")
    var element = Element(id: "e", text: TextBody(paragraphs: [], wrapsText: false))
    element.isFlippedHorizontally = true; element.isFlippedVertically = true
    element.effects = .init(direct: [.outerShadow(.init(rotatesWithShape: false))])
    element.fill = .gradient(.init(stops: [], rotatesWithShape: false))
    slide.elements = [element]; slide.showsMasterShapes = false
    slide.transition = .init(advancesOnClick: false)
    let encoded = try JSONEncoder().encode(slide)
    let string = String(decoding: encoded, as: UTF8.self)
    for key in ["flipHorizontal", "flipVertical", "wrap", "showMasterShapes", "rotateWithShape", "advanceOnClick"] {
        #expect(string.contains("\"\(key)\":"))
    }
    #expect(try JSONDecoder().decode(Slide.self, from: encoded) == slide)
}

@Test func invalidDistributionRollsBackBeforeChangingAnyElement() throws {
    let initial = [Element(frame: .init(x: 1, y: 2, width: 10, height: 10)),
                   Element(frame: .init(x: 5, y: 6, width: -1, height: 10))]
    var elements = initial
    #expect(throws: SlideError.self) { try Layout.distribute(&elements, along: .horizontal, in: .init(x: 0, y: 0, width: 100, height: 100)) }
    #expect(elements == initial)
    elements = [initial[0]]
    #expect(throws: SlideError.self) { try Layout.distribute(&elements, along: .horizontal, in: .init(x: .infinity, y: 0, width: 100, height: 100)) }
    #expect(elements == [initial[0]])
}

private struct MalformedSlideSource: PresentationSlideSource {
    let slideDescriptors: [SlideDescriptor]
    let summary: PresentationSummary
    func slide(at index: Int) throws -> SlideReadResult { .init(slide: Slide()) }
    func asset(at path: String) throws -> Data { Data() }
}
private struct MalformedReaderCodec: SlideReadingCodec {
    let source: MalformedSlideSource
    var format: PresentationFormat { .pptx }
    func read(_ data: Data, options: ReadOptions) throws -> ReadResult { .init(presentation: Presentation()) }
    func inspect(_ data: Data, options: InspectOptions) throws -> PresentationSummary { source.summary }
    func write(_ presentation: Presentation, options: WriteOptions) throws -> WriteResult { .init(data: Data()) }
    func openSlides(_ data: Data, options: ReadOptions) throws -> any PresentationSlideSource { source }
}
@Test func readerRejectsInconsistentDescriptorContracts() {
    for (descriptors, count) in [([SlideDescriptor(id: "a", index: 4)], 1), ([SlideDescriptor(id: "a", index: 0)], 2),
                                 ([SlideDescriptor(id: "a", index: 0), SlideDescriptor(id: "a", index: 1)], 2)] {
        let source = MalformedSlideSource(slideDescriptors: descriptors, summary: .init(format: .pptx, size: .standard, slideCount: count, metadata: .init(), parts: []))
        let set = CodecSet([Codec(MalformedReaderCodec(source: source))])
        #expect(throws: SlideError.self) { try set.slideReader(Data(), format: .pptx) }
    }
}

@Test func sourceXMLTraversalKeepsDocumentOrderAndNamespaces() throws {
    let root = try MarkupNode.parse(Data("<r xmlns='urn:a'><x id='1'><x id='2'/></x><x xmlns='urn:b' id='3'/><x id='4'/></r>".utf8), part: "synthetic.xml", limits: .init())
    let source = try SourceXMLNode(root)
    #expect(source.descendants(named: "x").compactMap { $0.attributes["id"] } == ["1", "2", "3", "4"])
    #expect(source.descendants(named: "x", namespace: "urn:a").compactMap { $0.attributes["id"] } == ["1", "2", "4"])
}

@Test func inspectionOptionsReachPlainAndPasswordCodecs() async throws {
    let data = try fixture()
    let options = InspectOptions(limits: .init(maxEntries: 0))
    #expect(throws: SlideError.self) { try Presentation.inspect(data, options: options) }
    #expect(throws: SlideError.self) { try Presentation.inspect(data, password: "unused", options: options) }
    await #expect(throws: SlideError.self) { try await CodecSet.all.inspect(data, options: options) }
    await #expect(throws: SlideError.self) { try await Presentation.inspect(data, password: "unused", options: options) }
}

@Test func releaseVersionAgreesWithDocuments() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    #expect(try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8).contains("**" + SwiftSlidesInfo.version + "**"))
    #expect(try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8).contains("## [" + SwiftSlidesInfo.version + "]"))
}
