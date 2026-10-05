/// 形式全体の操作別能力。個別文書の保存可否は保存処理で検査する。
public enum CapabilityOperation: String, Sendable, Codable, CaseIterable {
    case inspect, read, create, edit, preserve, convert, render, play
}

/// 未検証を対応済みとして扱わないための状態。
public enum CapabilityStatus: String, Sendable, Codable {
    case supported, partial, preserveOnly, unsupported, notApplicable, unverified
}

/// codecが宣言する能力概要。未記載の操作はunverified。
public struct CodecCapabilities: Sendable, Equatable, Codable {
    public var format: PresentationFormat
    public var operations: [CapabilityOperation: CapabilityStatus]
    public var notes: String
    public var features: [FeatureCapability]
    public init(format: PresentationFormat, operations: [CapabilityOperation: CapabilityStatus] = [:], notes: String = "", features: [FeatureCapability] = []) {
        self.format = format; self.operations = operations; self.notes = notes; self.features = features
    }
    public subscript(_ operation: CapabilityOperation) -> CapabilityStatus { operations[operation] ?? .unverified }
    /// 完全に一致する宣言だけを返す。未掲載・重複した宣言は未検証。
    public func capability(for feature: FeatureID, operation: CapabilityOperation, profile: CapabilityProfile) -> FeatureCapability {
        let matches = features.filter { $0.feature == feature && $0.operation == operation && $0.profile == profile }
        guard matches.count == 1, let result = matches.first else {
            return .init(feature: feature, profile: profile, operation: operation, status: .unverified)
        }
        return result
    }

    private enum CodingKeys: String, CodingKey { case format, operations, notes, features }
    /// 詳細能力のない旧JSONも読める。
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        format = try values.decode(PresentationFormat.self, forKey: .format)
        operations = try values.decode([CapabilityOperation: CapabilityStatus].self, forKey: .operations)
        notes = try values.decode(String.self, forKey: .notes)
        features = try values.decodeIfPresent([FeatureCapability].self, forKey: .features) ?? []
    }
}

/// 機能台帳と診断で共通に使う拡張可能なID。未知IDを削除しない。
public struct FeatureID: RawRepresentable, Sendable, Hashable, Codable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: any Encoder) throws { var value = encoder.singleValueContainer(); try value.encode(rawValue) }
}

/// 詳細能力の対象。文書自体のプロファイル判定・保存指定とは独立した照会用の値。
public struct CapabilityProfile: RawRepresentable, Sendable, Hashable, Codable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: any Encoder) throws { var value = encoder.singleValueContainer(); try value.encode(rawValue) }
    public static let ooxmlTransitional: Self = "ooxmlTransitional"
    public static let ooxmlStrict: Self = "ooxmlStrict"
    public static let odf12: Self = "odf12"
    public static let odf13: Self = "odf13"
    public static let odf14: Self = "odf14"
}

/// 回帰検査の定義への参照。実行結果や実アプリ互換性の保証ではない。
public struct CapabilityEvidence: Sendable, Equatable, Codable {
    public let id: String
    /// Tests/SwiftSlidesTests/Fixtures内の架空fixture名。
    public let fixture: String
    public let fixtureSHA256: String
    public let test: String
    /// 加工条件と、検査が証明する限定範囲。
    public let scope: String
    public init(id: String, fixture: String, fixtureSHA256: String, test: String, scope: String) {
        self.id = id; self.fixture = fixture; self.fixtureSHA256 = fixtureSHA256; self.test = test; self.scope = scope
    }
}

/// 一つの機能・プロファイル・操作に限った能力宣言。
public struct FeatureCapability: Sendable, Equatable, Codable {
    public let feature: FeatureID
    public let profile: CapabilityProfile
    public let operation: CapabilityOperation
    public let status: CapabilityStatus
    public let evidence: [CapabilityEvidence]
    public let notes: String
    public init(feature: FeatureID, profile: CapabilityProfile, operation: CapabilityOperation, status: CapabilityStatus,
                evidence: [CapabilityEvidence] = [], notes: String = "") {
        self.feature = feature; self.profile = profile; self.operation = operation; self.status = status
        self.evidence = evidence; self.notes = notes
    }
}

/// 原本を展開せず取得する概要。未知依存の完全な列挙ではない。
public struct PreservationSummary: Sendable, Equatable, Codable {
    public let sourceFormat: PresentationFormat?
    public let hasOriginal: Bool
    public let originalBytes: Int
    public let retainedPartCount: Int
    /// 現在のモデル内にあるopaque要素。グループ内も含む。
    public let opaqueElementCount: Int
    /// 読取時の診断。現在の編集内容の診断ではない。
    public let warningCounts: [SlideWarning.Code: Int]
}

extension Presentation {
    public var preservationSummary: PreservationSummary {
        var opaque = 0
        var pending = slides.flatMap(\.elements)
        while let element = pending.popLast() {
            if element.kind == .opaque { opaque += 1 }
            pending.append(contentsOf: element.children)
        }
        var counts: [SlideWarning.Code: Int] = [:]
        for warning in readWarnings { counts[warning.code, default: 0] += warning.count }
        return .init(sourceFormat: sourceFormat, hasOriginal: storage != nil,
                     originalBytes: storage?.data.count ?? 0, retainedPartCount: storage?.archive.paths.count ?? 0,
                     opaqueElementCount: opaque, warningCounts: counts)
    }
}
