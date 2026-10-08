import Foundation

/// XLSXセルの保存済み値。formulaの再計算はしない。
public struct WorkbookCell: Sendable, Equatable, Codable {
    public let address: String
    public let type: String
    public let value: String?
    public let formula: String?
    /// 共有式の相対参照を解決した式。formulaは原本のまま。
    public let resolvedFormula: String?
    public let formulaAttributes: [String: String]?
    public let source: SourceXMLNode?
    public init(address: String, type: String, value: String?, formula: String? = nil, resolvedFormula: String? = nil, formulaAttributes: [String: String]? = nil, source: SourceXMLNode? = nil) { self.address = address; self.type = type; self.value = value; self.formula = formula; self.resolvedFormula = resolvedFormula; self.formulaAttributes = formulaAttributes; self.source = source }
}
public struct WorkbookSheet: Sendable, Equatable, Codable {
    public let name: String
    public let cells: [String: WorkbookCell]
    public init(name: String, cells: [String: WorkbookCell]) { self.name = name; self.cells = cells }
}
public struct WorkbookRangeResolution: Sendable, Equatable, Codable {
    public let points: [ChartPoint]
    public let pointCount: Int
    public let ranges: [WorkbookCellRange]?
    public init(points: [ChartPoint], pointCount: Int, ranges: [WorkbookCellRange]? = nil) { self.points = points; self.pointCount = pointCount; self.ranges = ranges }
}
public final class WorkbookData: Sendable, Equatable, Codable {
    public let sheets: [WorkbookSheet]
    public let definedNames: [WorkbookDefinedName]?
    public init(sheets: [WorkbookSheet], definedNames: [WorkbookDefinedName]? = nil) { self.sheets = sheets; self.definedNames = definedNames }
    public static func == (a: WorkbookData, b: WorkbookData) -> Bool { a === b || (a.sheets == b.sheets && a.definedNames == b.definedNames) }
    /// 参照式を保存済み値へ解決する。欠損cacheを0で補わず、式を再計算しない。
    public func resolve(_ formula: String, sheet: String? = nil, maxCells: Int = 1_000_000, maxDepth: Int = 128) throws -> WorkbookRangeResolution {
        try WorkbookReferenceResolver(book: self, maxCells: maxCells, maxDepth: maxDepth).resolve(formula, sheet: sheet)
    }
    package static func coordinate(_ raw: String) -> (Int, Int)? {
        var s = raw.uppercased()[...]
        if s.first == "$" { s = s.dropFirst() }
        let letters = s.prefix { $0 >= "A" && $0 <= "Z" }; s = s.dropFirst(letters.count)
        if s.first == "$" { s = s.dropFirst() }
        let digits = s
        guard !letters.isEmpty, letters.count <= 3, !digits.isEmpty, digits.count <= 7, digits.allSatisfy({ $0 >= "0" && $0 <= "9" }), let row = Int(digits), row > 0, row <= 1_048_576 else { return nil }
        let column = letters.utf8.reduce(0) { $0 * 26 + Int($1 - 64) }; guard column <= 16_384 else { return nil }; return (row, column)
    }
    package static func address(row: Int, column: Int) -> String { var n = column, text = ""; while n > 0 { n -= 1; text = String(UnicodeScalar(65 + n % 26)!) + text; n /= 26 }; return text + String(row) }
}
public enum WorkbookDataReader {
    public static func readXLSX(_ data: Data, limits: PackageLimits = .init()) throws -> WorkbookData {
        let archive = try PackageArchive(data, limits: limits)
        let namespaces = ["http://schemas.openxmlformats.org/spreadsheetml/2006/main", "http://purl.oclc.org/ooxml/spreadsheetml/main"]
        func tree(_ path: String) throws -> MarkupNode { try MarkupNode.parse(archive.read(path), part: path, limits: limits) }
        func rels(_ source: String) throws -> [String: String] {
            let root = try tree(OPCPackage.relationshipPart(for: source)); guard root.namespace == NS.rels, root.name == "Relationships" else { throw SlideError.corruptedPackage("workbook relationships") }
            var paths: [String: String] = [:], ids = Set<String>()
            for rel in root.children { guard rel.namespace == NS.rels, rel.name == "Relationship", let id = rel.attr("Id"), !id.isEmpty, ids.insert(id).inserted, rel.attr("Type") != nil, let target = rel.attr("Target") else { throw SlideError.corruptedPackage("workbook relationship不正") }; if rel.attr("TargetMode") == "External" { continue }; paths[id] = try OPCPackage.resolve(target, from: source) }
            return paths
        }
        let rootRels = try rels(""); let root = try tree("_rels/.rels")
        guard let mainID = root.children.first(where: { ($0.attr("Type") ?? "").hasSuffix("/officeDocument") })?.attr("Id"), let main = rootRels[mainID] else { throw SlideError.corruptedPackage("workbook main参照不在") }
        let workbook = try tree(main); guard workbook.name == "workbook", namespaces.contains(workbook.namespace) else { throw SlideError.unknownFormat }
        let paths = try rels(main), mainRels = try tree(OPCPackage.relationshipPart(for: main))
        var strings: [String] = []
        if let id = mainRels.children.first(where: { ($0.attr("Type") ?? "").hasSuffix("/sharedStrings") })?.attr("Id"), let path = paths[id] { let root = try tree(path); guard root.name == "sst", root.namespace == workbook.namespace else { throw SlideError.corruptedPackage("shared strings root") }; strings = root.children.filter { $0.name == "si" && $0.namespace == workbook.namespace }.map { $0.descendants("t", ns: workbook.namespace).map(\.text).joined() } }
        var result: [WorkbookSheet] = [], count = 0, names = Set<String>()
        for sheet in workbook.child("sheets", ns: workbook.namespace)?.children ?? [] {
            guard sheet.namespace == workbook.namespace, sheet.name == "sheet" else { continue }
            guard let name = sheet.attr("name"), names.insert(name.lowercased()).inserted, let id = sheet.rel("id"), let path = paths[id] else { throw SlideError.corruptedPackage("workbook sheet参照/名前") }
            let root = try tree(path); guard root.name == "worksheet", root.namespace == workbook.namespace else { throw SlideError.corruptedPackage("worksheet root") }
            var cells: [String: WorkbookCell] = [:]
            for row in root.child("sheetData", ns: root.namespace)?.children ?? [] where row.name == "row" && row.namespace == root.namespace { try Task.checkCancellation(); for cell in row.children where cell.name == "c" && cell.namespace == root.namespace {
                count += 1; guard count <= limits.maxTableCells else { throw SlideError.limitExceeded("workbookセル予算") }
                guard let raw = cell.attr("r"), let coordinate = WorkbookData.coordinate(raw) else { throw SlideError.corruptedPackage("workbookセル座標") }; let address = WorkbookData.address(row: coordinate.0, column: coordinate.1)
                guard cells[address] == nil else { throw SlideError.corruptedPackage("workbookセル重複") }
                let type = cell.attr("t") ?? "n", cached = cell.child("v", ns: root.namespace)?.text
                let value: String?
                if type == "s" { guard let cached, let i = Int(cached), strings.indices.contains(i) else { throw SlideError.corruptedPackage("shared string参照") }; value = strings[i] }
                else if type == "inlineStr" { value = cell.child("is", ns: root.namespace)?.descendants("t", ns: root.namespace).map(\.text).joined() }
                else { value = cached }
                let formula = cell.child("f", ns: root.namespace)
                cells[address] = try .init(address: address, type: type, value: value, formula: formula?.text, formulaAttributes: formula?.attributes, source: SourceXMLNode(cell))
            } }
            cells = try WorkbookFormulaResolver.expandShared(cells)
            result.append(.init(name: name, cells: cells))
        }
        var defined: [WorkbookDefinedName] = [], identities = Set<String>()
        for node in workbook.child("definedNames", ns: workbook.namespace)?.children ?? [] where node.namespace == workbook.namespace && node.name == "definedName" {
            guard let name = node.attr("name"), !name.isEmpty else { throw SlideError.corruptedPackage("workbook defined name不在") }
            var sheetName: String?
            if let raw = node.attr("localSheetId") { guard let index = Int(raw), result.indices.contains(index) else { throw SlideError.corruptedPackage("defined name scope") }; sheetName = result[index].name }
            guard identities.insert((sheetName?.lowercased() ?? "") + "!" + name.lowercased()).inserted else { throw SlideError.corruptedPackage("defined name重複") }
            defined.append(try .init(name: name, formula: node.text, sheet: sheetName, source: SourceXMLNode(node)))
        }
        return .init(sheets: result, definedNames: defined.isEmpty ? nil : defined)
    }
}
