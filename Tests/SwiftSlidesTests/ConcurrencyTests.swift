import Foundation
import Testing
@testable import SlideCore
import SwiftSlides

private enum TaskContext {
    @TaskLocal static var marker: String = "missing"
}

/// 従来の同期codec。追加したcapabilitiesには既定実装を使う。
private struct ContextCodec: PresentationCodec {
    let format: PresentationFormat = .pptx
    var cancelDuringWrite = false
    func read(_ data: Data, options: ReadOptions) throws -> ReadResult {
        .init(presentation: Presentation(metadata: .init(title: TaskContext.marker, subject: String(Thread.isMainThread))))
    }
    func inspect(_ data: Data, limits: PackageLimits) throws -> PresentationSummary { throw SlideError.invalidModel("test codec") }
    func write(_ presentation: Presentation, options: WriteOptions) throws -> WriteResult {
        if cancelDuringWrite { withUnsafeCurrentTask { $0?.cancel() } }
        return .init(data: Data("new contents".utf8))
    }
}

@MainActor @Test func asyncReadLeavesMainActorAndInheritsContext() async throws {
    let codecs = CodecSet([Codec(ContextCodec())])
    let result = try await TaskContext.$marker.withValue("inherited") {
        try await codecs.read(Data(), format: .pptx)
    }
    #expect(result.presentation.metadata.title == "inherited")
    #if os(macOS)
    #expect(result.presentation.metadata.subject == "false")
    #endif
    #expect(try codecs.capabilities(for: .pptx)[.read] == .unverified)
    #expect(try codecs.capabilities(for: .pptx).features.isEmpty)
    #expect(try codecs.capabilities(for: .pptx).capability(for: "TXT-001", operation: .read, profile: .ooxmlTransitional).status == .unverified)
}

@Test func asyncRoundTripAndInspection() async throws {
    let original = try fixture()
    var result = try await Presentation.read(original)
    #expect(result.warnings == result.presentation.readWarnings)
    #expect(try await result.presentation.data() == original)
    let overview = try await Presentation.inspect(original)
    #expect(overview.slideCount == result.presentation.slides.count)
    let image = try #require(result.presentation.slides[0].elements[5].image?.path)
    #expect(try await result.presentation.asset(at: image).starts(with: [137, 80, 78, 71]))
    result.presentation.metadata.title = "Async edit"
    let encoded = try await result.presentation.encoded()
    #expect(try await Presentation.read(encoded.data).presentation.metadata.title == "Async edit")

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("async.pptx")
    let saved = try await result.presentation.write(to: url)
    #expect(saved.warnings.isEmpty)
    #expect(try await Presentation.inspect(contentsOf: url).slideCount == overview.slideCount)
    #expect(try await Presentation.read(contentsOf: url).presentation.metadata.title == "Async edit")
}

private actor BatchProbe {
    var active = 0, peak = 0, started = 0, finished = 0, cancelled = 0
    var starters: [CheckedContinuation<Void, Never>] = []
    func start() {
        active += 1; started += 1; peak = max(peak, active)
        if started >= 3 { let waiting = starters; starters.removeAll(); for waiter in waiting { waiter.resume() } }
    }
    func waitForThree() async {
        if started >= 3 { return }
        await withCheckedContinuation { starters.append($0) }
    }
    func finish(cancelled: Bool = false) { active -= 1; finished += 1; if cancelled { self.cancelled += 1 } }
    var counts: [Int] { [active, peak, started, finished, cancelled] }
}

@Test func boundedBatchPreservesOrderAndLimit() async throws {
    let probe = BatchProbe()
    let results = try await boundedMap(Array(0..<12), maxConcurrent: 3) { n in
        await probe.start()
        try await Task.sleep(for: .milliseconds(12 - n))
        await probe.finish()
        return "item-\(n)"
    }
    #expect(results == (0..<12).map { "item-\($0)" })
    let counts = await probe.counts
    #expect(counts[0] == 0 && counts[1] <= 3 && counts[2] == 12 && counts[3] == 12)
    #expect(try await boundedMap([Int](), maxConcurrent: 1) { $0 }.isEmpty)
    await #expect(throws: SlideError.self) { try await boundedMap([Int](), maxConcurrent: 0) { $0 } }
}

private enum BatchFailure: Error { case expected }

@Test func batchFailureCancelsAndJoinsChildren() async {
    let probe = BatchProbe()
    await #expect(throws: BatchFailure.expected) {
        try await boundedMap(Array(0..<10), maxConcurrent: 3) { n in
            await probe.start()
            do {
                if n == 0 { await probe.waitForThree(); throw BatchFailure.expected }
                try await Task.sleep(for: .seconds(2))
                await probe.finish(); return n
            } catch {
                await probe.finish(cancelled: error is CancellationError)
                throw error
            }
        }
    }
    let counts = await probe.counts
    #expect(counts == [0, 3, 3, 3, 2])
}

