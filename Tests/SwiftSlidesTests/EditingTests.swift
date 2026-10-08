import Foundation
import Testing
import SwiftSlides

private enum EditingFailure: Error { case stopped }

@Test func idEditsFindNestedElementsAndPreserveOriginalParts() throws {
    let original = try fixture()
    var deck = try Presentation(data: original)
    let slideID = deck.slides[0].id
    let childID = deck.slides[0].elements[6].children[0].id
    let originalText = deck.slides[0].elements[6].children[0].text
    let result = try deck.editSlide(id: slideID) { slide in
        try slide.editElement(id: childID) { element in
            element.frame?.x = 740
            return element.name
        }
    }
    #expect(result == deck.slides[0].elements[6].children[0].name)
    let output = try deck.write(options: .init(strict: true))
    let reopened = try Presentation(data: output.data)
    #expect(reopened.slides[0].elements[6].children[0].id == childID)
    #expect(reopened.slides[0].elements[6].children[0].frame?.x == 740)
    #expect(reopened.slides[0].elements[6].children[0].text == originalText)
    let before = try parts(original), after = try parts(output.data)
    for path in before.keys where path != "ppt/slides/slide1.xml" && path != "ppt/slides/_rels/slide1.xml.rels" {
        #expect(before[path] == after[path])
    }
}

@Test func idAndTextEditingRollBackClosureFailures() throws {
    var deck = textPresentation()
    let slide = deck.slides[0], element = slide.elements[0]
    #expect(throws: EditingFailure.stopped) {
        try deck.editSlide(id: slide.id) { target in
            target.name = "破棄"
            try target.editElement(id: element.id) { $0.text = .init("途中の変更") }
            throw EditingFailure.stopped
        }
    }
    #expect(deck.slides == [slide])
    #expect(throws: EditingFailure.stopped) {
        try deck.slides[0].editElement(id: element.id) { target in
            target.name = "破棄"
            throw EditingFailure.stopped
        }
    }
    #expect(deck.slides == [slide])
    #expect(throws: EditingFailure.stopped) {
        try deck.slides[0].elements[0].editText { text in
            text.paragraphs[0].runs[0].text = "破棄"
            throw EditingFailure.stopped
        }
    }
    #expect(deck.slides == [slide])
    let count = try deck.slides[0].elements[0].editText { text in
        text.paragraphs[0].runs[0].text = "反映"
        return text.paragraphs.count
    }
    #expect(count == 1 && deck.plainText == "反映")
    #expect(deck.slides[0].elements[0].text?.paragraphs[0].runs[0].style == element.text?.paragraphs[0].runs[0].style)
}

@Test func idEditingRefusesMissingAmbiguousAndChangedIdentities() throws {
    var deck = textPresentation()
    let original = deck.slides
    var called = false
    #expect(throws: SlideError.slideNotFound(id: "missing")) { try deck.editSlide(id: "missing") { _ in called = true } }
    #expect(throws: SlideError.elementNotFound(id: "missing")) { try deck.slides[0].editElement(id: "missing") { _ in called = true } }
    #expect(!called && deck.slides == original)
    #expect(throws: SlideError.self) { try deck.editSlide(id: original[0].id) { $0.id = "changed" } }
    #expect(throws: SlideError.self) { try deck.slides[0].editElement(id: original[0].elements[0].id) { $0.id = "changed" } }
    #expect(throws: SlideError.self) {
        try deck.editSlide(id: original[0].id) { $0.elements.append($0.elements[0]) }
    }
    #expect(deck.slides == original)
    var invalid = deck
    invalid.slides.append(invalid.slides[0])
    #expect(throws: SlideError.self) { try invalid.editSlide(id: original[0].id) { _ in called = true } }
    invalid = deck
    invalid.slides[0].elements.append(Element(kind: .group, children: original[0].elements))
    #expect(throws: SlideError.self) { try invalid.slides[0].editElement(id: original[0].elements[0].id) { _ in called = true } }
    invalid = deck
    invalid.slides[0].elements[0].id = ""
    #expect(throws: SlideError.self) { try invalid.editSlide(id: original[0].id) { _ in called = true } }
    #expect(!called)
    // 同名と別スライド間の同じ要素IDは衝突ではない。
    var another = original[0]; another.id = "another"
    deck.slides.append(another)
    try deck.editSlide(id: "another") { $0.name = "同名を許容" }
    #expect(deck.slides[0] == original[0])
}

