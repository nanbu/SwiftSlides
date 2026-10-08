import Foundation
import Testing
@testable import SlideCore
import SwiftSlides

private let semanticFixture = "semantic-reading.odp"
private let odpDraw = "urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
private let odpSVG = "urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0"
private let odpMath = "http://www.w3.org/1998/Math/MathML"

private func semanticElement(_ p: Presentation, _ id: String) throws -> Element {
    try #require(p.slides[0].elements.first { $0.id == id })
}
private func semanticMutation(_ part: String = "content.xml", _ edit: (MarkupNode) throws -> Void) throws -> Data {
    try changedFixture(semanticFixture) { parts in
        let root = try MarkupNode.parse(#require(parts[part]), part: part, limits: .init())
        try edit(root); parts[part] = Data(root.xml.utf8)
    }
}

@Test func odpEnhancedGeometryOperandsAndCommands() throws {
    let p = try Presentation(data: fixture(semanticFixture)), element = try semanticElement(p, "enhanced")
    let geometry = try #require(element.enhancedGeometry), path = try #require(geometry.path)
    #expect(element.kind == .shape && element.geometry == nil && element.customGeometry == nil)
    #expect(abs((element.frame?.width ?? 0) - 3 * 72 / 2.54) < 0.000001 && element.text?.plainText == "Fictional shape")
    #expect(geometry.shapeType == "fictional" && geometry.viewBox == .init(x: -10, y: 0, width: 200, height: 100))
    #expect(geometry.modifiers == [25, 100] && geometry.mirrorHorizontal == false && geometry.mirrorVertical == true)
    #expect(path.map(\.kind) == [.move, .line, .cubic, .quadratic, .arcTo, .arc, .angleEllipseTo, .angleEllipse,
                                 .clockwiseArc, .clockwiseArcTo, .ellipticalQuadrantX, .ellipticalQuadrantY, .close, .end, .noFill, .noStroke])
    #expect(path[0].arguments == [.number(0), .number(0), .number(50), .number(50)])
    #expect(path[1].arguments == [.modifier(0), .formula("edge")])
    #expect(geometry.equations == [.init(name: "edge", formula: "$1 / 2")])
    #expect(geometry.textAreas == [.init(left: .number(0), top: .number(0), right: .modifier(0), bottom: .formula("edge"))])
    #expect(geometry.handles.first?.attributes[odpDraw + "|handle-position"] == "$0 ?edge")
    #expect(geometry.source.attributes[odpDraw + "|extrusion"] == "true")
    #expect(geometry.source.descendants(named: "future", namespace: "urn:fictional:future").first?.attributes["flag"] == "geometry")
    #expect(try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(element)) == element)
}

