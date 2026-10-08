import Foundation

public struct SavePartAction: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable { case copy, create, patch, remove }
    public let part: String
    public let kind: Kind
    public let expandedBytes: Int
    public init(part: String, kind: Kind, expandedBytes: Int) { self.part = part; self.kind = kind; self.expandedBytes = expandedBytes }
}

/// 現行writerの出力snapshotを持つ保存計画。計画作成時にエンコードする。
public struct SavePlan: Sendable {
    public let format: PresentationFormat
    public let profile: CapabilityProfile?
    public let options: WriteOptions
    public let actions: [SavePartAction]
    public let diagnostics: [SlideDiagnostic]
    public let sourceFingerprint: String
    public let modelFingerprint: String
    public let optionsFingerprint: String
    public var canSave: Bool { result != nil && !diagnostics.contains { $0.severity == .error } }
    public var changedPartCount: Int { actions.reduce(0) { $0 + ($1.kind != .copy ? 1 : 0) } }
    public var changedExpandedBytes: Int { actions.reduce(0) { $0 + ($1.kind == .create || $1.kind == .patch ? $1.expandedBytes : 0) } }
    package let result: WriteResult?
    package let codecIdentity: UUID?
    package init(format: PresentationFormat, profile: CapabilityProfile?, options: WriteOptions, actions: [SavePartAction], diagnostics: [SlideDiagnostic],
                 sourceFingerprint: String, modelFingerprint: String, optionsFingerprint: String, result: WriteResult?, codecIdentity: UUID?) {
        self.format = format; self.profile = profile; self.options = options; self.actions = actions; self.diagnostics = diagnostics
        self.sourceFingerprint = sourceFingerprint; self.modelFingerprint = modelFingerprint; self.optionsFingerprint = optionsFingerprint; self.result = result
        self.codecIdentity = codecIdentity
    }
}

private struct ModelSnapshot: Encodable {
    let size: Size
    let slides: [Slide]
    let metadata: Metadata
    let theme: Theme
    let sourceFormat: PresentationFormat?
    let sourceThemes: [ThemePart]
    let firstSlideNumber: Int?
    let defaultTextStyle: TextListStyle?
}

extension Presentation {
    package func modelFingerprint() throws -> String {
        try Fingerprint.encode(ModelSnapshot(size: size, slides: slides, metadata: metadata, theme: theme, sourceFormat: sourceFormat, sourceThemes: sourceThemes, firstSlideNumber: firstSlideNumber, defaultTextStyle: defaultTextStyle))
    }
    package func sourceFingerprint() throws -> String {
        struct Snapshot: Encodable { let original: String; let clones: [String: SlideClone] }
        return try Fingerprint.encode(Snapshot(original: Fingerprint.hash(storage?.data ?? Data()), clones: slideClones))
    }
}