@Test func textEditingRefusesWrongKindsWithoutCallingBody() throws {
    for kind in [Element.Kind.image, .table, .group, .opaque, .connector] {
        var element = Element(kind: kind, text: .init("読み取り投影"))
        let original = element
        #expect(throws: SlideError.self) { try element.editText { _ in Issue.record("型違いでクロージャーが呼ばれました") } }
        #expect(element == original)
    }
    var element = Element()
    #expect(throws: SlideError.self) { try element.editText { _ in Issue.record("文字のない要素で呼ばれました") } }
    #expect(element.text == nil)
}

@Test func transactionValidatesMultipleEditsAndReturnsEncodedResult() throws {
    var deck = try Presentation(data: fixture())
    let slideID = deck.slides[0].id, elementID = deck.slides[0].elements[0].id
    let result = try deck.transaction { candidate in
        candidate.metadata.title = "一括変更"
        try candidate.editSlide(id: slideID) { slide in
            try slide.editElement(id: elementID) { $0.frame?.x = 80 }
        }
        candidate.slides.reverse()
    }
    #expect(result.warnings.isEmpty)
    let reopened = try Presentation(data: result.data)
    #expect(reopened.metadata.title == "一括変更")
    #expect(reopened.slides.last?.id == slideID)
    #expect(reopened.slides.last?.elements[0].frame?.x == 80)
    #expect(deck.slides.last?.elements[0].frame?.x == 80)
}

@Test func transactionFailuresKeepModelAndOriginalSnapshot() throws {
    let data = try fixture()
    var deck = try Presentation(data: data)
    let original = deck.slides
    let originalSize = deck.size
    #expect(throws: EditingFailure.stopped) {
        try deck.transaction { candidate in
            candidate.metadata.title = "破棄"
            _ = try candidate.duplicateSlide(id: original[0].id)
            throw EditingFailure.stopped
        }
    }
    #expect(deck.metadata.title != "破棄" && deck.slides == original)
    #expect(try deck.write().data == data)
    #expect(throws: SlideError.self) { try deck.transaction { $0.size.width = .nan } }
    #expect(throws: SlideError.self) { try deck.transaction { $0.slides[1].elements[0].frame?.x = 80 } }
    #expect(deck.slides == original && deck.size == originalSize)
    #expect(try deck.write().data == data)
}

@Test func transactionStrictDefaultRefusesRewriteAndOptInReturnsWarnings() throws {
    var deck = try Presentation(data: fixture())
    let original = deck.slides
    #expect(throws: SlideError.self) { try deck.transaction { $0.slides[0].elements[0].text = .init("変更") } }
    #expect(deck.slides == original)
    let result = try deck.transaction(options: .init(strict: false)) { $0.slides[0].elements[0].text = .init("変更") }
    #expect(result.warnings.contains { $0.code == .rewrittenContent })
    #expect(try Presentation(data: result.data).slides[0].elements[0].plainText == "変更")
    #expect(deck.slides[0].elements[0].plainText == "変更")
}

@Test func transactionCancellationDiscardsCandidate() async throws {
    let original = textPresentation()
    let task = Task {
        var candidate = original
        do {
            _ = try candidate.transaction {
                $0.metadata.title = "破棄"
                withUnsafeCurrentTask { $0?.cancel() }
            }
            Issue.record("キャンセルした編集が確定しました")
        } catch is CancellationError {
            #expect(candidate.metadata == original.metadata && candidate.slides == original.slides)
        }
    }
    try await task.value
}
