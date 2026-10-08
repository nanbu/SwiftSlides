import Foundation
import SlideCore

/// 明示的に渡されたschemaだけでbytesを解釈する。未知fieldはfield:Nとして原wireを返す。
public struct KeynoteMessageSchema: Sendable {
    public enum ValueType: Sendable { case uint, int32, sint32, bool, float, double, string, bytes, message(String) }
    public struct Field: Sendable {
        public let name: String
        public let type: ValueType
        public let repeated: Bool
        public init(_ name: String, _ type: ValueType, repeated: Bool = false) { self.name = name; self.type = type; self.repeated = repeated }
    }
    public let fields: [UInt32: Field]
    public init(_ fields: [UInt32: Field]) { self.fields = fields }
}
public enum KeynoteSchemaReader {
    /// registryは追加版・独自extensionの明示解釈にも使える。未知版を既知版と見なさない。
    public static func read(_ data: Data, schema: String, registry: [String: KeynoteMessageSchema], limits: PackageLimits = .init()) throws -> [String: NativeValue] {
        guard data.count <= limits.maxPartBytes else { throw SlideError.limitExceeded("Keynote schema入力予算") }
        var budget = limits.maxXMLNodes
        func decode(_ data: Data, _ name: String, _ depth: Int) throws -> [String: NativeValue] {
            guard depth < limits.maxXMLDepth, let schema = registry[name] else { throw SlideError.unsupportedContainer("Keynote schema不在/深さ: \(name)") }
            let fields = try Wire.fields(data,limit:budget); budget -= fields.count
            var output: [String: NativeValue] = [:], repeated: [String: [NativeValue]] = [:]
            for field in fields {
                try Task.checkCancellation()
                guard let definition = schema.fields[field.number] else { repeated["field:\(field.number)",default:[]].append(.bytes(field.rawData)); continue }
                let value: NativeValue
                switch definition.type {
                case .uint, .int32, .sint32, .bool:
                    guard field.wireType == 0, let n = field.integer else { throw SlideError.corruptedPackage("Keynote整数wire: \(definition.name)") }
                    switch definition.type {
                    case .int32: value = .signed(Int64(Int32(truncatingIfNeeded:n)))
                    case .sint32: guard n <= UInt32.max else { throw SlideError.corruptedPackage("Keynote sint32範囲") }; value = .signed(Int64(n >> 1) ^ -Int64(n & 1))
                    case .bool: guard n <= 1 else { throw SlideError.corruptedPackage("Keynote bool範囲") }; value = .boolean(n == 1)
                    default: value = .unsigned(n)
                    }
                case .float, .double:
                    let number: Double? = { if case .float = definition.type { return field.float32.map(Double.init) }; return field.float64 }()
                    guard let number, number.isFinite else { throw SlideError.corruptedPackage("Keynote数値wire: \(definition.name)") }; value = .number(number)
                case .string: guard field.wireType == 2, let text = field.utf8 else { throw SlideError.corruptedPackage("Keynote文字列wire") }; value = .string(text)
                case .bytes: guard field.wireType == 2, let bytes = field.bytes else { throw SlideError.corruptedPackage("Keynote bytes wire") }; value = .bytes(bytes)
                case .message(let child): guard field.wireType == 2, let bytes = field.bytes else { throw SlideError.corruptedPackage("Keynote message wire") }; value = try .object(decode(bytes,child,depth+1))
                }
                if definition.repeated { repeated[definition.name,default:[]].append(value) }
                else { guard output.updateValue(value,forKey:definition.name) == nil else { throw SlideError.corruptedPackage("Keynote単一field重複: \(definition.name)") } }
            }
            for (name, values) in repeated { guard output[name] == nil else { throw SlideError.invalidModel("Keynote schemaの名前重複") }; output[name] = .array(values) }
            return output
        }
        return try decode(data,schema,0)
    }
    /// 確認済みTSCEの数式・UID/handle参照。値の再計算は行わない。
    public static let formulaSchemas: [String: KeynoteMessageSchema] = [
        "formula": .init([1:.init("nodes",.message("nodes")),2:.init("hostColumn",.uint),3:.init("hostRow",.uint),4:.init("negativeColumn",.bool),5:.init("negativeRow",.bool),6:.init("translationFlags",.message("translationFlags")),7:.init("tableUID",.message("uuid")),8:.init("columnUID",.message("uuid")),9:.init("rowUID",.message("uuid"))]),
        "nodes": .init([1:.init("tokens",.message("token"),repeated:true)]),
        "token": .init([1:.init("kind",.uint),2:.init("functionID",.uint),3:.init("argumentCount",.uint),4:.init("number",.double),5:.init("boolean",.bool),6:.init("text",.string),7:.init("date",.double),8:.init("duration",.double),9:.init("durationUnit",.int32),10:.init("tokenBoolean",.bool),11:.init("arrayColumns",.uint),12:.init("arrayRows",.uint),13:.init("listCount",.uint),14:.init("thunk",.message("nodes")),15:.init("localReference",.message("local")),16:.init("crossTableReference",.message("cross")),17:.init("unknownFunction",.string),18:.init("unknownArgumentCount",.uint),19:.init("suppressDate",.bool),20:.init("suppressTime",.bool),21:.init("dateFormat",.string),22:.init("durationStyle",.uint),23:.init("largestUnit",.uint),24:.init("smallestUnit",.uint),25:.init("whitespace",.string),26:.init("column",.message("coordinate")),27:.init("row",.message("coordinate")),28:.init("table",.message("table")),29:.init("automaticUnits",.bool),30:.init("uidCoordinate",.message("uidCoordinate")),33:.init("sticky",.message("sticky")),34:.init("letIdentifier",.string),35:.init("letWhitespace",.string),36:.init("letContinuation",.bool),37:.init("symbol",.uint),38:.init("tractList",.message("tractList")),39:.init("categoryReference",.message("categoryReference")),40:.init("colonTract",.message("colonTract")),41:.init("frozenSticky",.message("sticky")),42:.init("decimalLow",.uint),43:.init("decimalHigh",.uint),44:.init("categoryLevels",.message("levels")),45:.init("lambdaIdentifiers",.message("lambda")),46:.init("rangeContext",.uint),47:.init("upgradeKind",.uint)]),
        "translationFlags": .init([1:.init("excelImport",.bool),2:.init("removeDateCoercion",.bool),3:.init("uidReferences",.bool),4:.init("frozenReferences",.bool),5:.init("percentResult",.bool)]),
        "categoryReference": .init([1:.init("reference",.message("category"))]),
        "category": .init([1:.init("groupUID",.message("uuid")),2:.init("columnUID",.message("uuid")),3:.init("aggregateType",.uint),4:.init("groupLevel",.sint32),8:.init("relativeColumn",.int32),9:.init("relativeGroupUID",.message("uuid")),10:.init("absoluteGroupUID",.message("uuid")),11:.init("pivotRows",.bool),12:.init("pivotColumns",.bool),13:.init("aggregateIndexLevel",.uint),14:.init("showAggregateName",.bool)]),
        "coordinate": .init([1:.init("offset",.sint32),2:.init("absolute",.bool)]),
        "uuid": .init([1:.init("lower",.uint),2:.init("upper",.uint)]),
        "cfuuid": .init([1:.init("bytes",.bytes),2:.init("word0",.uint),3:.init("word1",.uint),4:.init("word2",.uint),5:.init("word3",.uint)]),
        "local": .init([1:.init("rowHandle",.uint),2:.init("columnHandle",.uint),3:.init("rowSticky",.uint),4:.init("columnSticky",.uint)]),
        "cross": .init([1:.init("rowHandle",.uint),2:.init("columnHandle",.uint),3:.init("rowSticky",.uint),4:.init("columnSticky",.uint),5:.init("tableUID",.message("cfuuid")),6:.init("beforeTable",.string),7:.init("afterTable",.string),8:.init("beforeColumn",.string),9:.init("beforeRow",.string)]),
        "table": .init([1:.init("tableUID",.message("cfuuid")),2:.init("beforeTable",.string),3:.init("afterTable",.string),4:.init("beforeColumn",.string),5:.init("beforeRow",.string)]),
        "uidCoordinate": .init([1:.init("column",.message("uuid")),2:.init("row",.message("uuid")),3:.init("absoluteColumn",.bool),4:.init("absoluteRow",.bool)]),
        "sticky": .init([1:.init("beginRowAbsolute",.bool),2:.init("beginColumnAbsolute",.bool),3:.init("endRowAbsolute",.bool),4:.init("endColumnAbsolute",.bool)]),
        "tractList": .init([1:.init("tracts",.message("tract"),repeated:true),2:.init("sticky",.message("sticky"))]),
        "tract": .init([1:.init("columns",.message("uidList")),2:.init("rows",.message("uidList")),3:.init("isRange",.bool),4:.init("purpose",.uint),5:.init("rectangular",.bool)]),
        "uidList": .init([1:.init("uids",.message("uuid"),repeated:true)]),
        "colonTract": .init([1:.init("relativeColumns",.message("relativeRange")),2:.init("relativeRows",.message("relativeRange")),3:.init("absoluteColumns",.message("absoluteRange")),4:.init("absoluteRows",.message("absoluteRange")),5:.init("rectangular",.bool)]),
        "relativeRange": .init([1:.init("begin",.int32),2:.init("end",.int32)]),
        "absoluteRange": .init([1:.init("begin",.uint),2:.init("end",.uint)]),
        "levels": .init([1:.init("columnGroup",.uint),2:.init("rowGroup",.uint),3:.init("aggregateIndex",.uint)]),
        "lambda": .init([1:.init("identifiers",.string,repeated:true),2:.init("firstSymbol",.uint),3:.init("beforeWhitespace",.string),4:.init("afterWhitespace",.string)])
    ]
}
