import Foundation

/// schemaで意味と型を確認したネイティブ値。未知のwireをmessageへ推測変換しない。
public indirect enum NativeValue: Sendable, Equatable, Codable {
    case unsigned(UInt64), signed(Int64), number(Double), boolean(Bool), string(String), bytes(Data)
    case array([NativeValue]), object([String: NativeValue])
    public subscript(_ name: String) -> NativeValue? { if case .object(let fields) = self { fields[name] } else { nil } }
}

public struct FormulaTokenDetails: Sendable, Equatable, Codable {
    /// 日時、duration、配列寸法、UID、tract、sticky、lambda識別子など。
    public let properties: [String: NativeValue]
    public let children: [FormulaToken]
    public init(properties: [String: NativeValue] = [:], children: [FormulaToken] = []) { self.properties = properties; self.children = children }
}

public struct NativeCellProperties: Sendable, Equatable, Codable {
    public let storageVersion: UInt8
    public let references: [String: UInt64]
    public let properties: [String: NativeValue]
    public let source: Data
    public init(storageVersion: UInt8, references: [String: UInt64], properties: [String: NativeValue] = [:], source: Data) { self.storageVersion = storageVersion; self.references = references; self.properties = properties; self.source = source }
}

/// parameterized pathの意味と調整値。プリセットへの近似・描画はしない。
public struct NativeGeometry: Sendable, Equatable, Codable {
    public let dialect: String
    public let kind: String
    public let properties: [String:NativeValue]
    public let source: Data
    public init(dialect: String, kind: String, properties: [String:NativeValue], source: Data) { self.dialect = dialect; self.kind = kind; self.properties = properties; self.source = source }
}
