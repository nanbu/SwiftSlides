import Foundation

/// 別文書へのリンクを暗黙に失わないための対応表。
public struct SlideImportOptions: Sendable {
    public var slideLinks: [String: String]
    public init(slideLinks: [String: String] = [:]) { self.slideLinks = slideLinks }
}

public protocol SlideImportingCodec: PresentationCodec {
    @discardableResult func duplicateSlide(id: String, in presentation: inout Presentation, at index: Int?) throws -> String
    @discardableResult func importSlide(id: String, from source: Presentation, into destination: inout Presentation,
        at index: Int?, options: SlideImportOptions) throws -> String
}

extension CodecSet {
    @discardableResult public func duplicateSlide(id: String, in presentation: inout Presentation, at index: Int? = nil) throws -> String {
        try Task.checkCancellation()
        guard let implementation = try codec(presentation.sourceFormat ?? .pptx) as? any SlideImportingCodec else {
            throw SlideError.unsafeEdit("このコーデックはスライドの複製を提供しません")
        }
        return try implementation.duplicateSlide(id: id, in: &presentation, at: index)
    }
    @discardableResult public func importSlide(id: String, from source: Presentation, into destination: inout Presentation,
        at index: Int? = nil, options: SlideImportOptions = .init()) throws -> String {
        try Task.checkCancellation()
        guard let implementation = try codec(destination.sourceFormat ?? .pptx) as? any SlideImportingCodec else {
            throw SlideError.unsafeEdit("このコーデックはスライドの取り込みを提供しません")
        }
        return try implementation.importSlide(id: id, from: source, into: &destination, at: index, options: options)
    }
}

package struct CloneSlideLink: Sendable, Codable {
    package let part: String
    package let relationshipID: String
    package let slideID: String
    package let fragment: String
    package init(part: String, relationshipID: String, slideID: String, fragment: String = "") {
        self.part = part; self.relationshipID = relationshipID; self.slideID = slideID; self.fragment = fragment
    }
}

/// writerが原本XMLとして扱う、不変の取り込みsnapshot。
package struct SlideClone: Sendable, Codable {
    package let baseline: Slide
    package let slidePath: String
    package let notesPath: String?
    package let notesOmitted: Bool
    package let parts: [String: Data]
    package let contentTypes: [String: String]
    package let links: [CloneSlideLink]
    package let graph: PackageGraph
    package let origins: [String: String]
    package init(baseline: Slide, slidePath: String, notesPath: String?, notesOmitted: Bool, parts: [String: Data],
                 contentTypes: [String: String], links: [CloneSlideLink], graph: PackageGraph, origins: [String: String]) {
        self.baseline = baseline; self.slidePath = slidePath; self.notesPath = notesPath; self.notesOmitted = notesOmitted
        self.parts = parts; self.contentTypes = contentTypes; self.links = links; self.graph = graph; self.origins = origins
    }
}
