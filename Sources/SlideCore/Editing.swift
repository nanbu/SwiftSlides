import Foundation

extension Presentation {
    /// 指定IDのスライドを編集し、正常終了時だけ反映する。保存可否はwriterで検査する。
    @discardableResult public mutating func editSlide<R>(id: String, _ body: (inout Slide) throws -> R) throws -> R {
        try validateIdentities()
        guard let index = slides.firstIndex(where: { $0.id == id }) else { throw SlideError.slideNotFound(id: id) }
        var candidate = slides[index]
        let result = try body(&candidate)
        guard candidate.id == id else { throw SlideError.invalidModel("編集中のスライドIDは変更できません") }
        try validateElementIdentities(candidate.elements)
        try Task.checkCancellation()
        slides[index] = candidate
        return result
    }

    package func validateIdentities() throws {
        var ids: Set<String> = []
        for slide in slides {
            try Task.checkCancellation()
            guard !slide.id.isEmpty, ids.insert(slide.id).inserted else { throw SlideError.invalidModel("空または重複したスライドID") }
            try validateElementIdentities(slide.elements)
        }
    }
}

extension Slide {
    /// group内も含めて指定IDの要素を編集する。失敗時はスライド全体を維持する。
    @discardableResult public mutating func editElement<R>(id: String, _ body: (inout Element) throws -> R) throws -> R {
        try validateElementIdentities(elements)
        guard let path = elementPath(id: id, in: elements) else { throw SlideError.elementNotFound(id: id) }
        var candidate = self
        let result = try editElementValue(in: &candidate.elements, path: path[...], body: body)
        try validateElementIdentities(candidate.elements)
        try Task.checkCancellation()
        self = candidate
        return result
    }
}

extension Element {
    /// 既存shapeのTextBodyを編集する。型違い・text欠落・クロージャー失敗では変更しない。
    @discardableResult public mutating func editText<R>(_ body: (inout TextBody) throws -> R) throws -> R {
        try Task.checkCancellation()
        guard kind == .shape, var candidate = text else { throw SlideError.invalidModel("この要素には編集できるshapeの文字がありません") }
        let result = try body(&candidate)
        try Task.checkCancellation()
        text = candidate
        return result
    }
}

extension CodecSet {
    /// 複数の編集を元形式のwriterで検査し、成功時だけ確定する。ファイル保存はしない。
    /// 検査で生成したbytesと警告を返す。既定のstrictは警告のある変更も拒否する。
    public func transaction(_ presentation: inout Presentation, options: WriteOptions = .init(strict: true),
                            _ body: (inout Presentation) throws -> Void) throws -> WriteResult {
        try Task.checkCancellation()
        let format = presentation.sourceFormat ?? .pptx
        var candidate = presentation
        try body(&candidate)
        try candidate.validateIdentities()
        let result = try write(candidate, as: format, options: options)
        try Task.checkCancellation()
        presentation = candidate
        return result
    }
}

private func validateElementIdentities(_ elements: [Element]) throws {
    var ids: Set<String> = []
    var pending = elements.map { ($0, 0) }
    while let (element, depth) = pending.popLast() {
        try Task.checkCancellation()
        guard depth <= 128 else { throw SlideError.invalidModel("要素の階層が深すぎます") }
        guard !element.id.isEmpty, ids.insert(element.id).inserted else { throw SlideError.invalidModel("空または重複した要素ID") }
        pending.append(contentsOf: element.children.map { ($0, depth + 1) })
    }
}

private func elementPath(id: String, in elements: [Element]) -> [Int]? {
    for index in elements.indices {
        if elements[index].id == id { return [index] }
        if let child = elementPath(id: id, in: elements[index].children) { return [index] + child }
    }
    return nil
}

private func editElementValue<R>(in elements: inout [Element], path: ArraySlice<Int>,
                               body: (inout Element) throws -> R) throws -> R {
    let index = path.first!
    if path.count > 1 { return try editElementValue(in: &elements[index].children, path: path.dropFirst(), body: body) }
    let id = elements[index].id
    let result = try body(&elements[index])
    guard elements[index].id == id else { throw SlideError.invalidModel("編集中の要素IDは変更できません") }
    return result
}
