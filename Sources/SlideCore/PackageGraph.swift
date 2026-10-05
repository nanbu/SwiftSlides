import Foundation

/// 原本XMLの位置。pathはnamespace URIと同名兄弟の番号を含む説明用経路。
public struct ReferenceLocation: Sendable, Equatable, Codable {
    public let part: String
    public let path: String
    public let attribute: String?
    public let slideID: String?
    public let elementID: String?
    public init(part: String, path: String, attribute: String? = nil, slideID: String? = nil, elementID: String? = nil) {
        self.part = part; self.path = path; self.attribute = attribute; self.slideID = slideID; self.elementID = elementID
    }
}

/// 意味を確認した参照と、解釈できない参照候補を区別する。
public struct PackageReference: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable { case relationship, relationshipAttribute, timing, connector, unknown }
    public enum Knowledge: String, Sendable, Codable { case known, unknown }
    public let kind: Kind
    public let knowledge: Knowledge
    public let sourcePart: String
    public let location: ReferenceLocation
    public let value: String
    public let relationshipType: String?
    public let targetPart: String?
    public let targetElementID: String?
    public let isExternal: Bool
    public init(kind: Kind, knowledge: Knowledge, location: ReferenceLocation, value: String, sourcePart: String? = nil,
                relationshipType: String? = nil, targetPart: String? = nil, targetElementID: String? = nil, isExternal: Bool = false) {
        self.kind = kind; self.knowledge = knowledge; self.location = location; self.value = value
        self.sourcePart = sourcePart ?? location.part
        self.relationshipType = relationshipType; self.targetPart = targetPart; self.targetElementID = targetElementID; self.isExternal = isExternal
    }
}

public struct SourceIdentity: Sendable, Equatable, Codable {
    public let slideID: String
    public let elementID: String?
    public let part: String
    public let sourceID: String?
    public init(slideID: String, elementID: String? = nil, part: String, sourceID: String? = nil) {
        self.slideID = slideID; self.elementID = elementID; self.part = part; self.sourceID = sourceID
    }
}

/// 原本の参照inventory。未知scope・非XML内部の意味は解決済みとしない。
public struct PackageGraph: Sendable, Equatable, Codable {
    public let parts: [PackagePart]
    public let identities: [SourceIdentity]
    public let references: [PackageReference]
    public let unresolvedScopes: [ReferenceLocation]
    public let uninspectedParts: [String]
    public init(parts: [PackagePart] = [], identities: [SourceIdentity] = [], references: [PackageReference] = [],
                unresolvedScopes: [ReferenceLocation] = [], uninspectedParts: [String] = []) {
        self.parts = parts; self.identities = identities; self.references = references
        self.unresolvedScopes = unresolvedScopes; self.uninspectedParts = uninspectedParts
    }
}

/// 従来codecに義務を追加しない原本inventoryの拡張点。
public protocol PreservationInspectingCodec: PresentationCodec {
    func inspectPreservation(_ presentation: Presentation) throws -> PackageGraph
}

extension CodecSet {
    public func inspectPreservation(_ presentation: Presentation) throws -> PackageGraph {
        guard let format = presentation.sourceFormat else { return .init() }
        guard let implementation = try codec(format) as? any PreservationInspectingCodec else {
            throw SlideError.unsafeEdit("このコーデックは参照inventoryを提供しません")
        }
        return try implementation.inspectPreservation(presentation)
    }
}