@Test func odpEnhancedGeometryUnknownEmptyAndOmittedAreDistinct() throws {
    let p = try Presentation(data: fixture(semanticFixture)), unknown = try #require(semanticElement(p, "unknown-path").enhancedGeometry)
    #expect(unknown.path == nil && unknown.source.attributes[odpDraw + "|enhanced-path"] == "M0 0 R1 2")
    let empty = try #require(semanticElement(p, "empty-path").enhancedGeometry)
    #expect(empty.path == [] && empty.modifiers == [] && empty.viewBox == nil && empty.mirrorHorizontal == nil)
    #expect(p.readWarnings.contains { $0.message.contains("未知のenhanced path") })
    let data = try semanticMutation { root in
        let geometry = try #require(root.descendants("enhanced-geometry", ns: odpDraw).first)
        geometry.attributes[odpDraw + "|enhanced-path"] = nil; geometry.attributes[odpDraw + "|modifiers"] = nil; geometry.attributes[odpDraw + "|text-areas"] = nil
    }
    let omitted = try #require(semanticElement(Presentation(data: data), "enhanced").enhancedGeometry)
    #expect(omitted.path == nil && omitted.modifiers == nil && omitted.textAreas == nil)
    let engine = try semanticMutation { root in let shape = try #require(root.descendants("custom-shape", ns: odpDraw).first); shape.attributes[odpDraw + "|engine"] = "fictional-engine"; shape.attributeNames[odpDraw + "|engine"] = "draw:engine" }
    #expect(try semanticElement(Presentation(data: engine), "enhanced").kind == .opaque)
    #expect(try semanticElement(Presentation(data: engine), "enhanced").enhancedGeometry == nil)
}

@Test func odpEnhancedGeometryRejectsMalformedValuesAndReferences() throws {
    let changes: [(String, String)] = [
        ("enhanced-path", "M0"), ("enhanced-path", "0 0 L1 2"), ("enhanced-path", "M0 0 Z1"),
        ("enhanced-path", "M0 0 L$2 1"), ("enhanced-path", "M0 0 L?missing 1"), ("enhanced-path", "M0 1e999"),
        ("enhanced-path", "M0 -Infinity"),
        ("modifiers", "NaN"), ("mirror-horizontal", "unknown"), ("text-areas", "0 0 1"), ("text-areas", "0 0 ?missing 1")
    ]
    for (attribute, value) in changes {
        let data = try semanticMutation { root in try #require(root.descendants("enhanced-geometry", ns: odpDraw).first).attributes[odpDraw + "|" + attribute] = value }
        #expect(throws: SlideError.self) { try Presentation(data: data) }
    }
    for value in ["0 0 -1 2", "0 0 1", "0 0 1 Infinity"] {
        let data = try semanticMutation { root in try #require(root.descendants("enhanced-geometry", ns: odpDraw).first).attributes[odpSVG + "|viewBox"] = value }
        #expect(throws: SlideError.self) { try Presentation(data: data) }
    }
    let duplicate = try semanticMutation { root in
        let geometry = try #require(root.descendants("enhanced-geometry", ns: odpDraw).first)
        geometry.content.append(.node(try #require(geometry.children.first { $0.name == "equation" })))
    }
    #expect(throws: SlideError.self) { try Presentation(data: duplicate) }
}

@Test func odpMathMLStructureSourcesAndInlineOrder() throws {
    let p = try Presentation(data: fixture(semanticFixture)), element = try semanticElement(p, "package-math")
    let equation = try #require(element.equation)
    #expect(equation.dialect == .mathML && equation.part == "Formula/content.xml" && equation.root.kind == .math)
    #expect(equation.lexicalText == "a2+x3y12∑0n12z20" && element.plainText == equation.lexicalText)
    #expect(equation.source.name == "math")
    #expect(equation.source.descendants(named: "annotation").first?.text == "NOT DISPLAYED")
    #expect(!equation.lexicalText.contains("NOT DISPLAYED"))
    let row = try #require(equation.root.children.first?.children.first)
    #expect(row.kind == .row && row.children.first?.kind == .fraction)
    #expect(row.children.first?.children.map(\.kind) == [.identifier, .number])
    #expect(row.children.first { $0.name == "mroot" }?.children.map(\.lexicalText) == ["x", "3"])
    #expect(row.children.first { $0.kind == .matrix }?.children.first?.children.map(\.kind) == [.tableCell, .tableCell])
    #expect(row.children.contains { $0.kind == .native && $0.namespace == "urn:fictional:future" })
    #expect(element.sourceProperties?.descendants(named: "image", namespace: odpDraw).first != nil)
    #expect(try p.asset(at: "Pictures/preview.png") == fixture("fixture.png"))
    let inline = try #require(semanticElement(p, "text-math").text?.paragraphs.first)
    #expect(inline.runs.map(\.text) == ["Before", "b4", "After"] && inline.runs[1].equation?.dialect == .mathML)
    #expect(try semanticElement(p, "second-inline-math").equation?.lexicalText == "b4")
    #expect(try semanticElement(p, "formula-group").children[0].equation?.lexicalText == "b4")
    #expect(try semanticElement(p, "external-math").equation == nil)
    #expect(p.readDiagnostics.contains { $0.feature == "OBJ-005" && $0.location.part == "Formula/content.xml" && $0.message.contains("未解釈") })
    #expect(try JSONDecoder().decode(Equation.self, from: JSONEncoder().encode(equation)) == equation)
}

@Test func odpMathMLRejectsMalformedArgumentsAndMissingObjects() throws {
    for name in ["mfrac", "mroot", "msubsup", "munderover", "semantics", "mmultiscripts"] {
        let data = try semanticMutation("Formula/content.xml") { root in
            let node = try #require(root.descendants(name, ns: odpMath).first)
            node.content.removeAll()
        }
        #expect(throws: SlideError.self) { try Presentation(data: data) }
    }
    let missing = try changedFixture(semanticFixture) { $0.removeValue(forKey: "Formula/content.xml") }
    #expect(throws: SlideError.self) { try Presentation(data: missing) }
    let malformed = try changedFixture(semanticFixture) { $0["Formula/content.xml"] = Data("<broken>".utf8) }
    #expect(throws: SlideError.self) { try Presentation(data: malformed) }
    let dtd = try changedFixture(semanticFixture) { parts in
        parts["Formula/content.xml"] = Data("<!DOCTYPE math [<!ENTITY x 'hidden'>]><math xmlns='http://www.w3.org/1998/Math/MathML'><mi>&x;</mi></math>".utf8)
    }
    #expect(throws: SlideError.self) { try Presentation(data: dtd) }
}

@Test func odpSemanticModelsHonorSelectedReaderBudgetsAndReadOnlyBoundaries() throws {
    let data = try fixture(semanticFixture), p = try Presentation(data: data)
    let reader = try SlideReader(data: data, format: .odp)
    #expect(try reader.slide(id: "semantic-page").slide == p.slides[0])
    #expect(try reader.asset(at: "Formula/content.xml") == p.asset(at: "Formula/content.xml"))
    let repeated = try semanticMutation { root in
        let page = try #require(root.descendants("page", ns: odpDraw).first)
        let parent = try #require(root.descendants("presentation", ns: "urn:oasis:names:tc:opendocument:xmlns:office:1.0").first)
        let second = try MarkupNode.parse(Data(page.xml.utf8), part: "content.xml", limits: .init()); second.attributes["http://www.w3.org/XML/1998/namespace|id"] = "semantic-second"
        parent.content.append(.node(second))
    }
    // package XMLを再利用しても、数式tokenはページごとの展開予算に含める。
    let first = try SlideReader(data: repeated, format: .odp)
    #expect(try first.slide(id: "semantic-second").slide.elements.contains { $0.equation != nil })
    let large = try changedFixture(semanticFixture) { package in
        package = try parts(repeated)
        package["Formula/content.xml"] = Data(("<math xmlns='http://www.w3.org/1998/Math/MathML'><mi>" + String(repeating: "a", count: 20_000) + "</mi></math>").utf8)
    }
    var limits = PackageLimits(); limits.maxExpandedBytes = try PackageArchive(large, limits: .init()).entries.values.reduce(0) { $0 + $1.expandedSize }
    let bounded = try SlideReader(data: large, format: .odp, options: .init(limits: limits))
    #expect(try bounded.slide(id: "semantic-page").slide.elements.first { $0.id == "package-math" }?.equation?.lexicalText.count == 20_000)
    #expect(throws: SlideError.limitExceeded("ODP数式表示文字の展開予算")) { try Presentation(data: large, options: .init(limits: limits)) }
    let manyOperands = try semanticMutation { root in
        try #require(root.descendants("enhanced-geometry", ns: odpDraw).first).attributes[odpDraw + "|enhanced-path"] = "M " + Array(repeating: "0", count: 202).joined(separator: " ")
    }
    limits = .init(); limits.maxXMLNodes = 200
    #expect(throws: SlideError.limitExceeded("ODP geometry token予算")) { try Presentation(data: manyOperands, options: .init(limits: limits)) }
    let manyModifiers = try semanticMutation { root in
        try #require(root.descendants("enhanced-geometry", ns: odpDraw).first).attributes[odpDraw + "|modifiers"] = Array(repeating: "0", count: 201).joined(separator: " ")
    }
    #expect(throws: SlideError.limitExceeded("ODP modifier予算")) { try Presentation(data: manyModifiers, options: .init(limits: limits)) }
    var newElement = Element(frame: .init(x: 0, y: 0, width: 10, height: 10))
    newElement.enhancedGeometry = try semanticElement(p, "enhanced").enhancedGeometry
    #expect(throws: SlideError.self) { try Presentation(slides: [Slide(elements: [newElement])]).write().data }
    newElement.enhancedGeometry = nil; newElement.equation = try semanticElement(p, "package-math").equation
    #expect(throws: SlideError.self) { try Presentation(slides: [Slide(elements: [newElement])]).write().data }
    #expect(throws: SlideError.self) { try p.write(as: .odp).data }
    var existing = try Presentation(data: fixture()); existing.slides[0].elements[0].equation = newElement.equation
    #expect(throws: SlideError.self) { try existing.write(options: .init(strict: false)).data }
}