@Test func parentCancellationJoinsBatchChildren() async {
    let probe = BatchProbe()
    let task = Task {
        try await boundedMap(Array(0..<10), maxConcurrent: 3) { n in
            await probe.start()
            do {
                try await Task.sleep(for: .seconds(2))
                await probe.finish(); return n
            } catch {
                await probe.finish(cancelled: error is CancellationError)
                throw error
            }
        }
    }
    await probe.waitForThree()
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(await probe.counts == [0, 3, 3, 3, 3])
}

@Test func batchURLsUseOptionsAndInputOrder() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let names = ["python-pptx.pptx", "macro.pptm", "strict.pptx"]
    var urls: [URL] = []
    for name in names {
        let url = directory.appendingPathComponent(name)
        try fixture(name).write(to: url); urls.append(url)
    }
    let results = try await Presentation.readAll(contentsOf: urls, options: .init(includeNotes: false), maxConcurrentReads: 2)
    #expect(results.map { $0.presentation.sourceFormat } == [.pptx, .pptm, .pptx])
    #expect(results.allSatisfy { $0.presentation.slides.allSatisfy { $0.notes == nil } })
    await #expect(throws: SlideError.self) {
        try await Presentation.readAll(contentsOf: urls, options: .init(limits: .init(maxEntries: 1)), maxConcurrentReads: 2)
    }
    urls.append(directory.appendingPathComponent("missing.pptx"))
    await #expect(throws: (any Error).self) { try await Presentation.readAll(contentsOf: urls) }
}

@Test func cancellationBeforeReadAndBeforeSavePreservesDestination() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("original.pptx"), original = Data("original".utf8)
    try original.write(to: url)
    let read = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await Presentation.read(contentsOf: directory.appendingPathComponent("missing.pptx"))
    }
    await #expect(throws: CancellationError.self) { try await read.value }
    let write = Task {
        let codecs = CodecSet([Codec(ContextCodec(cancelDuringWrite: true))])
        return try await codecs.write(Presentation(), to: url)
    }
    await #expect(throws: CancellationError.self) { try await write.value }
    #expect(try Data(contentsOf: url) == original)
}

@Test func capabilitiesAndPreservationAreConservative() throws {
    #expect(try CodecSet.all.capabilities(for: .pptx)[.create] == .partial)
    #expect(try CodecSet.all.capabilities(for: .pptm)[.create] == .unsupported)
    #expect(try CodecSet.all.capabilities(for: .pptx)[.render] == .unsupported)
    #expect(try CodecSet.all.capabilities(for: .odp)[.create] == .unsupported)
    let original = try fixture()
    var result = try Presentation.read(original)
    let summary = result.preservationSummary
    #expect(summary.sourceFormat == .pptx && summary.hasOriginal)
    #expect(summary.originalBytes == original.count)
    #expect(summary.retainedPartCount == result.presentation.packageParts.count)
    #expect(summary.opaqueElementCount == 1)
    #expect(summary.warningCounts[.unsupportedContent, default: 0] >= 1)
    var group = Element(id: "new-group", kind: .group)
    group.children = [Element(id: "nested", kind: .opaque)]
    result.presentation.slides[0].elements.append(group)
    #expect(result.preservationSummary.opaqueElementCount == 2)
    #expect(Presentation().preservationSummary.originalBytes == 0)
    #expect(!Presentation().preservationSummary.hasOriginal)
}

@Test(arguments: [0, 1, 65_535, 65_536, 65_537, 200_000])
func chunkedCompressionRoundTripsAndDetectsCorruption(_ count: Int) throws {
    // 圧縮しやすい入力とchunkより大きい出力の両方を通す。
    var state: UInt64 = 12345
    let random = Data((0..<count).map { _ in
        state = state &* 6364136223846793005 &+ 1
        return UInt8(truncatingIfNeeded: state >> 32)
    })
    let expected = ["random.bin": random, "repeat.bin": Data(repeating: 42, count: count)]
    let encoded = try ZIPWriter.write(expected, compress: true)
    let archive = try PackageArchive(encoded)
    // Python zlib.crc32で独立に求めた値。reader/writer双方の誤りの相殺を防ぐ。
    let crcOracle: [Int: UInt32] = [0: 0, 1: 0x6c09ff9d, 65_535: 0x2d1547f4,
                                  65_536: 0x932b80aa, 65_537: 0x602ccf25, 200_000: 0x3fc960d9]
    #expect(archive.entries["random.bin"]?.crc == crcOracle[count])
    for (name, bytes) in expected { #expect(try archive.read(name) == bytes) }
    if count > 0 {
        var corrupt = encoded
        let nameSize = Int(corrupt[26]) | Int(corrupt[27]) << 8
        corrupt[30 + nameSize] ^= 0xff
        #expect(throws: SlideError.self) { try PackageArchive(corrupt).read("random.bin") }
    }
}
