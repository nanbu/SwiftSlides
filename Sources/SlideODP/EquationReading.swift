import Foundation
import SlideCore

private let mathMLNamespace = "http://www.w3.org/1998/Math/MathML"

extension ODPPageParser {
    /// 同一frameのプレビューは式として読まず、元のframe構造へ残す。
    func frameEquation(_ frame: MarkupNode) throws -> Equation? {
        let objects = frame.children(ODF.draw, "object")
        guard objects.count == 1,
              frame.children.allSatisfy({ ($0.namespace == ODF.draw && ["object", "image"].contains($0.name)) ||
                  ($0.namespace == ODF.svg && ["title", "desc"].contains($0.name)) }) else { return nil }
        return try objectEquation(objects[0])
    }

    func objectEquation(_ object: MarkupNode) throws -> Equation? {
        let inline = object.children.filter { ($0.namespace == mathMLNamespace && $0.name == "math") ||
            ($0.namespace == ODF.office && $0.name == "document") }
        guard inline.count <= 1 else { throw SlideError.corruptedPackage("ODP objectのinline内容が重複") }
        let source: MarkupNode, part: String
        if let root = inline.first { source = root; part = "content.xml" }
        else if let href = object.odf(ODF.xlink, "href") {
            let ref = try reference(href)
            guard let path = ref.path, path.hasSuffix(".xml") else { return nil }
            source = try MarkupNode.parse(archive.read(path), part: path, limits: options.limits); part = path
        } else { return nil }
        // ODFのformula subdocumentはmath:mathをルートとする。office文書を式と推測しない。
        guard source.namespace == mathMLNamespace, source.name == "math" else { return nil }
        let root = source
        var kinds: [String: EquationNode.Kind] = ["math": .math, "mi": .identifier, "mn": .number, "mo": .operatorToken,
            "ms": .stringLiteral, "mtext": .text, "mrow": .row, "mfrac": .fraction, "msqrt": .radical, "mroot": .radical,
            "msup": .superscript, "msub": .subscriptExpression, "msubsup": .subSuperscript, "munder": .under, "mover": .over,
            "munderover": .underOver, "mtable": .matrix, "mtr": .matrixRow, "mlabeledtr": .matrixRow, "mtd": .tableCell,
            "mstyle": .style, "mspace": .space, "mpadded": .padded, "menclose": .enclosed, "mphantom": .phantom,
            "mmultiscripts": .multiscripts, "mprescripts": .prescripts, "none": .none, "semantics": .semantics,
            "annotation": .annotation, "annotation-xml": .annotation, "maction": .action, "merror": .error, "mfenced": .delimiter]
        kinds.merge(["apply": .application, "bind": .binding, "bvar": .boundVariable, "ci": .identifier,
            "cn": .number, "cs": .stringLiteral, "csymbol": .contentSymbol, "lambda": .lambda,
            "set": .set, "list": .list, "interval": .interval, "vector": .vector,
            "matrix": .matrix, "matrixrow": .matrixRow, "piecewise": .piecewise, "piece": .piece,
            "otherwise": .otherwise, "declare": .declaration, "share": .share, "sep": .separator,
            "cerror": .error], uniquingKeysWith: { _, value in value })
        for name in "condition domainofapplication degree logbase lowlimit uplimit momentabout".split(separator: " ") { kinds[String(name)] = .qualifier }
        for name in "plus minus times divide power root quotient rem factorial abs conjugate arg real imaginary floor ceiling max min gcd lcm and or xor not implies forall exists eq neq gt lt geq leq equivalent approx factorof int diff partialdiff divergence grad curl laplacian sum product limit tendsto sin cos tan sec csc cot sinh cosh tanh sech csch coth arcsin arccos arctan arccosh arccot arccoth arccsc arccsch arcsec arcsech arcsinh arctanh exp ln log determinant transpose selector vectorproduct scalarproduct outerproduct compose inverse ident domain codomain image union intersect in notin subset prsubset notsubset notprsubset setdiff card cartesianproduct mean sdev variance median mode moment".split(separator: " ") { kinds[String(name)] = .contentOperator }
        for name in "integers reals rationals naturalnumbers complexes primes exponentiale imaginaryi notanumber true false emptyset pi eulergamma infinity".split(separator: " ") { kinds[String(name)] = .contentConstant }
        let arities = ["mfrac": 2, "mroot": 2, "msup": 2, "msub": 2, "msubsup": 3, "munder": 2, "mover": 2, "munderover": 3]
        let tokens: Set<EquationNode.Kind> = [.identifier, .number, .operatorToken, .stringLiteral, .text, .contentSymbol]
        func project(_ node: MarkupNode, annotation: Bool = false) throws -> EquationNode {
            try Task.checkCancellation()
            let kind = node.namespace == mathMLNamespace ? kinds[node.name] ?? .native : .native
            // annotation内のXMLは別dialectや不完全な式も許す。表示式として検証しない。
            if !annotation && kind != .annotation {
                if let count = arities[node.name], node.namespace == mathMLNamespace, node.children.count != count {
                    throw SlideError.corruptedPackage("MathML \(node.name)の引数数が不正: \(part)")
                }
                if [.application, .binding].contains(kind), node.children.isEmpty { throw SlideError.corruptedPackage("Content MathMLの演算子不在") }
                if kind == .binding {
                    guard node.children.count >= 2, node.children.dropFirst().dropLast().allSatisfy({ $0.name == "bvar" && $0.namespace == mathMLNamespace }) else { throw SlideError.corruptedPackage("Content MathML bindの構造") }
                }
                if kind == .boundVariable, node.children.isEmpty { throw SlideError.corruptedPackage("Content MathMLの束縛変数不在") }
                if kind == .piece, node.children.count != 2 { throw SlideError.corruptedPackage("Content MathML pieceの引数数") }
                if kind == .otherwise, node.children.count != 1 { throw SlideError.corruptedPackage("Content MathML otherwiseの引数数") }
                if kind == .interval, node.children.count != 2 { throw SlideError.corruptedPackage("Content MathML intervalの引数数") }
                if kind == .piecewise, node.children.filter({ $0.name == "otherwise" }).count > 1 { throw SlideError.corruptedPackage("Content MathML otherwise重複") }
                if kind == .semantics {
                    guard let first = node.children.first, !(first.namespace == mathMLNamespace && ["annotation", "annotation-xml"].contains(first.name)) else {
                        throw SlideError.corruptedPackage("MathML semanticsの主式がありません")
                    }
                    guard node.children.dropFirst().allSatisfy({ $0.namespace == mathMLNamespace && ["annotation", "annotation-xml"].contains($0.name) }) else {
                        throw SlideError.corruptedPackage("MathML semanticsの注釈構造が不正")
                    }
                }
                if kind == .multiscripts {
                    let children = node.children
                    guard let first = children.first, !(first.namespace == mathMLNamespace && ["mprescripts", "none"].contains(first.name)) else {
                        throw SlideError.corruptedPackage("MathML multiscriptsのbaseがありません")
                    }
                    let rest = Array(children.dropFirst()), markers = rest.indices.filter { rest[$0].namespace == mathMLNamespace && rest[$0].name == "mprescripts" }
                    guard markers.count <= 1 else { throw SlideError.corruptedPackage("MathML prescriptsが重複") }
                    let boundary = markers.first ?? rest.count
                    guard boundary.isMultiple(of: 2), (markers.isEmpty ? 0 : rest.count - boundary - 1).isMultiple(of: 2) else {
                        throw SlideError.corruptedPackage("MathML multiscriptsの引数対が不正")
                    }
                }
                if kind == .native { warnings.add(.unsupportedContent, part: part, element: node.name, message: "未解釈MathML内容を原本に保持します", feature: "OBJ-005", slideID: slideID) }
            }
            var parts: [String]?
            if kind == .number && node.name == "cn" {
                var values = [""]
                for content in node.content { switch content { case .text(let text): values[values.count - 1] += text; case .node(let child): if child.namespace == mathMLNamespace && child.name == "sep" { values.append("") } else { values[values.count - 1] += child.text } } }
                parts = values
            }
            return try .init(kind: kind, name: node.name, namespace: node.namespace, attributes: node.attributes,
                             text: tokens.contains(kind) ? node.text : nil, tokenParts: parts,
                             children: node.children.map { try project($0, annotation: annotation || kind == .annotation) })
        }
        let equation = try Equation(dialect: .mathML, root: project(root), source: SourceXMLNode(source), part: part)
        let budget = min(options.limits.maxPartBytes, options.limits.maxExpandedBytes), bytes = equation.lexicalText.utf8.count
        guard bytes <= budget - textBytes else { throw SlideError.limitExceeded("ODP数式表示文字の展開予算") }
        textBytes += bytes
        warnings.add(.unsupportedContent, part: part, element: root.name, message: "MathMLの構造とtokenを読みます。計算・描画は行いません", feature: "OBJ-005", slideID: slideID)
        return equation
    }
}