extension CodecSet {
    public func planWrite(_ presentation: Presentation, as format: PresentationFormat? = nil, options: WriteOptions = .init()) throws -> SavePlan {
        try Task.checkCancellation()
        let destination = format ?? presentation.sourceFormat ?? .pptx
        let source = try presentation.sourceFingerprint(), model = try presentation.modelFingerprint(), conditions = try Fingerprint.encode(options)
        let result: WriteResult?
        let diagnostics: [SlideDiagnostic]
        do {
            let encoded = try codec(destination).write(presentation, options: options)
            result = encoded; diagnostics = encoded.diagnostics
        } catch let error as SlideError {
            let code: DiagnosticCode
            switch error {
            case .invalidModel: code = "invalidModel"
            case .unsafeEdit: code = "unsafeEdit"
            case .noCodec: code = "noCodec"
            default: throw error
            }
            result = nil
            diagnostics = [.init(code: code, severity: .error, stage: .write, action: .unresolved,
                location: .init(part: "", sourceElement: ""), message: error.description)]
        }
        var actions: [SavePartAction] = []
        var profile: CapabilityProfile?
        if let result, destination == .pptx || destination == .pptm {
            // Comparison uses exact compressed payloads, never CRC alone, and does not inflate untouched assets.
            let limits = PackageLimits(maxEntries: Int.max, maxExpandedBytes: Int.max, maxPartBytes: Int.max)
            let output = try PackageArchive(result.data, limits: limits)
            let package = try OPCPackage(archive: output, limits: limits)
            let root = try MarkupNode.parse(output.read(package.mainPart), part: package.mainPart, limits: limits)
            profile = root.namespace == NS.strictP ? .ooxmlStrict : .ooxmlTransitional
            let original = presentation.storage?.archive
            for path in Set(output.paths).union(original?.paths ?? []).sorted() where !path.hasSuffix("/") {
                try Task.checkCancellation()
                let kind: SavePartAction.Kind
                if output.entries[path] == nil { kind = .remove }
                else if original?.entries[path] == nil { kind = .create }
                else if let old = original, old.entries[path]?.method == output.entries[path]?.method,
                        old.entries[path]?.expandedSize == output.entries[path]?.expandedSize,
                        old.entries[path]?.crc == output.entries[path]?.crc,
                        try old.compressedBytes(path) == output.compressedBytes(path) { kind = .copy }
                else { kind = .patch }
                actions.append(.init(part: path, kind: kind, expandedBytes: output.entries[path]?.expandedSize ?? 0))
            }
        }
        try Task.checkCancellation()
        return .init(format: destination, profile: profile, options: options, actions: actions, diagnostics: diagnostics,
                     sourceFingerprint: source, modelFingerprint: model, optionsFingerprint: conditions, result: result,
                     codecIdentity: try? codec(for: destination).identity)
    }

    public func write(_ presentation: Presentation, using plan: SavePlan, options: WriteOptions? = nil) throws -> WriteResult {
        try Task.checkCancellation()
        let selected = try codec(for: plan.format)
        guard selected.identity == plan.codecIdentity,
              try presentation.sourceFingerprint() == plan.sourceFingerprint,
              try presentation.modelFingerprint() == plan.modelFingerprint,
              try Fingerprint.encode(options ?? plan.options) == plan.optionsFingerprint else { throw SlideError.stalePlan }
        guard plan.canSave, let result = plan.result else {
            throw SlideError.unsafeEdit(plan.diagnostics.map(\.message).joined(separator: "; "))
        }
        try Task.checkCancellation(); return result
    }

    public func write(_ presentation: Presentation, to url: URL, using plan: SavePlan, options: WriteOptions? = nil) throws -> WriteResult {
        try Task.checkCancellation()
        try validateDestination(url, format: plan.format)
        let result = try write(presentation, using: plan, options: options)
        try Task.checkCancellation()
        try FileTarget(url).write(result.data)
        return result
    }
    @concurrent public func planWrite(_ presentation: Presentation, as format: PresentationFormat? = nil, options: WriteOptions = .init()) async throws -> SavePlan {
        try planWriteSync(presentation, format: format, options: options)
    }
    private func planWriteSync(_ presentation: Presentation, format: PresentationFormat?, options: WriteOptions) throws -> SavePlan {
        try planWrite(presentation, as: format, options: options)
    }
    @concurrent public func write(_ presentation: Presentation, using plan: SavePlan, options: WriteOptions? = nil) async throws -> WriteResult {
        try writePlanSync(presentation, using: plan, options: options)
    }
    private func writePlanSync(_ presentation: Presentation, using plan: SavePlan, options: WriteOptions?) throws -> WriteResult {
        try write(presentation, using: plan, options: options)
    }
    @concurrent public func write(_ presentation: Presentation, to url: URL, using plan: SavePlan, options: WriteOptions? = nil) async throws -> WriteResult {
        try writePlanURLSync(presentation, to: url, using: plan, options: options)
    }
    private func writePlanURLSync(_ presentation: Presentation, to url: URL, using plan: SavePlan, options: WriteOptions?) throws -> WriteResult {
        try write(presentation, to: url, using: plan, options: options)
    }
}
