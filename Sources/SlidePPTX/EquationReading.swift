import Foundation
import SlideCore

private let ommlNamespaces: Set<String> = ["http://schemas.openxmlformats.org/officeDocument/2006/math", "http://purl.oclc.org/ooxml/officeDocument/math"]
private let mathDrawingNamespace = "http://schemas.microsoft.com/office/drawing/2010/main"
private let markupCompatibilityNamespace = "http://schemas.openxmlformats.org/markup-compatibility/2006"

/// 未選択分岐の数式も、文字領域の再構成で破棄しない。
func containsEquationSource(_ node: MarkupNode?) -> Bool {
    guard let node else { return false }
    if ommlNamespaces.contains(node.namespace), ["oMath", "oMathPara"].contains(node.name) { return true }
    if node.namespace == mathDrawingNamespace, node.name == "m" { return true }
    return node.children.contains { containsEquationSource($0) }
}

extension PPTXReader {
    /// 段落の一つの子を読む。未選択Choice/Fallbackもsourceに保持する。
    func equation(_ source: MarkupNode, part: String) throws -> Equation? {
        func mathRoot(_ node: MarkupNode) throws -> MarkupNode? {
            if ommlNamespaces.contains(node.namespace), ["oMath", "oMathPara"].contains(node.name) { return node }
            if node.namespace == mathDrawingNamespace, node.name == "m" {
                let roots = node.children.filter { ommlNamespaces.contains($0.namespace) && ["oMath", "oMathPara"].contains($0.name) }
                guard roots.count == 1 else { throw SlideError.corruptedPackage("DrawingML数式のルートが不在または重複: \(part)") }
                return roots[0]
            }
            return nil
        }
        let root: MarkupNode?
        if source.namespace == markupCompatibilityNamespace, source.name == "AlternateContent" {
            let supported = ommlNamespaces.union([mathDrawingNamespace, NS.a, NS.strictA])
            let choice = source.children.first { node in
                guard node.namespace == markupCompatibilityNamespace, node.name == "Choice", let requires = node.attr("Requires") else { return false }
                let prefixes = requires.split(whereSeparator: { $0.isWhitespace })
                return !prefixes.isEmpty && prefixes.allSatisfy { prefix in node.namespaces[String(prefix)].map { supported.contains($0) } ?? false }
            }
            // 複数の対応分岐を同時に投影しない。対応外の内容を推測しない。
            guard let choice else { return nil }
            let candidates = try choice.children.compactMap(mathRoot)
            guard candidates.count <= 1 else { throw SlideError.corruptedPackage("数式Choiceのルートが重複: \(part)") }
            root = candidates.first
        } else { root = try mathRoot(source) }
        guard let root else { return nil }
        let kinds: [String: EquationNode.Kind] = [
            "oMath": .math, "oMathPara": .paragraph, "r": .run, "t": .text, "f": .fraction, "num": .numerator, "den": .denominator,
            "rad": .radical, "deg": .degree, "e": .base, "sSup": .superscript, "sSub": .subscriptExpression, "sSubSup": .subSuperscript,
            "sPre": .preSubSuperscript, "sub": .subscriptArgument, "sup": .superscriptArgument, "nary": .nary, "d": .delimiter,
            "m": .matrix, "mr": .matrixRow, "eqArr": .equationArray, "func": .function, "fName": .functionName,
            "acc": .accent, "bar": .bar, "groupChr": .groupCharacter, "limLow": .lowerLimit, "limUpp": .upperLimit,
            "lim": .limit, "box": .box, "borderBox": .borderBox, "phant": .phantom
        ]
        let required: [String: [String]] = ["f": ["num", "den"], "rad": ["deg", "e"], "sSup": ["e", "sup"], "sSub": ["e", "sub"],
            "sSubSup": ["e", "sub", "sup"], "sPre": ["sub", "sup", "e"], "nary": ["sub", "sup", "e"], "func": ["fName", "e"],
            "limLow": ["e", "lim"], "limUpp": ["e", "lim"], "acc": ["e"], "bar": ["e"], "groupChr": ["e"], "box": ["e"], "borderBox": ["e"], "phant": ["e"]]
        let propertyContainers: Set<String> = ["oMathParaPr", "rPr", "ctrlPr", "fPr", "radPr", "sSupPr", "sSubPr", "sSubSupPr", "sPrePr",
            "naryPr", "dPr", "mPr", "eqArrPr", "funcPr", "accPr", "barPr", "groupChrPr", "limLowPr", "limUppPr", "boxPr", "borderBoxPr", "phantPr", "mcs", "mc", "mcPr"]
        let propertyNames: Set<String> = ["jc", "type", "chr", "degHide", "grow", "limLoc", "subHide", "supHide", "begChr", "endChr", "sepChr",
            "shp", "baseJc", "count", "mcJc", "cGp", "cGpRule", "cSp", "rSp", "rSpRule", "plcHide", "pos", "vertJc", "ctrlPr", "sty", "scr",
            "nor", "lit", "brk", "aln", "diff", "noBreak", "opEmu", "hideBot", "hideTop", "hideLeft", "hideRight", "strikeBLTR", "strikeH", "strikeTLBR", "strikeV", "show", "transp", "zeroAsc", "zeroDesc", "zeroWid"]
        func project(_ node: MarkupNode, property: Bool = false) throws -> EquationNode {
            try Task.checkCancellation()
            let isMath = ommlNamespaces.contains(node.namespace)
            let isProperties = isMath && propertyContainers.contains(node.name)
            let kind = isMath ? kinds[node.name] ?? (isProperties ? .properties : property && propertyNames.contains(node.name) ? .property : .native) : .native
            if isMath, let arguments = required[node.name] {
                for argument in arguments {
                    guard node.children.filter({ ommlNamespaces.contains($0.namespace) && $0.name == argument }).count == 1 else {
                        throw SlideError.corruptedPackage("数式\(node.name)の\(argument)が不在または重複: \(part)")
                    }
                }
            }
            if kind == .native { warn(part, node, .unsupportedContent, "未解釈の数式ノードを原本構造に保持します", feature: "OBJ-005") }
            return .init(kind: kind, name: node.name, namespace: node.namespace, attributes: node.attributes,
                         text: kind == .text ? node.text : nil, children: try node.children.map { try project($0, property: isProperties) })
        }
        warn(part, source, .unsupportedContent, "数式の構造と字句を読みます。計算・線形式への変換・描画は行いません", feature: "OBJ-005")
        return try .init(root: project(root), source: SourceXMLNode(source), part: part)
    }
}
