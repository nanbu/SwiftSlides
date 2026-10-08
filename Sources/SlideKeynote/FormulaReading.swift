import Foundation
import SlideCore

extension KeynoteSource {
    func nativeFormula(_ data: Data, row: Int, column: Int) throws -> CellFormula {
        let formula = try fields(data)
        guard let array = try child(formula, 1) else { throw SlideError.corruptedPackage("Keynote式のnode配列不在") }
        let kinds: [UInt64: String] = [1: "ADDITION_NODE", 2: "SUBTRACTION_NODE", 3: "MULTIPLICATION_NODE", 4: "DIVISION_NODE", 5: "POWER_NODE", 6: "CONCATENATION_NODE", 7: "GREATER_THAN_NODE", 8: "GREATER_THAN_OR_EQUAL_TO_NODE", 9: "LESS_THAN_NODE", 10: "LESS_THAN_OR_EQUAL_TO_NODE", 11: "EQUAL_TO_NODE", 12: "NOT_EQUAL_TO_NODE", 13: "NEGATION_NODE", 14: "PLUS_SIGN_NODE", 15: "PERCENT_NODE", 16: "FUNCTION_NODE", 17: "NUMBER_NODE", 18: "BOOLEAN_NODE", 19: "STRING_NODE", 20: "DATE_NODE", 21: "DURATION_NODE", 22: "EMPTY_ARGUMENT_NODE", 23: "TOKEN_NODE", 24: "ARRAY_NODE", 25: "LIST_NODE", 26: "THUNK_NODE", 27: "LOCAL_CELL_REFERENCE_NODE", 28: "CROSS_TABLE_CELL_REFERENCE_NODE", 29: "COLON_NODE", 30: "REFERENCE_ERROR_NODE", 31: "UNKNOWN_FUNCTION_NODE", 32: "APPEND_WHITESPACE_NODE", 33: "PREPEND_WHITESPACE_NODE", 34: "BEGIN_THUNK_NODE", 35: "END_THUNK_NODE", 36: "CELL_REFERENCE_NODE", 45: "COLON_NODE_WITH_UIDS", 46: "REFERENCE_ERROR_WITH_UIDS", 48: "UID_REFERENCE_NODE", 52: "LET_BIND_NODE", 53: "VAR_NODE", 54: "END_SCOPE_NODE", 55: "LAMBDA_NODE", 56: "BEGIN_LAMBDA_THUNK_NODE", 57: "END_LAMBDA_THUNK_NODE", 63: "LINKED_CELL_REF_NODE", 64: "LINKED_COLUMN_REF_NODE", 65: "LINKED_ROW_REF_NODE", 66: "CATEGORY_REF_NODE", 67: "COLON_TRACT_NODE", 68: "VIEW_TRACT_REF_NODE", 69: "INTERSECTION_NODE", 70: "SPILL_RANGE_NODE"]
        var context = try KeynoteSchemaReader.read(data, schema: "formula", registry: KeynoteSchemaReader.formulaSchemas, limits: options.limits)
        let decodedNodes = context.removeValue(forKey: "nodes")
        var budget = options.limits.maxXMLNodes
        func parseTokens(_ array: [KeynoteField], decoded: NativeValue?, depth: Int) throws -> [FormulaToken] {
        guard depth < options.limits.maxXMLDepth else { throw SlideError.limitExceeded("Keynote式の入れ子深さ") }
        let decodedTokens: [NativeValue]
        if case .array(let values) = decoded?["tokens"] { decodedTokens = values } else { decodedTokens = [] }
        var tokens: [FormulaToken] = []
        for (index, field) in array.filter({ $0.number == 1 }).enumerated() {
            budget -= 1; guard budget >= 0 else { throw SlideError.limitExceeded("Keynote式token予算") }
            guard let source = field.bytes else { throw SlideError.corruptedPackage("Keynote式nodeのwire型") }
            let f = try fields(source), type = try Wire.scalar(f, 1)
            func coordinate(_ field: UInt32, base: Int) throws -> (Int?, Bool?) {
                guard let value = try child(f, field) else { return (nil, nil) }
                let raw = try Wire.scalar(value, 1); guard raw <= UInt64(UInt32.max) else { throw SlideError.corruptedPackage("Keynote式の座標桁あふれ") }
                let offset = Int(Int64(raw >> 1) ^ -Int64(raw & 1)), absolute = try Self.optionalInteger(value, 2).map { $0 != 0 } ?? false
                return (absolute ? offset : base + offset, absolute)
            }
            let r = try coordinate(27, base: row), c = try coordinate(26, base: column)
            let number = try number(f, 4), text = try Self.string(f, type == 31 ? 17 : 6)
            let bool = try Self.optionalInteger(f, type == 23 ? 10 : 5).map { $0 != 0 }
            var token = try FormulaToken(kind: kinds[type] ?? "native:\(type)", number: number, text: text, boolean: bool, functionID: Self.optionalInteger(f, 2), argumentCount: Self.optionalInteger(f, type == 31 ? 18 : 3), row: r.0, column: c.0, absoluteRow: r.1, absoluteColumn: c.1, source: source)
            var properties: [String: NativeValue] = [:]
            if decodedTokens.indices.contains(index), case .object(let values) = decodedTokens[index] { properties = values }
            let nestedValue = properties.removeValue(forKey: "thunk")
            let nested = try child(f, 14).map { try parseTokens($0, decoded: nestedValue, depth: depth + 1) } ?? []
            token.details = .init(properties: properties, children: nested)
            tokens.append(token)
        }
        return tokens
        }
        return .init(dialect: "keynote:TSCE", tokens: try parseTokens(array, decoded: decodedNodes, depth: 0), source: data, context: context)
    }
    func applyMerges(model: [KeynoteField], store: [KeynoteField], table: inout Table) throws {
        var ranges: [(Int, Int, Int, Int)] = []
        if store.contains(where: { $0.number == 13 }) {
            let map = try object(ref(store, 13))
            guard map.type == 6144 else { throw SlideError.corruptedPackage("Keynote merge map型") }
            for field in map.fields where field.number == 1 {
                let f = try field.message(maxFields: options.limits.maxXMLNodes)
                func packed(_ n: UInt32) throws -> UInt32 {
                    guard let message = try child(f, n), let bits = message.first(where: { $0.number == 1 })?.bytes, bits.count == 4 else { throw SlideError.corruptedPackage("Keynote結合領域のpacked値") }
                    return bits.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) }
                }
                let origin = try packed(1), size = try packed(2)
                ranges.append((Int(origin & 0xffff), Int(origin >> 16), Int(size & 0xffff), Int(size >> 16)))
            }
        }
        if ranges.isEmpty, let owner = try child(model, 47), let store = try child(owner, 2) {
            for pair in store where pair.number == 3 {
                let f = try pair.message(maxFields: options.limits.maxXMLNodes)
                guard let formula = try child(f, 2), let array = try child(formula, 1) else { throw SlideError.corruptedPackage("Keynote merge式不在") }
                for node in array where node.number == 1 {
                    let f = try node.message(maxFields: options.limits.maxXMLNodes)
                    let kind = try Wire.scalar(f, 1)
                    // 現行producerのmerge ownerはrangeを関数168で包む。
                    if kind == 16, try Wire.scalar(f, 2) == 168, try Wire.scalar(f, 3) == 1 { continue }
                    if [32, 33].contains(kind) { continue }
                    guard kind == 67, let tract = try child(f, 40) else { throw SlideError.unsupportedContainer("Keynote mergeの式種別") }
                    func range(_ n: UInt32) throws -> (Int, Int) {
                        guard let f = try child(tract, n), let begin = try Self.optionalInteger(f, 1), begin <= (try Self.optionalInteger(f, 2) ?? begin), (try Self.optionalInteger(f, 2) ?? begin) <= UInt64(Int.max) else { throw SlideError.corruptedPackage("Keynote結合のrange") }; let end = try Self.optionalInteger(f, 2) ?? begin; return (Int(begin), Int(end - begin + 1))
                    }
                    let r = try range(4), c = try range(3); ranges.append((r.0, c.0, r.1, c.1))
                }
            }
        }
        var occupied = Set<Int>(), columns = table.columnWidths.count
        for (r, c, nr, nc) in ranges {
            guard r >= 0, c >= 0, nr > 0, nc > 0, r < table.rows.count, c < columns, nr <= table.rows.count - r, nc <= columns - c else { throw SlideError.corruptedPackage("Keynote結合領域の範囲") }
            for row in r..<r + nr { for col in c..<c + nc {
                guard occupied.insert(row * columns + col).inserted else { throw SlideError.corruptedPackage("Keynote結合領域の重複") }
                if row == r && col == c { table.rows[row][col].rowSpan = nr; table.rows[row][col].columnSpan = nc } else { table.rows[row][col].isMergeContinuation = true }
            } }
        }
    }
}
