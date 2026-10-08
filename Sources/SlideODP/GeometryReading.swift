import Foundation
import SlideCore

private enum EnhancedToken { case command(String), operand(GeometryOperand) }

extension ODPPageParser {
    func enhancedGeometry(_ node: MarkupNode, elementID: String) throws -> EnhancedGeometry {
        func number(_ raw: String) throws -> Double {
            guard let value = Double(raw), value.isFinite else { throw SlideError.corruptedPackage("不正なODP geometry数値") }
            return value
        }
        func boolean(_ name: String) throws -> Bool? {
            guard let raw = node.odf(ODF.draw, name) else { return nil }
            switch raw { case "true", "1": return true; case "false", "0": return false
            default: throw SlideError.corruptedPackage("不正なODP geometry真偽値") }
        }
        var viewBox: Rect?
        if let raw = node.odf(ODF.svg, "viewBox") {
            let values = try raw.split(maxSplits: 4, whereSeparator: \.isWhitespace).map { try number(String($0)) }
            guard values.count == 4, values[2] >= 0, values[3] >= 0 else { throw SlideError.corruptedPackage("不正なODP viewBox") }
            viewBox = .init(x: values[0], y: values[1], width: values[2], height: values[3])
        }
        let modifiers = try node.odf(ODF.draw, "modifiers").map { raw in
            let values = raw.split(maxSplits: options.limits.maxXMLNodes, whereSeparator: \.isWhitespace)
            guard values.count <= options.limits.maxXMLNodes else { throw SlideError.limitExceeded("ODP modifier予算") }
            return try values.map { try number(String($0)) }
        }
        var equations: [GeometryGuide] = [], names = Set<String>()
        for equation in node.children(ODF.draw, "equation") {
            guard let name = equation.odf(ODF.draw, "name"), !name.isEmpty, names.insert(name).inserted,
                  let formula = equation.odf(ODF.draw, "formula"), !formula.isEmpty else {
                throw SlideError.corruptedPackage("ODP geometry guideが欠損または重複")
            }
            equations.append(.init(name: name, formula: formula))
        }
        // 数字の指数内のEを命令へ切り分けない。guide名は区切りまで一つの参照とする。
        let lexer = try NSRegularExpression(pattern: #"\$[0-9]+|\?[^\s,]+|(?i:[+-]?(?:NaN|Infinity|INF))|[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?|[A-Za-z]+"#)
        func tokens(_ raw: String) throws -> [EnhancedToken]? {
            let text = raw as NSString
            var cursor = 0, result: [EnhancedToken] = []
            while cursor < text.length {
                try Task.checkCancellation()
                let scalar = text.character(at: cursor)
                if [9, 10, 13, 32, 44].contains(scalar) { cursor += 1; continue }
                guard result.count < options.limits.maxXMLNodes else { throw SlideError.limitExceeded("ODP geometry token予算") }
                guard let match = lexer.firstMatch(in: raw, options: .anchored, range: NSRange(location: cursor, length: text.length - cursor)) else { return nil }
                let token = text.substring(with: match.range); cursor = NSMaxRange(match.range)
                if token.hasPrefix("$") {
                    guard let index = Int(token.dropFirst()), let modifiers, modifiers.indices.contains(index) else { throw SlideError.corruptedPackage("欠損ODP modifier参照") }
                    result.append(.operand(.modifier(index)))
                } else if token.hasPrefix("?") {
                    let name = String(token.dropFirst())
                    guard names.contains(name) else { throw SlideError.corruptedPackage("欠損ODP guide参照: \(name)") }
                    result.append(.operand(.formula(name)))
                } else if token.first?.isLetter == true {
                    if ["nan", "inf", "infinity"].contains(token.lowercased()) { throw SlideError.corruptedPackage("非有限ODP geometry数値") }
                    // 区切りなしのZNなども個別命令として読む。
                    guard token.count <= options.limits.maxXMLNodes - result.count else { throw SlideError.limitExceeded("ODP geometry token予算") }
                    result += token.map { .command(String($0)) }
                } else { result.append(.operand(.number(try number(token)))) }
            }
            return result
        }
        var path: [EnhancedPathCommand]?
        if let raw = node.odf(ODF.draw, "enhanced-path") {
            if let values = try tokens(raw) {
                var parsed: [EnhancedPathCommand] = [], current: EnhancedPathCommand.Kind?, arguments: [GeometryOperand] = []
                let arities: [EnhancedPathCommand.Kind: Int] = [.move: 2, .line: 2, .cubic: 6, .quadratic: 4, .close: 0, .end: 0,
                    .noFill: 0, .noStroke: 0, .arcTo: 8, .arc: 8, .angleEllipseTo: 6, .angleEllipse: 6,
                    .clockwiseArc: 8, .clockwiseArcTo: 8, .ellipticalQuadrantX: 2, .ellipticalQuadrantY: 2]
                func flush() throws {
                    guard let current else {
                        guard arguments.isEmpty else { throw SlideError.corruptedPackage("ODP pathに先頭命令がありません") }; return
                    }
                    let arity = arities[current]!
                    guard arity == 0 ? arguments.isEmpty : !arguments.isEmpty && arguments.count.isMultiple(of: arity) else {
                        throw SlideError.corruptedPackage("ODP path命令\(current.rawValue)の引数数が不正")
                    }
                    parsed.append(.init(kind: current, arguments: arguments)); arguments = []
                }
                var unknown = false
                for value in values {
                    switch value {
                    case .command(let code):
                        guard let kind = EnhancedPathCommand.Kind(rawValue: code) else { unknown = true; break }
                        try flush(); current = kind
                    case .operand(let operand): arguments.append(operand)
                    }
                    if unknown { break }
                }
                if !unknown { try flush(); path = parsed }
            }
            if path == nil { warn(node, "未知のenhanced path命令/字句は未解決として原本に保持します", code: .uninterpretedFormatting, id: elementID, feature: "GEO-004") }
        }
        var areas: [EnhancedTextArea]?
        if let raw = node.odf(ODF.draw, "text-areas") {
            guard let values = try tokens(raw) else { throw SlideError.corruptedPackage("不正なODP text area字句") }
            let operands = values.compactMap { if case .operand(let value) = $0 { value } else { nil } }
            guard operands.count == values.count, [4, 8].contains(operands.count) else { throw SlideError.corruptedPackage("不正なODP text area引数") }
            areas = stride(from: 0, to: operands.count, by: 4).map {
                .init(left: operands[$0], top: operands[$0 + 1], right: operands[$0 + 2], bottom: operands[$0 + 3])
            }
        }
        let handles = try node.children(ODF.draw, "handle").map { try SourceXMLNode($0) }
        if !equations.isEmpty || !handles.isEmpty { warn(node, "guide式の評価・handleの配置は原本に保持します", code: .uninterpretedFormatting, id: elementID, feature: "GEO-004") }
        let interpreted = Set(["type", "enhanced-path", "modifiers", "text-areas", "mirror-horizontal", "mirror-vertical"].map { ODF.key(ODF.draw, $0) } + [ODF.key(ODF.svg, "viewBox")])
        for key in node.attributes.keys.sorted() where !interpreted.contains(key) { warn(node, "未解釈の高度geometry属性を保持します: \(key)", code: .uninterpretedFormatting, id: elementID, feature: "GEO-004") }
        for child in node.children where child.namespace != ODF.draw || !["equation", "handle"].contains(child.name) { warn(child, "未知の高度geometry内容を原本に保持します", id: elementID, feature: "GEO-004") }
        return try .init(shapeType: node.odf(ODF.draw, "type"), viewBox: viewBox, modifiers: modifiers, equations: equations,
                         path: path, textAreas: areas, mirrorHorizontal: boolean("mirror-horizontal"), mirrorVertical: boolean("mirror-vertical"),
                         handles: handles, source: SourceXMLNode(node))
    }
}
