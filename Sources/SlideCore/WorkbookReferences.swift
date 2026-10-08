import Foundation

public struct WorkbookDefinedName: Sendable, Equatable, Codable {
    public let name: String
    public let formula: String
    /// nilはworkbook scope。
    public let sheet: String?
    public let source: SourceXMLNode?
    public init(name: String, formula: String, sheet: String? = nil, source: SourceXMLNode? = nil) { self.name = name; self.formula = formula; self.sheet = sheet; self.source = source }
}
public struct WorkbookCellRange: Sendable, Equatable, Codable {
    public let sheet: String
    public let firstRow: Int
    public let firstColumn: Int
    public let lastRow: Int
    public let lastColumn: Int
    public init(sheet: String, firstRow: Int, firstColumn: Int, lastRow: Int, lastColumn: Int) { self.sheet = sheet; self.firstRow = firstRow; self.firstColumn = firstColumn; self.lastRow = lastRow; self.lastColumn = lastColumn }
}

/// 参照演算だけを解釈し、SUM/OFFSET等の式の再計算と混同しない。
struct WorkbookReferenceResolver {
    let book: WorkbookData
    let maxCells: Int
    let maxDepth: Int
    private enum Token: Equatable { case atom(String), comma, space, open, close }
    func resolve(_ formula: String, sheet: String?) throws -> WorkbookRangeResolution {
        guard maxCells > 0, maxDepth > 0 else { throw SlideError.invalidModel("workbook参照予算") }
        var budget = maxCells
        let ranges = try expression(formula, sheet: sheet, seen: [], depth: 0, budget: &budget)
        var points: [ChartPoint] = [], count = 0
        for range in ranges {
            guard let source = book.sheets.first(where: { $0.name.caseInsensitiveCompare(range.sheet) == .orderedSame }) else { throw SlideError.missingPart(range.sheet) }
            let width = range.lastColumn - range.firstColumn + 1, height = range.lastRow - range.firstRow + 1
            guard width > 0, height > 0, height <= (maxCells - count) / width else { throw SlideError.limitExceeded("workbook参照セル数") }
            // 疎なsheetの保存値だけを走査し、空の巨大矩形を展開しない。
            for cell in source.cells.values {
                try Task.checkCancellation()
                guard let (row, column) = WorkbookData.coordinate(cell.address), row >= range.firstRow, row <= range.lastRow, column >= range.firstColumn, column <= range.lastColumn, let value = cell.value else { continue }
                points.append(.init(index: count + (row - range.firstRow) * width + column - range.firstColumn, text: value))
            }
            count += width * height
        }
        return .init(points: points.sorted { $0.index < $1.index }, pointCount: count, ranges: ranges)
    }
    private func lex(_ text: String) throws -> [Token] {
        let chars = Array(text.trimmingCharacters(in: .whitespacesAndNewlines)); var i = chars.first == "=" ? 1 : 0, result: [Token] = []
        while i < chars.count {
            if chars[i].isWhitespace { while i < chars.count && chars[i].isWhitespace { i += 1 }; result.append(.space); continue }
            switch chars[i] { case ",": result.append(.comma); i += 1; continue; case "(": result.append(.open); i += 1; continue; case ")": result.append(.close); i += 1; continue; default: break }
            let start = i; var quote = false, bracket = 0
            while i < chars.count {
                let c = chars[i]
                if c == "'" { if quote && i + 1 < chars.count && chars[i + 1] == "'" { i += 2; continue }; quote.toggle() }
                else if !quote {
                    if c == "[" { bracket += 1 }; if c == "]" { bracket -= 1; guard bracket >= 0 else { throw SlideError.invalidModel("参照の角括弧") } }
                    if bracket == 0 && (c.isWhitespace || [",", "(", ")"].contains(c)) { break }
                }
                i += 1
            }
            guard !quote, bracket == 0, i > start else { throw SlideError.invalidModel("参照の引用符/括弧") }
            result.append(.atom(String(chars[start..<i])))
        }
        // 区切りの周囲の空白だけを除き、参照同士の空白はintersectionとして残す。
        return result.enumerated().compactMap { index, token in
            guard token == .space else { return token }
            guard index > 0, index + 1 < result.count, result[index - 1] != .comma, result[index - 1] != .open, result[index + 1] != .comma, result[index + 1] != .close else { return nil }; return token
        }
    }
    private func expression(_ text: String, sheet: String?, seen: Set<String>, depth: Int, budget: inout Int) throws -> [WorkbookCellRange] {
        guard depth < maxDepth else { throw SlideError.limitExceeded("workbook参照深さ") }
        let tokens = try lex(text); var index = 0
        func primary(_ level: Int, _ budget: inout Int) throws -> [WorkbookCellRange] {
            try Task.checkCancellation(); budget -= 1
            guard budget >= 0, level < maxDepth else { throw SlideError.limitExceeded("workbook参照解析予算") }
            guard index < tokens.count else { throw SlideError.invalidModel("workbook参照欠損") }
            switch tokens[index] {
            case .atom(let atom): index += 1; return try resolveAtom(atom, sheet: sheet, seen: seen, depth: depth + 1, budget: &budget)
            case .open: index += 1; let ranges = try union(level + 1, &budget); guard index < tokens.count, tokens[index] == .close else { throw SlideError.invalidModel("参照式の括弧") }; index += 1; return ranges
            default: throw SlideError.invalidModel("参照式の字句")
            }
        }
        func intersection(_ level: Int, _ budget: inout Int) throws -> [WorkbookCellRange] {
            var lhs = try primary(level, &budget)
            while index < tokens.count, tokens[index] == .space {
                index += 1; let rhs = try primary(level, &budget); var output: [WorkbookCellRange] = []
                for a in lhs { for b in rhs where a.sheet == b.sheet {
                    budget -= 1; guard budget >= 0 else { throw SlideError.limitExceeded("workbook intersection予算") }
                    let r1 = max(a.firstRow, b.firstRow), r2 = min(a.lastRow, b.lastRow), c1 = max(a.firstColumn, b.firstColumn), c2 = min(a.lastColumn, b.lastColumn)
                    if r1 <= r2 && c1 <= c2 { output.append(.init(sheet: a.sheet, firstRow: r1, firstColumn: c1, lastRow: r2, lastColumn: c2)) }
                } }
                lhs = output
            }
            return lhs
        }
        func union(_ level: Int, _ budget: inout Int) throws -> [WorkbookCellRange] {
            var ranges = try intersection(level, &budget)
            while index < tokens.count, tokens[index] == .comma { index += 1; ranges += try intersection(level, &budget) }
            return ranges
        }
        let result = try union(depth, &budget)
        guard index == tokens.count else { throw SlideError.unsupportedContainer("値の計算を必要とするworkbook式") }
        return result
    }
    private func resolveAtom(_ atom: String, sheet scope: String?, seen: Set<String>, depth: Int, budget: inout Int) throws -> [WorkbookCellRange] {
        var reference = atom, qualifier = scope
        if let bang = atom.lastIndex(of: "!") { qualifier = String(atom[..<bang]); reference = String(atom[atom.index(after: bang)...]) }
        func unquote(_ s: String) -> String { s.hasPrefix("'") && s.hasSuffix("'") ? String(s.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'") : s }
        if let q = qualifier { qualifier = unquote(q) }
        if let q = qualifier, q.hasPrefix("["), let end = q.firstIndex(of: "]") { qualifier = String(q[q.index(after: end)...]) }
        if let qualifier, !qualifier.contains(":"), !book.sheets.contains(where: { $0.name.caseInsensitiveCompare(qualifier) == .orderedSame }) { throw SlideError.missingPart("workbook sheet: \(qualifier)") }
        let name = (book.definedNames ?? []).first { $0.name.caseInsensitiveCompare(reference) == .orderedSame && $0.sheet?.lowercased() == qualifier?.lowercased() }
            ?? (book.definedNames ?? []).first { $0.name.caseInsensitiveCompare(reference) == .orderedSame && $0.sheet == nil }
        if let name {
            let key = (name.sheet ?? "") + "!" + name.name.lowercased()
            guard !seen.contains(key) else { throw SlideError.invalidModel("名前付き範囲の循環: \(name.name)") }
            return try expression(name.formula, sheet: name.sheet ?? qualifier, seen: seen.union([key]), depth: depth, budget: &budget)
        }
        guard let qualifier else { throw SlideError.unsupportedContainer("sheetまたは名前付き範囲が必要です") }
        let sheetNames = qualifier.split(separator: ":", omittingEmptySubsequences: false).map { unquote(String($0)) }
        guard (1...2).contains(sheetNames.count), let firstSheet = book.sheets.firstIndex(where: { $0.name.caseInsensitiveCompare(sheetNames[0]) == .orderedSame }), let lastSheet = book.sheets.firstIndex(where: { $0.name.caseInsensitiveCompare(sheetNames.last!) == .orderedSame }) else { throw SlideError.missingPart("workbook sheet: \(qualifier)") }
        let endpoints = reference.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (1...2).contains(endpoints.count) else { throw SlideError.unsupportedContainer("workbook参照の範囲") }
        func endpoint(_ text: String, last: Bool) -> (Int, Int)? {
            if let cell = WorkbookData.coordinate(text) { return cell }
            guard endpoints.count == 2 else { return nil }
            let raw = text.hasPrefix("$") ? String(text.dropFirst()) : text
            if !raw.isEmpty, raw.allSatisfy(\.isNumber), let row = Int(raw), (1...1_048_576).contains(row) { return (row, last ? 16_384 : 1) }
            if let col = WorkbookData.coordinate(raw + "1") { return (last ? 1_048_576 : 1, col.1) }
            return nil
        }
        func kind(_ raw: String) -> Int { if WorkbookData.coordinate(raw) != nil { return 0 }; let value = raw.replacingOccurrences(of:"$",with:""); return value.allSatisfy(\.isNumber) ? 1 : 2 }
        guard kind(endpoints[0]) == kind(endpoints.last!) else { throw SlideError.invalidModel("workbookの混在した範囲端点") }
        guard let a = endpoint(endpoints[0], last: false), let b = endpoint(endpoints.last!, last: true), a.0 <= b.0, a.1 <= b.1 else { throw SlideError.unsupportedContainer("workbookの未解決参照: \(reference)") }
        return (min(firstSheet, lastSheet)...max(firstSheet, lastSheet)).map { .init(sheet: book.sheets[$0].name, firstRow: a.0, firstColumn: a.1, lastRow: b.0, lastColumn: b.1) }
    }
}

public enum WorkbookFormulaResolver {
    /// A1参照だけを平行移動する。文字列、引用したsheet名、絶対行/列は変えない。
    public static func translate(_ formula: String, from source: String, to destination: String) throws -> String {
        guard let a = WorkbookData.coordinate(source), let b = WorkbookData.coordinate(destination) else { throw SlideError.invalidModel("共有数式の座標") }
        let text = formula as NSString, regex = try NSRegularExpression(pattern: #"(\$?)([A-Za-z]{1,3})(\$?)([1-9][0-9]{0,6})"#)
        let whole = try NSRegularExpression(pattern:#"(\$?)([A-Za-z]{1,3}|[1-9][0-9]{0,6})(\s*:\s*)(\$?)([A-Za-z]{1,3}|[1-9][0-9]{0,6})"#)
        var index = 0, output: [UInt16] = [], quote: UInt16?, brackets = 0
        func word(_ c: UInt16) -> Bool { c >= 128 || (65...90).contains(c) || (97...122).contains(c) || (48...57).contains(c) || [95, 46].contains(c) }
        while index < text.length {
            let c = text.character(at: index)
            if let delimiter = quote {
                output.append(text.character(at: index)); index += 1
                if c == delimiter { if index < text.length && text.character(at: index) == delimiter { output.append(text.character(at: index)); index += 1 } else { quote = nil } }; continue
            }
            if c == 34 || c == 39 { quote = c }
            if c == 91 { brackets += 1 }; if c == 93 { brackets -= 1 }
            if quote == nil, brackets == 0, (index == 0 || !word(text.character(at:index-1))), let range = whole.firstMatch(in:formula,options:.anchored,range:NSRange(location:index,length:text.length-index)) {
                let end = NSMaxRange(range.range), suffix = end < text.length ? text.character(at:end) : 0
                let first = text.substring(with:range.range(at:2)), last = text.substring(with:range.range(at:5)), columns = first.first?.isLetter == true
                if suffix != 33, !word(suffix), columns == (last.first?.isLetter == true) {
                    func translated(_ value: String, absolute: Bool) throws -> String {
                        let original = columns ? WorkbookData.coordinate(value+"1")?.1 : Int(value)
                        guard let original else { throw SlideError.corruptedPackage("共有式の行/列参照") }
                        let n = original + (absolute ? 0 : columns ? b.1-a.1 : b.0-a.0)
                        guard n >= 1, n <= (columns ? 16_384 : 1_048_576) else { return "#REF!" }
                        return (absolute ? "$" : "") + (columns ? String(WorkbookData.address(row:1,column:n).dropLast()) : String(n))
                    }
                    let value = try translated(first,absolute:range.range(at:1).length > 0)+text.substring(with:range.range(at:3))+translated(last,absolute:range.range(at:4).length > 0)
                    output.append(contentsOf:value.utf16); index = end; continue
                }
            }
            if quote == nil, brackets == 0, (index == 0 || !word(text.character(at: index - 1))), let match = regex.firstMatch(in: formula, options: .anchored, range: NSRange(location: index, length: text.length - index)), NSMaxRange(match.range) == text.length || !word(text.character(at: NSMaxRange(match.range))) {
                let end = NSMaxRange(match.range), suffix = end < text.length ? text.character(at: end) : 0
                if suffix != 33 && suffix != 40, let cell = WorkbookData.coordinate(text.substring(with: match.range)) {
                    let absColumn = match.range(at: 1).length > 0, absRow = match.range(at: 3).length > 0
                    let row = cell.0 + (absRow ? 0 : b.0 - a.0), column = cell.1 + (absColumn ? 0 : b.1 - a.1)
                    if !(1...1_048_576).contains(row) || !(1...16_384).contains(column) { output.append(contentsOf: "#REF!".utf16) }
                    else { let address = WorkbookData.address(row: row, column: column), letters = address.prefix(while: { $0.isLetter }); output.append(contentsOf: ((absColumn ? "$" : "") + letters + (absRow ? "$" : "") + String(row)).utf16) }
                    index = end; continue
                }
            }
            output.append(text.character(at: index)); index += 1
        }
        guard quote == nil, brackets == 0 else { throw SlideError.corruptedPackage("共有数式の文字列/角括弧") }
        return String(decoding: output, as: UTF16.self)
    }
    static func expandShared(_ cells: [String: WorkbookCell]) throws -> [String: WorkbookCell] {
        var masters: [String: WorkbookCell] = [:]
        for cell in cells.values where cell.formulaAttributes?["t"] == "shared" {
            guard let id = cell.formulaAttributes?["si"], UInt64(id) != nil else { throw SlideError.corruptedPackage("共有数式ID不在") }
            if let formula = cell.formula, !formula.isEmpty { guard masters.updateValue(cell, forKey: id) == nil else { throw SlideError.corruptedPackage("共有数式master重複") } }
        }
        var result = cells
        for cell in cells.values where cell.formulaAttributes?["t"] == "shared" {
            try Task.checkCancellation()
            guard let id = cell.formulaAttributes?["si"], let master = masters[id], let formula = master.formula else { throw SlideError.corruptedPackage("共有数式master不在") }
            if let ref = master.formulaAttributes?["ref"] {
                let ends = ref.split(separator: ":").map(String.init)
                guard (1...2).contains(ends.count), let first = WorkbookData.coordinate(ends[0]), let last = WorkbookData.coordinate(ends.last!), let position = WorkbookData.coordinate(cell.address), position.0 >= first.0, position.0 <= last.0, position.1 >= first.1, position.1 <= last.1 else { throw SlideError.corruptedPackage("共有数式範囲外") }
            }
            result[cell.address] = .init(address: cell.address, type: cell.type, value: cell.value, formula: cell.formula, resolvedFormula: try translate(formula, from: master.address, to: cell.address), formulaAttributes: cell.formulaAttributes, source: cell.source)
        }
        return result
    }
}
