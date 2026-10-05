import Foundation
import Testing
import SwiftSlides
@testable import SlideCore

@Test func selectedReaderSkipsBrokenUnselectedSlideAndSnapshotsURL() throws {
    let data = try changedFixture { $0["ppt/slides/slide2.xml"] = Data("broken".utf8) }
    let reader = try SlideReader(data:data,codecs:.all)
    #expect(reader.slideDescriptors.count == 2)
    #expect(try reader.slide(id:reader.slideDescriptors[0].id).slide.plainText.contains("売上成長"))
    #expect(throws:SlideError.self) { try reader.slide(id:reader.slideDescriptors[1].id) }
    #expect(throws:SlideError.self) { try reader.slides(selection:.ids(["missing"])) }
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:dir) }
    let url = dir.appendingPathComponent("input.pptx"); try data.write(to:url)
    let snapshot = try SlideReader(contentsOf:url,codecs:.all)
    try Data("changed".utf8).write(to:url)
    #expect(try snapshot.slide(id:snapshot.slideDescriptors[0].id).slide.plainText.contains("売上成長"))
}
@Test func readerAsyncSequenceIsDemandDrivenAndPreservesSelectionOrder() async throws {
    let reader = try SlideReader(data:fixture("styles.odp"),codecs:.all)
    var iterator = try reader.slides(selection:.ids(["page-two","page-one"])).makeAsyncIterator()
    #expect(try await iterator.next()?.slide.id == "page-two")
    #expect(try await iterator.next()?.slide.id == "page-one")
    #expect(try await iterator.next() == nil)
    let task = Task { () throws -> SlideReadResult? in
        withUnsafeCurrentTask { $0?.cancel() }
        var iterator = try reader.slides().makeAsyncIterator(); return try await iterator.next()
    }
    await #expect(throws:CancellationError.self) { try await task.value }
    #expect(try await reader.asset(at:"Pictures/fixture.png") == fixture("fixture.png"))
}
@Test func atomicFileTargetPreservesDestinationAfterPartialWriteFailureAndCancellation() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:dir) }
    let url = dir.appendingPathComponent("target.pptx"), original = Data("original destination".utf8)
    try original.write(to:url)
    let bytes = Data(repeating:42,count:200_000)
    #expect(throws:POSIXError(.ENOSPC)) {
        try FileTarget(url).write(bytes,beforeChunk:{ count in if count >= 65536 { throw POSIXError(.ENOSPC) } },beforeCommit:nil)
    }
    #expect(try Data(contentsOf:url) == original)
    #expect(try FileManager.default.contentsOfDirectory(atPath:dir.path) == ["target.pptx"])
    #expect(throws:CancellationError.self) { try FileTarget(url).write(bytes,beforeChunk:nil,beforeCommit:{ throw CancellationError() }) }
    #expect(try Data(contentsOf:url) == original)
    #expect(try FileManager.default.contentsOfDirectory(atPath:dir.path) == ["target.pptx"])
    try FileTarget(url).write(bytes)
    #expect(try Data(contentsOf:url) == bytes)
    let directoryTarget = dir.appendingPathComponent("existing-directory")
    try FileManager.default.createDirectory(at:directoryTarget,withIntermediateDirectories:false)
    #expect(throws:POSIXError.self) { try FileTarget(directoryTarget).write(bytes) }
    #expect(try FileManager.default.contentsOfDirectory(atPath:directoryTarget.path).isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath:dir.path).sorted() == ["existing-directory","target.pptx"])
}
@Test func atomicFileTargetChecksTaskCancellationAfterWritingChunks() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:dir) }
    let url = dir.appendingPathComponent("output"), original = Data("original".utf8); try original.write(to:url)
    let task = Task { () throws -> Void in
        try FileTarget(url).write(Data(repeating:7,count:200_000),beforeChunk:{ count in if count >= 65536 { withUnsafeCurrentTask { $0?.cancel() } } },beforeCommit:nil)
    }
    await #expect(throws:CancellationError.self) { try await task.value }
    #expect(try Data(contentsOf:url) == original)
    #expect(try FileManager.default.contentsOfDirectory(atPath:dir.path) == ["output"])
}
