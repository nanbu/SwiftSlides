import Foundation

/// 座標を変換せず、元の独自座標領域でoperandを評価したパス。
public struct EvaluatedEnhancedPath: Sendable, Equatable, Codable {
    public let kind: EnhancedPathCommand.Kind
    public let arguments: [Double]
    public init(kind: EnhancedPathCommand.Kind, arguments: [Double]) { self.kind = kind; self.arguments = arguments }
}
public struct EnhancedGeometryEvaluation: Sendable, Equatable, Codable {
    public let guides: [String: Double]
    public let path: [EvaluatedEnhancedPath]?
    public let textAreas: [Rect]?
    public let handles: [EvaluatedGeometryHandle]
}
public struct EvaluatedGeometryHandle: Sendable, Equatable, Codable {
    public let values: [String: Double]
    public let flags: [String: Bool]
}
/// ODF enhanced-geometryの算術式。計算量・深さ・参照を制限する。
public enum GeometryEvaluator {
    public static func evaluate(_ geometry: EnhancedGeometry, variables: [String: Double] = [:], maxOperations: Int = 100_000, maxDepth: Int = 128) throws -> EnhancedGeometryEvaluation {
        guard maxOperations > 0, maxDepth > 0 else { throw SlideError.limitExceeded("geometry評価予算") }
        var formulas: [String: String] = [:]
        for guide in geometry.equations { guard formulas.updateValue(guide.formula, forKey: guide.name) == nil else { throw SlideError.invalidModel("guide重複") } }
        var values = variables, resolved: [String: Double] = [:], active = Set<String>(), remaining = maxOperations
        if let box = geometry.viewBox {
            for (name, value) in ["left": box.x, "top": box.y, "right": box.maxX, "bottom": box.maxY, "width": box.width, "height": box.height] where values[name] == nil { values[name] = value }
        }
        values["pi"] = Double.pi
        func charge() throws { try Task.checkCancellation(); remaining -= 1; guard remaining >= 0 else { throw SlideError.limitExceeded("geometry評価予算") } }
        func reference(_ name: String, _ depth: Int) throws -> Double {
            try charge(); guard depth < maxDepth else { throw SlideError.limitExceeded("geometry参照深さ") }
            if name.hasPrefix("$") { guard let index = Int(name.dropFirst()), let modifiers = geometry.modifiers, modifiers.indices.contains(index) else { throw SlideError.invalidModel("modifier参照不在") }; return modifiers[index] }
            if !name.hasPrefix("?") { guard let value = values[name], value.isFinite else { throw SlideError.invalidModel("geometry変数不在: \(name)") }; return value }
            let key = String(name.dropFirst())
            if let value = resolved[key] { return value }
            guard !active.contains(key), let formula = formulas[key] else { throw SlideError.invalidModel("guide循環/欠損: \(key)") }
            active.insert(key); defer { active.remove(key) }
            var parser = GeometryExpression(formula, maxDepth: maxDepth, reference: { try reference($0, depth + 1) }, charge: charge)
            let value = try parser.parse(); resolved[key] = value; return value
        }
        func operand(_ value: GeometryOperand) throws -> Double {
            let number: Double
            switch value { case .number(let n): try charge(); number = n; case .modifier(let i): number = try reference("$\(i)", 0); case .formula(let s): number = try reference("?" + s, 0) }
            guard number.isFinite else { throw SlideError.invalidModel("非有限geometry結果") }; return number
        }
        for guide in geometry.equations { _ = try reference("?" + guide.name, 0) }
        let path = try geometry.path.map { try $0.map { try EvaluatedEnhancedPath(kind: $0.kind, arguments: $0.arguments.map(operand)) } }
        let areas = try geometry.textAreas.map { try $0.map { area in
            let l = try operand(area.left), t = try operand(area.top), r = try operand(area.right), b = try operand(area.bottom)
            guard r >= l, b >= t else { throw SlideError.invalidModel("反転したtext area") }; return Rect(x: l, y: t, width: r - l, height: b - t)
        } }
        let handles = try geometry.handles.map { handle in
            var values: [String: Double] = [:], flags: [String: Bool] = [:]
            let namespace = "urn:oasis:names:tc:opendocument:xmlns:drawing:1.0|"
            func evaluate(_ text: String) throws -> Double {
                var parser = GeometryExpression(text, maxDepth: maxDepth, reference: { try reference($0, 0) }, charge: charge)
                return try parser.parse()
            }
            for (attribute, text) in handle.attributes where attribute.hasPrefix(namespace) {
                let name = String(attribute.dropFirst(namespace.count))
                if ["handle-mirror-vertical", "handle-mirror-horizontal", "handle-switched"].contains(name) {
                    guard ["true", "false", "1", "0"].contains(text) else { throw SlideError.invalidModel("handle真偽値") }; flags[name] = text == "true" || text == "1"
                } else if ["handle-position", "handle-polar"].contains(name) {
                    let parts = text.split(whereSeparator: \.isWhitespace)
                    guard parts.count == 2 else { throw SlideError.unsupportedContainer("handle座標式") }
                    let prefix = name == "handle-position" ? "handle-position-" : "handle-polar-pole-"
                    values[prefix + "x"] = try evaluate(String(parts[0])); values[prefix + "y"] = try evaluate(String(parts[1]))
                } else if name.hasPrefix("handle-position-") || name.hasPrefix("handle-polar-") || name.hasPrefix("handle-range-") || name.hasPrefix("handle-radius-range-") { values[name] = try evaluate(text) }
            }
            return EvaluatedGeometryHandle(values: values, flags: flags)
        }
        return .init(guides: resolved, path: path, textAreas: areas, handles: handles)
    }
}

