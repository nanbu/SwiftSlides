import Foundation
import Testing
@testable import SlideCore
import SwiftSlides

@Test func savePlanCopiesOriginalAndLocatesPatch() throws {
    let data = try fixture(), original = try Presentation(data: data)
    let copy = try original.planWrite()
    #expect(copy.canSave)
    #expect(copy.changedPartCount == 0)
    #expect(copy.actions.allSatisfy { $0.kind == .copy })
    #expect(try original.write(using: copy).data == data)
    var changed = original
    changed.slides[0].elements[0].frame?.x = 80
    let patch = try changed.planWrite(options: .init(strict: true))
    #expect(patch.canSave)
    #expect(patch.actions.filter { $0.kind == .patch }.map(\.part) == ["ppt/slides/slide1.xml", "ppt/slides/_rels/slide1.xml.rels"].sorted())
    #expect(patch.changedExpandedBytes > 0)
    #expect(try Presentation(data: changed.write(using: patch).data).slides[0].elements[0].frame?.x == 80)
    let create = try textPresentation().planWrite()
    #expect(create.canSave && create.actions.allSatisfy { $0.kind == .create })
}

@Test func stalePlanRejectsModelSourceAndOptionsBeforeWrite() throws {
    var p = try Presentation(data: fixture())
    let plan = try p.planWrite()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pptx")
    let sentinel = Data("既存の出力先".utf8)
    try sentinel.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    p.slides[0].elements[0].text = .init("Changed")
    #expect(throws: SlideError.stalePlan) { try p.write(to: url, using: plan) }
    #expect(try Data(contentsOf: url) == sentinel)
    p = try Presentation(data: fixture())
    #expect(throws: SlideError.stalePlan) { try p.write(using: plan, options: .init(compress: false)) }
    p = try Presentation(data: changedFixture { $0["unrelated.bin"] = Data([1, 2, 3]) })
    #expect(throws: SlideError.stalePlan) { try p.write(using: plan) }
}

@Test func rejectedSavePlansKeepReasonsAndDestination() throws {
    var p = textPresentation()
    p.size.width = .nan
    let invalid = try p.planWrite()
    #expect(!invalid.canSave && invalid.diagnostics.first?.code == "invalidModel")
    p = try Presentation(data: fixture())
    p.slides[1].elements[0].frame?.x = 12
    let unsafe = try p.planWrite()
    #expect(!unsafe.canSave && unsafe.diagnostics.first?.code == "unsafeEdit")
    #expect(throws: SlideError.self) { try p.write(using: unsafe) }
    #expect(try !p.planWrite(as: .odp).canSave)
    p = try Presentation(data: fixture())
    p.slides[0].elements[0].text = .init("Rewrite")
    #expect(try p.planWrite().diagnostics.contains { $0.action == .rewritten })
    #expect(try !p.planWrite(options: .init(strict: true)).canSave)
}

@Test func fingerprintMatchesIndependentSHA256Vectors() throws {
    #expect(try Fingerprint.hash(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    #expect(try Fingerprint.hash(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    #expect(try Fingerprint.hash(Data(repeating: 97, count: 1_000_000)) == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    #expect(try Fingerprint.hash(Data([0, 97, 98, 99]).dropFirst()) == Fingerprint.hash(Data("abc".utf8)))
}

@Test func asyncPlanAndCancellationPreserveDestination() async throws {
    let p = textPresentation()
    let plan = try await p.planWrite()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pptx")
    let sentinel = Data("untouched".utf8)
    try sentinel.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await p.write(to: url, using: plan)
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(try Data(contentsOf: url) == sentinel)
    let saved = try await p.write(to: url, using: plan)
    #expect(saved.warnings.isEmpty)
    #expect(try Presentation(contentsOf: url).plainText == "Hello")
}

@Test func failedAtomicTargetKeepsExistingContents() throws {
    let p = textPresentation(), plan = try p.planWrite()
    let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pptx")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: target) }
    let child = target.appendingPathComponent("sentinel")
    let contents = Data("保持する内容".utf8); try contents.write(to: child)
    do { _ = try p.write(to: target, using: plan); Issue.record("ディレクトリへの保存が成功しました") }
    catch { #expect(try Data(contentsOf: child) == contents) }
}
