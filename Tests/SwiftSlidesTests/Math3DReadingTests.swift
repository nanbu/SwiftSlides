import Foundation
import Testing
@testable import SlideCore
import SwiftSlides

private let math3DFixtures = ["math-3d.pptx", "math-3d-strict.pptx"]
private let mathNS = "http://schemas.openxmlformats.org/officeDocument/2006/math"
private let mcNS = "http://schemas.openxmlformats.org/markup-compatibility/2006"

private func equationShape(_ p: Presentation) throws -> Element {
    try #require(p.slides[0].elements.first { $0.name == "Fictional equation and 3D" })
}
private func allMathNodes(_ root: EquationNode) -> [EquationNode] { [root] + root.children.flatMap(allMathNodes) }

@Test(arguments: math3DFixtures)
func ommlStructureAndInlineOrder(_ name: String) throws {
    let p = try Presentation(data: fixture(name)), e = try equationShape(p)
    let text = try #require(e.text), run = text.paragraphs[0].runs[1], equation = try #require(run.equation)
    #expect(text.paragraphs[0].runs.map(\.text) == ["Before", "a+bcx21234", "After"])
    #expect(equation.dialect == .omml && equation.root.kind == .paragraph && equation.part == "ppt/slides/slide1.xml")
    let nodes = allMathNodes(equation.root), fraction = try #require(nodes.first { $0.kind == .fraction })
    #expect(fraction.children.map(\.kind) == [.properties, .numerator, .denominator])
    #expect(fraction.children[1].lexicalText == "a+b" && fraction.children[2].lexicalText == "c")
    #expect(nodes.first { $0.kind == .superscript }?.children.map(\.kind) == [.base, .superscriptArgument])
    let matrix = try #require(nodes.first { $0.kind == .matrix })
    #expect(matrix.children.filter { $0.kind == .matrixRow }.map(\.lexicalText) == ["12", "34"])
    #expect(nodes.contains { $0.kind == .native && $0.namespace == "urn:fictional:future" && $0.attributes["flag"] == "keep" })
    #expect(equation.source.name == "AlternateContent" && equation.source.namespace == mcNS)
    #expect(equation.source.children.filter { $0.name == "Choice" }.count == 3)
    #expect(equation.source.descendants(named: "t").contains { $0.text == "Fallback" })
    #expect(!equation.lexicalText.contains("Rejected") && !equation.lexicalText.contains("Later"))
    let second = try #require(text.paragraphs[1].runs.first?.equation)
    #expect(second.lexicalText == "3yi=1ni")
    #expect(allMathNodes(second.root).first { $0.kind == .radical }?.children.map(\.kind) == [.degree, .base])
    #expect(allMathNodes(second.root).first { $0.kind == .nary }?.children.map(\.kind) == [.properties, .subscriptArgument, .superscriptArgument, .base])
    #expect(p.slides[0].elements.first { $0.table != nil }?.table?.rows[0][0].text.paragraphs[0].runs[1].equation?.root == equation.root)
    #expect(p.slides[0].notes?.paragraphs[0].runs[1].equation?.root == equation.root)
    let layout = try p.readLayout(at: #require(p.slides[0].layoutPath)).layout
    #expect(layout.elements.first { $0.name == e.name }?.text?.paragraphs[0].runs[1].equation?.root == equation.root)
    #expect(p.readDiagnostics.contains { $0.feature == "OBJ-005" && $0.message.contains("未解釈") })
    #expect(try p.write().data == fixture(name))
    #expect(try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(e)) == e)
    let legacy = try JSONDecoder().decode(TextRun.self, from: Data("{\"text\":\"old\",\"style\":{\"font\":{\"supplementalFamilies\":{}}}}".utf8))
    #expect(legacy.equation == nil)
}

@Test(arguments: math3DFixtures)
func scene3DDirectValuesAndOmissions(_ name: String) throws {
    let p = try Presentation(data: fixture(name)), e = try equationShape(p), scene = try #require(e.scene3D), shape = try #require(e.shape3D)
    #expect(scene.cameraPreset == "perspectiveFront" && scene.fieldOfView == 90 && scene.zoom == 1.5)
    #expect(scene.cameraRotation == .init(latitude: 10, longitude: 20, revolution: 0))
    #expect(scene.lightRig == "threePt" && scene.lightDirection == "t" && scene.lightRotation?.revolution == 30)
    #expect(scene.source.descendants(named: "anchor").first?.attributes["z"] == "12700")
    #expect(scene.source.descendants(named: "future", namespace: "urn:fictional:future").first?.attributes["flag"] == "scene")
    #expect(shape.depth == -1 && shape.extrusionHeight == 2 && shape.contourWidth == 0.5 && shape.material == "plastic")
    #expect(shape.topBevel == .init(width: 1, height: 2, preset: "circle") && shape.bottomBevel == .init(width: 0, height: 0))
    #expect(shape.extrusionColor == .rgb("123456") && shape.contourColor == .theme("accent2"))
    #expect(p.readDiagnostics.contains { $0.feature == "GEO-012" })
    let data = try changedFixture(name) { parts in
        let path = "ppt/slides/slide1.xml", root = try MarkupNode.parse(parts[path]!, part: path, limits: .init())
        let camera = try #require(root.descendants("camera").first); camera.set("fov", nil); camera.set("zoom", nil); camera.remove(["rot"])
        let properties = try #require(root.descendants("sp3d").first); properties.attributes = [:]; properties.content = []
        parts[path] = Data(root.xml.utf8)
    }
    let omitted = try equationShape(Presentation(data: data))
    #expect(omitted.scene3D?.fieldOfView == nil && omitted.scene3D?.zoom == nil && omitted.scene3D?.cameraRotation == nil)
    #expect(omitted.shape3D?.extrusionHeight == nil && omitted.shape3D?.depth == nil && omitted.shape3D?.topBevel == nil)
}

@Test(arguments: math3DFixtures)
func mathAnd3DPreservePositionEditsAndRejectDestructiveRewrites(_ name: String) throws {
    let p = try Presentation(data: fixture(name)), index = try #require(p.slides[0].elements.firstIndex { $0.name == "Fictional equation and 3D" })
    let before = p.slides[0].elements[index]
    var moved = p; moved.slides[0].elements[index].frame?.x = 42
    let output = try moved.write(options: .init(strict: true)).data, after = try equationShape(Presentation(data: output))
    #expect(after.text == before.text && after.scene3D == before.scene3D && after.shape3D == before.shape3D)
    #expect(after.frame?.x == 42)
    let tableIndex = try #require(p.slides[0].elements.firstIndex { $0.table != nil })
    let mutations: [(inout Presentation) -> Void] = [
        { $0.slides[0].elements[index].text?.paragraphs[0].runs[0].text = "Changed" },
        { $0.slides[0].elements[index].text?.paragraphs[0].runs[1].equation = nil },
        { $0.slides[0].elements[index].text = nil },
        { $0.slides[0].elements[index].scene3D = nil },
        { $0.slides[0].elements[index].shape3D = nil },
        { $0.slides[0].notes = nil },
        { $0.slides[0].elements[tableIndex].table?.rows[0][0].text = .init("Discard formula") },
        { $0.slides[0].elements[tableIndex].table?.rows.removeLast(); $0.slides[0].elements[tableIndex].table?.rowHeights.removeLast() }
    ]
    for mutate in mutations {
        var candidate = p; mutate(&candidate)
        #expect(throws: SlideError.self) { try candidate.write(options: .init(strict: false)).data }
    }
    var newShape = Element(kind: .shape, frame: .init(x: 0, y: 0, width: 100, height: 100)); newShape.text = before.text
    #expect(throws: SlideError.self) { try Presentation(slides: [Slide(elements: [newShape])]).write().data }
    newShape.text = nil; newShape.scene3D = before.scene3D
    #expect(throws: SlideError.self) { try Presentation(slides: [Slide(elements: [newShape])]).write().data }
    // セル寸法だけの変更では原式を維持する。
    var wider = p; wider.slides[0].elements[tableIndex].table?.columnWidths[0] = 160
    #expect(try Presentation(data: wider.write(options: .init(strict: true)).data).slides[0].elements[tableIndex].table?.rows[0][0].text == p.slides[0].elements[tableIndex].table?.rows[0][0].text)
}

@Test func unknownMathChoiceIsPreservedWithoutSelectingItsFormula() throws {
    let data = try changedFixture("math-3d.pptx") { parts in
        let path = "ppt/slides/slide1.xml", root = try MarkupNode.parse(parts[path]!, part: path, limits: .init())
        let choices = root.descendants("Choice", ns: mcNS)
        for choice in choices { choice.set("Requires", "u") }
        for body in root.descendants("txBody") {
            if let first = body.named("p").first {
                body.content.removeAll { if case .node(let node) = $0 { node.isA && node.name == "p" && node !== first } else { false } }
            }
        }
        parts[path] = Data(root.xml.utf8)
    }
    var p = try Presentation(data: data), index = try #require(p.slides[0].elements.firstIndex { $0.name == "Fictional equation and 3D" })
    #expect(p.slides[0].elements[index].text?.paragraphs[0].runs.map(\.text) == ["Before", "After"])
    #expect(p.slides[0].elements[index].text?.paragraphs.flatMap(\.runs).allSatisfy { $0.equation == nil } == true)
    #expect(try p.write().data == data)
    p.slides[0].elements[index].text?.paragraphs[0].runs[0].text = "Changed"
    #expect(throws: SlideError.self) { try p.write(options: .init(strict: false)).data }
}

@Test func corruptedMathArgumentsAnd3DValuesAreRejected() throws {
    let mutations: [(MarkupNode) throws -> Void] = [
        { root in let f = try #require(root.descendants("f", ns: mathNS).first); f.content.removeAll { if case .node(let n) = $0 { n.name == "den" } else { false } } },
        { root in let f = try #require(root.descendants("f", ns: mathNS).first); f.content.append(.node(try #require(f.children.first { $0.name == "num" }))) },
        { try #require($0.descendants("camera").first).set("fov", "NaN") },
        { try #require($0.descendants("camera").first).set("fov", "10800001") },
        { try #require($0.descendants("camera").first).set("zoom", "-1") },
        { try #require($0.descendants("camera").first).set("prst", nil) },
        { try #require($0.descendants("scene3d").first).remove(["lightRig"]) },
        { root in let scene = try #require(root.descendants("scene3d").first); scene.content.append(.node(try #require(scene.child("camera")))) },
        { try #require($0.descendants("rot").first).set("lat", "21600000") },
        { try #require($0.descendants("sp3d").first).set("extrusionH", "-1") },
        { try #require($0.descendants("bevelT").first).set("w", "1.5") }
    ]
    for mutate in mutations {
        let data = try changedFixture("math-3d.pptx") { parts in
            let path = "ppt/slides/slide1.xml", root = try MarkupNode.parse(parts[path]!, part: path, limits: .init())
            try mutate(root)
            parts[path] = Data(root.xml.utf8)
        }
        #expect(throws: SlideError.self) { try Presentation(data: data) }
    }
}

@Test(arguments: math3DFixtures)
func math3DSelectedReaderMatchesFullRead(_ name: String) async throws {
    let data = try fixture(name), full = try await Presentation.read(data), reader = try SlideReader(data: data)
    #expect(try await reader.slide(id: reader.slideDescriptors[0].id).slide == full.presentation.slides[0])
}