private struct GeometryExpression {
    let input: [Character]
    let maxDepth: Int
    let reference: (String) throws -> Double
    let charge: () throws -> Void
    var position = 0
    init(_ text: String, maxDepth: Int, reference: @escaping (String) throws -> Double, charge: @escaping () throws -> Void) { input = Array(text); self.maxDepth = maxDepth; self.reference = reference; self.charge = charge }
    mutating func skip() { while position < input.count, input[position].isWhitespace { position += 1 } }
    mutating func take(_ ch: Character) -> Bool { skip(); if position < input.count, input[position] == ch { position += 1; return true }; return false }
    mutating func parse() throws -> Double { let value = try expression(0); skip(); guard position == input.count else { throw SlideError.invalidModel("geometry式の末尾字句") }; return value }
    mutating func expression(_ depth: Int, evaluating: Bool = true) throws -> Double {
        var value = try product(depth + 1, evaluating: evaluating)
        while true { if take("+") { value += try product(depth + 1, evaluating: evaluating) } else if take("-") { value -= try product(depth + 1, evaluating: evaluating) } else { break }; try charge() }
        return evaluating ? try finite(value) : 0
    }
    mutating func product(_ depth: Int, evaluating: Bool = true) throws -> Double {
        var value = try atom(depth + 1, evaluating: evaluating)
        while true { if take("*") { value *= try atom(depth + 1, evaluating: evaluating) } else if take("/") { let rhs = try atom(depth + 1, evaluating: evaluating); guard !evaluating || rhs != 0 else { throw SlideError.invalidModel("geometry式の0除算") }; if evaluating { value /= rhs } } else { break }; try charge() }
        return evaluating ? try finite(value) : 0
    }
    mutating func atom(_ depth: Int, evaluating: Bool = true) throws -> Double {
        try charge(); guard depth < maxDepth else { throw SlideError.limitExceeded("geometry式の深さ") }
        if take("+") { return try atom(depth + 1, evaluating: evaluating) }; if take("-") { return try -atom(depth + 1, evaluating: evaluating) }
        if take("(") { let v = try expression(depth + 1, evaluating: evaluating); guard take(")") else { throw SlideError.invalidModel("geometry式の括弧") }; return v }
        skip(); let start = position
        guard position < input.count else { throw SlideError.invalidModel("geometry式の欠損") }
        if input[position].isNumber || input[position] == "." {
            while position < input.count, input[position].isNumber || input[position] == "." { position += 1 }
            if position < input.count, ["e", "E"].contains(input[position]) { position += 1; if position < input.count, ["+", "-"].contains(input[position]) { position += 1 }; while position < input.count, input[position].isNumber { position += 1 } }
            guard let n = Double(String(input[start..<position])) else { throw SlideError.invalidModel("geometry式の数値") }; return evaluating ? try finite(n) : 0
        }
        if ["?", "$"].contains(input[position]) { position += 1 }
        while position < input.count, input[position].isLetter || input[position].isNumber || input[position] == "_" { position += 1 }
        guard position > start else { throw SlideError.invalidModel("geometry式の字句") }; let name = String(input[start..<position])
        if !take("(") { return evaluating ? try finite(reference(name)) : 0 }
        var args: [Double] = []
        if !take(")") { repeat { let selected = name != "if" || args.isEmpty || (args.count == 1 ? args[0] > 0 : args[0] <= 0)
                args.append(try expression(depth + 1, evaluating: evaluating && selected)) } while take(","); guard take(")") else { throw SlideError.invalidModel("geometry関数の括弧") } }
        let arity: [String: Int] = ["abs": 1, "sqrt": 1, "sin": 1, "cos": 1, "tan": 1, "atan": 1, "atan2": 2, "min": 2, "max": 2, "if": 3]
        guard arity[name] == args.count else { throw SlideError.invalidModel("geometry関数/引数数: \(name)") }
        guard evaluating else { return 0 }
        let v: Double
        switch name { case "abs": v = abs(args[0]); case "sqrt": v = sqrt(args[0]); case "sin": v = sin(args[0]); case "cos": v = cos(args[0]); case "tan": v = tan(args[0]); case "atan": v = atan(args[0]); case "atan2": v = atan2(args[0], args[1]); case "min": v = min(args[0], args[1]); case "max": v = max(args[0], args[1]); default: v = args[0] > 0 ? args[1] : args[2] }
        return try finite(v)
    }
    func finite(_ v: Double) throws -> Double { guard v.isFinite else { throw SlideError.invalidModel("非有限geometry式結果") }; return v }
}
