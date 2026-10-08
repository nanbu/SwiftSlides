import Foundation
import Testing
@testable import SlideCore
import SwiftSlides

@Test func enhancedGuideEvaluationAndFailures() throws {
    let p = try Presentation(data: fixture("semantic-reading.odp")), geometry = try #require(p.slides[0].elements.first { $0.id == "enhanced" }?.enhancedGeometry)
    let result = try GeometryEvaluator.evaluate(geometry)
    #expect(result.guides["edge"] == 50 && result.path?[1].arguments == [25, 50])
    #expect(result.textAreas == [.init(x: 0, y: 0, width: 25, height: 50)])
    #expect(result.handles[0].values["handle-position-x"] == 25 && result.handles[0].values["handle-position-y"] == 50)
    let conditional = EnhancedGeometry(equations: [.init(name: "a", formula: "if(1,5,1/0)")], source: geometry.source)
    #expect(try GeometryEvaluator.evaluate(conditional).guides["a"] == 5)
    let equation = EnhancedGeometry(viewBox: .init(x: 0, y: 0, width: 200, height: 100), modifiers: [9], equations: [.init(name: "b", formula: "?a * 2"), .init(name: "a", formula: "sqrt($0) + sin(pi/2) + max(width,height)")], path: [.init(kind: .line, arguments: [.formula("b"), .formula("a")])], source: geometry.source)
    let value = try GeometryEvaluator.evaluate(equation)
    #expect(value.guides["a"] == 204 && value.guides["b"] == 408)
    for formula in ["1/0", "sqrt(-1)", "?a", "?missing", "sin(1,2)", "1 junk", "1e999"] {
        let bad = EnhancedGeometry(equations: [.init(name: "a", formula: formula)], source: geometry.source)
        #expect(throws: SlideError.self) { try GeometryEvaluator.evaluate(bad) }
    }
    #expect(throws: SlideError.self) { try GeometryEvaluator.evaluate(equation, maxOperations: 1) }
}

@Test func pptxAdditionalEffectsAndTextAppearance() throws {
    let data = try changedFixture("stored.pptx") { parts in
        let path = "ppt/slides/slide1.xml", root = try MarkupNode.parse(#require(parts[path]), part: path, limits: .init())
        let shape = try #require(root.descendants("sp").first), props = try #require(shape.child("spPr"))
        props.content.append(.node(try MarkupNode.fragment("<a:effectLst><a:glow rad=\"25400\"><a:srgbClr val=\"FF0000\"/></a:glow><a:innerShdw dist=\"12700\" dir=\"5400000\"><a:srgbClr val=\"000000\"/></a:innerShdw><a:softEdge rad=\"12700\"/></a:effectLst>")))
        let run = try #require(shape.child("txBody")?.descendants("r").first)
        run.content.insert(.node(try MarkupNode.fragment("<a:rPr spc=\"125\" baseline=\"25000\" cap=\"small\" strike=\"dblStrike\" u=\"wavy\" kern=\"1200\"/>")), at: 0)
        parts[path] = Data(root.xml.utf8)
    }
    let p = try Presentation(data: data), e = try #require(p.slides[0].elements.first { $0.effects != nil })
    let values = try #require(e.effects?.direct).compactMap { if case .drawing(let d) = $0 { d } else { nil } }
    #expect(values.map(\.kind) == [.glow, .innerShdw, .softEdge])
    #expect(values[0].values["rad"] == 2 && values[0].colors == [.rgb("FF0000")])
    #expect(values[1].values["dist"] == 1 && values[1].values["dir"] == 90)
    let a = try #require(e.text?.paragraphs.first?.runs.first?.style.appearance)
    #expect(a.spacing == 1.25 && a.baseline == 0.25 && a.capitalization == "small" && a.strike == "dblStrike" && a.kerning == 12)
    #expect(try p.write().data == data)
    var edited = p; edited.slides[0].elements[0].text?.paragraphs[0].runs[0].text = "changed"
    #expect(throws: SlideError.self) { try edited.write().data }
    #expect(try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(e)) == e)
    let dagData = try changedFixture("stored.pptx") { parts in
        let path = "ppt/slides/slide1.xml", root = try MarkupNode.parse(#require(parts[path]), part: path, limits: .init())
        let props = try #require(root.descendants("sp").first?.child("spPr")); props.remove(["effectLst", "effectDag"])
        props.content.append(.node(try MarkupNode.fragment("<a:effectDag><a:xfrm tx=\"25400\" ty=\"-12700\"/><a:relOff tx=\"25000\" ty=\"-50000\"/></a:effectDag>")))
        parts[path] = Data(root.xml.utf8)
    }
    let dagDeck = try Presentation(data: dagData)
    let effects = try #require(dagDeck.slides[0].elements[0].effects?.direct)
    let dag = try #require(effects.compactMap { if case .drawing(let e) = $0 { e } else { nil } }.first)
    #expect(dag.children[0].values["tx"] == 2 && dag.children[0].values["ty"] == -1)
    #expect(dag.children[1].values["tx"] == 0.25 && dag.children[1].values["ty"] == -0.5)
}

@Test func odfSpatialSceneAndExtrusion() throws {
    let data = try changedFixture("semantic-reading.odp") { parts in
        let path = "content.xml", root = try MarkupNode.parse(#require(parts[path]), part: path, limits: .init())
        let page = try #require(root.descendants("page", ns: "urn:oasis:names:tc:opendocument:xmlns:drawing:1.0").first)
        let xml = "<d:scene xmlns:d=\"urn:oasis:names:tc:opendocument:xmlns:dr3d:1.0\" d:vrp=\"(0cm 1cm 2cm)\" d:projection=\"perspective\" d:distance=\"2cm\" d:transform=\"matrix(1 0 0 0 1 0 0 0 1 0 0 0)\"><d:cube d:min-edge=\"(-1 -1 -1)\" d:max-edge=\"(1 1 1)\"/><d:light d:direction=\"(0 0 1)\" d:enabled=\"true\"/></d:scene>"
        page.content.append(.node(try MarkupNode.parse(Data(xml.utf8), part: path, limits: .init())))
        parts[path] = Data(root.xml.utf8)
    }
    let p = try Presentation(data: data), scene = try #require(p.slides[0].elements.first { $0.spatialGeometry?.kind == .scene })
    #expect(scene.kind == .group && scene.children.map { $0.spatialGeometry?.kind } == [.cube, .light])
    #expect(scene.spatialGeometry?.matrix?.count == 12 && scene.spatialGeometry?.tokens["projection"] == "perspective")
    #expect(abs((scene.spatialGeometry?.vectors["vrp"]?.z ?? 0) - 2 * 72 / 2.54) < 1e-8)
    #expect(scene.children[1].spatialGeometry?.flags["enabled"] == true)
    #expect(p.slides[0].elements.first { $0.id == "enhanced" }?.spatialGeometry?.flags["extrusion"] == true)
}

@Test func workbookStoredValuesAndSparseRanges() throws {
    let parts: [String: Data] = [
        "_rels/.rels": Data("<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"main\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>".utf8),
        "xl/workbook.xml": Data("<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"Fictional Sheet\" r:id=\"s\"/></sheets></workbook>".utf8),
        "xl/_rels/workbook.xml.rels": Data("<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"s\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/s.xml\"/><Relationship Id=\"strings\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings\" Target=\"sharedStrings.xml\"/></Relationships>".utf8),
        "xl/sharedStrings.xml": Data("<sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><si><r><t>Fictional</t></r><r><t> text</t></r></si></sst>".utf8),
        "xl/worksheets/s.xml": Data("<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData><row r=\"1\"><c r=\"A1\" t=\"s\"><v>0</v></c><c r=\"B1\"><f>2+3</f><v>5</v></c></row><row r=\"3\"><c r=\"A3\"><v>7</v></c></row></sheetData></worksheet>".utf8)
    ]
    let data = try ZIPWriter.write(parts, compress: true), book = try WorkbookDataReader.readXLSX(data)
    #expect(book.sheets[0].cells["A1"]?.value == "Fictional text" && book.sheets[0].cells["B1"]?.formula == "2+3")
    let range = try book.resolve("'Fictional Sheet'!$A$1:$A$3")
    #expect(range.pointCount == 3 && range.points == [.init(index: 0, text: "Fictional text"), .init(index: 2, text: "7")])
    #expect(throws: SlideError.self) { try book.resolve("'Fictional Sheet'!A1:XFD1048576", maxCells: 100) }
    #expect(throws: SlideError.self) { try book.resolve("SUM(A1:A3)") }
    #expect(throws: SlideError.self) { try book.resolve("'Fictional Sheet'!A1$") }
    #expect(throws: SlideError.self) { try WorkbookDataReader.readXLSX(data, limits: .init(maxTableCells: 1)) }
    #expect(try JSONDecoder().decode(WorkbookData.self, from: JSONEncoder().encode(book)) == book)
}

@Test func embeddedWorkbookAndExplicitExternalProvider() throws {
    let data = try fixture("stored.pptx"), original = try Presentation(data: data)
    let chart = try #require(original.slides.flatMap(\.elements).first { $0.chart != nil }?.chart)
    #expect(chart.workbook != nil && chart.groups[0].series[0].values?.workbookPoints != nil)
    let bytes = try original.asset(at: #require(chart.externalData?.path))
    let external = try changedFixture("stored.pptx") { parts in
        let path = "ppt/charts/_rels/chart1.xml.rels", root = try MarkupNode.parse(#require(parts[path]), part: path, limits: .init())
        let rel = try #require(root.children.first); rel.set("Target", "https://example.invalid/fictional.xlsx"); rel.set("TargetMode", "External"); parts[path] = Data(root.xml.utf8)
    }
    let unresolved = try Presentation(data: external)
    #expect(unresolved.slides.flatMap(\.elements).first { $0.chart != nil }?.chart?.workbook == nil)
    var options = ReadOptions(); options.workbookProvider = { reference in
        guard reference.externalTarget == "https://example.invalid/fictional.xlsx" else { throw SlideError.invalidModel("外部参照") }; return bytes
    }
    let resolved = try Presentation(data: external, options: options)
    #expect(resolved.slides.flatMap(\.elements).first { $0.chart != nil }?.chart?.workbook == chart.workbook)
}

@Test(arguments: ["remaining-native.keynote.zip", "remaining-preuff.keynote.zip"])
func keynoteFormulaMergeAndAxes(_ name: String) throws {
    let p = try Presentation(data: fixture(name))
    let table = try #require(p.slides[0].elements.first { $0.table != nil }?.table), formula = try #require(table.rows[1][0].nativeFormula)
    #expect(table.rows[0][0].columnSpan == 2 && table.rows[0][1].isMergeContinuation)
    #expect(table.rows[1][0].value?.number == 5 && formula.tokens.map(\.kind) == ["NUMBER_NODE", "NUMBER_NODE", "ADDITION_NODE"])
    #expect(formula.tokens[0].number == 2 && formula.tokens[1].number == 3 && formula.dialect == "keynote:TSCE")
    let axis = try #require(p.slides[0].elements.first { $0.chart != nil }?.chart?.axes.first)
    #expect(axis.minimum == -5 && axis.maximum == 100 && axis.title == "Fictional axis" && axis.isDeleted == false)
    #expect(axis.nativeProperties?["valueshowmajorgridlines"] == "1")
    #expect(try JSONDecoder().decode(Table.self, from: JSONEncoder().encode(table)) == table)
}

@Test(arguments: ["stored.pptx", "semantic-reading.odp", "remaining-native.keynote.zip"])
func fileBackedSelectionAndChangeDetection(_ name: String) throws {
    let bytes = try fixture(name), url = FileManager.default.temporaryDirectory.appendingPathComponent("fictional-\(UUID().uuidString)")
    try bytes.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
    let reader = try SlideReader(fileBackedURL: url, cacheBytes: 128 << 10)
    let snapshot = try SlideReader(data: bytes)
    for descriptor in reader.slideDescriptors { #expect(try reader.slide(id: descriptor.id).slide == snapshot.slide(id: descriptor.id).slide) }
    // 同じpathでatomic置換しても、元descriptorへ読み続けない。
    try bytes.write(to: url, options: .atomic)
    #expect(throws: SlideError.self) { try reader.slide(id: reader.slideDescriptors[0].id) }
    #expect(throws: SlideError.self) { try reader.asset(at: "missing") }
    #expect(try snapshot.slide(id: snapshot.slideDescriptors[0].id).slide.id == snapshot.slideDescriptors[0].id)
}

@Test(arguments: [("legacy-gzip.key.zip", PresentationFormat.keynoteLegacy, "Fictional legacy Keynote"), ("legacy-xml.key.zip", PresentationFormat.keynoteLegacy, "Fictional legacy Keynote"), ("legacy-impress.sxi", .sxi, "Fictional legacy Impress")])
func legacyXMLReadOnlyCodecs(_ input: (String, PresentationFormat, String)) throws {
    let data = try fixture(input.0), result = try Presentation(data: data)
    #expect(result.sourceFormat == input.1 && result.slides.count == 1 && result.plainText == input.2)
    #expect(try PresentationFormat.detect(data) == input.1)
    #expect(!result.readWarnings.isEmpty)
    #expect(throws: SlideError.self) { try result.write().data }
    #expect(try SlideReader(data: data).slide(id: result.slides[0].id).slide == result.slides[0])
}

@Test func legacyPPTLivePersistOrderAndProducerText() throws {
    let data = try fixture("libreoffice-legacy.ppt"), p = try Presentation(data: data)
    #expect(p.sourceFormat == .ppt && p.size == .init(width: 960, height: 540) && p.slides.count == 2)
    #expect(p.slides[0].elements.prefix(3).map(\.plainText) == ["売上成長 — 90 days", "顧客集中", "実行"])
    #expect(p.slides[1].plainText == "Metrics" && p.slides.map(\.id) == ["256", "257"])
    #expect(try p.asset(at: "original.ppt") == data)
    #expect(throws: SlideError.self) { try p.write().data }
    #expect(throws: SlideError.self) { try Presentation(data: data, options: .init(limits: .init(maxExpandedBytes: 100))) }
    let reader = try SlideReader(data: data)
    #expect(try reader.slide(id: p.slides[1].id).slide == p.slides[1])
}

@Test func inherited3DAndModelResourceReferences() throws {
    let data = try changedFixture("math-3d.pptx") { parts in
        let slidePath = "ppt/slides/slide1.xml", layoutPath = "ppt/slideLayouts/slideLayout7.xml"
        let slide = try MarkupNode.parse(#require(parts[slidePath]), part: slidePath, limits: .init())
        let layout = try MarkupNode.parse(#require(parts[layoutPath]), part: layoutPath, limits: .init())
        let shape = try #require(slide.descendants("sp").first { $0.child("nvSpPr")?.child("cNvPr")?.attr("id") == "900" })
        let props = try #require(shape.child("spPr")), scene = try #require(props.child("scene3d")), threeD = try #require(props.child("sp3d"))
        props.remove(["scene3d", "sp3d"])
        let nv = try #require(shape.child("nvSpPr")?.child("nvPr")); nv.content.append(.node(try MarkupNode.fragment("<p:ph type=\"body\" idx=\"42\"/>")))
        let copy = try MarkupNode.parse(Data(shape.xml.utf8), part: layoutPath, limits: .init())
        copy.child("nvSpPr")?.child("cNvPr")?.set("id", "990")
        copy.child("spPr")?.content.append(contentsOf: [.node(scene), .node(threeD)])
        try #require(layout.child("cSld")?.child("spTree")).content.append(.node(copy))
        parts[slidePath] = Data(slide.xml.utf8); parts[layoutPath] = Data(layout.xml.utf8)
    }
    let p = try Presentation(data: data), e = try #require(p.slides[0].elements.first { $0.id == "900" })
    #expect(e.scene3D == nil)
    let resolved = try p.resolveElement(slideID: p.slides[0].id, elementID: e.id)
    #expect(resolved.element.scene3D?.cameraPreset == "perspectiveFront" && resolved.element.shape3D?.extrusionHeight == 2)
    #expect(resolved.origins["scene3D"]?.kind == .layout && resolved.origins["shape3D"]?.kind == .layout)
    let modelBytes = Data("fictional 3D asset".utf8)
    let modelData = try changedFixture("stored.pptx") { parts in
        let path = "ppt/slides/slide1.xml", root = try MarkupNode.parse(#require(parts[path]), part: path, limits: .init())
        let graphic = try #require(root.descendants("graphicData").first)
        graphic.content = [.node(try MarkupNode.fragment("<m:model3d xmlns:m=\"http://schemas.microsoft.com/office/drawing/2017/model3d\" r:embed=\"fictional3d\"/>"))]
        graphic.set("uri", "http://schemas.microsoft.com/office/drawing/2017/model3d"); parts[path] = Data(root.xml.utf8)
        let relPath = "ppt/slides/_rels/slide1.xml.rels", rels = try MarkupNode.parse(#require(parts[relPath]), part: relPath, limits: .init())
        let rel = MarkupNode(name: "Relationship", namespace: NS.rels, qualifiedName: "Relationship")
        rel.set("Id", "fictional3d"); rel.set("Type", "http://schemas.microsoft.com/office/2017/10/relationships/model3d"); rel.set("Target", "../media/fictional.bin")
        rels.content.append(.node(rel)); parts[relPath] = Data(rels.xml.utf8); parts["ppt/media/fictional.bin"] = modelBytes
    }
    let modelDeck = try Presentation(data: modelData), model = try #require(modelDeck.slides[0].elements.first { $0.model3D != nil }?.model3D)
    #expect(model.model.path == "ppt/media/fictional.bin" && model.model.externalTarget == nil)
    #expect(try modelDeck.asset(at: #require(model.model.path)) == modelBytes)
}

@Test func fileArchiveReadsOnlyRequestedPayloadAndBoundsCache() throws {
    let parts = Dictionary(uniqueKeysWithValues: (0..<8).map { ("asset\($0).bin", Data(repeating: UInt8($0), count: 2 << 20)) })
    let bytes = try ZIPWriter.write(parts, compress: false), url = FileManager.default.temporaryDirectory.appendingPathComponent("fictional-large-\(UUID().uuidString)")
    try bytes.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
    let archive = try PackageArchive(contentsOf: url, cacheBytes: 64 << 10)
    let index = try #require(archive.fileStatistics)
    #expect(index.fetchedBytes < bytes.count / 4 && index.peakCachedBytes <= 64 << 10)
    #expect(try archive.read("asset3.bin") == parts["asset3.bin"])
    #expect(try #require(archive.fileStatistics).fetchedBytes < bytes.count / 2)
    let handle = try FileHandle(forWritingTo: url); try handle.seek(toOffset: 0); try handle.write(contentsOf: Data([0])); try handle.close()
    #expect(throws: SlideError.self) { try archive.read("asset3.bin") }
}

@Test func legacyXMLDetectionRequiresPresentationAndRetainsUnknown() throws {
    let unrelated = try ZIPWriter.write(["index.xml": Data("<fictional/>".utf8)], compress: true)
    #expect(throws: SlideError.self) { try PresentationFormat.detect(unrelated) }
    let data = try changedFixture("legacy-xml.key.zip") { parts in
        parts["index.apxl"] = Data(String(decoding: try #require(parts["index.apxl"]), as: UTF8.self).replacingOccurrences(of: "<sf:p>Fictional legacy Keynote</sf:p>", with: "<sf:unknown-picture sf:href=\"fictional.png\"/>").utf8)
    }
    let p = try Presentation(data: data)
    #expect(!p.slides[0].elements.isEmpty && p.slides[0].elements[0].sourceProperties?.descendants(named: "unknown-picture").count == 1)
    let archive = try PackageArchive(fixture("legacy-xml.key.zip")), xml = try archive.read("index.apxl")
    #expect(try PresentationFormat.detect(xml) == .keynoteLegacy)
    #expect(try Presentation(data: xml).plainText == "Fictional legacy Keynote")
}

@Test func keynoteProducerFormulaAndMergeMatchAppValues() throws {
    // Keynote 15.4: A2=2、B2=3、C2="=A2+B2"、A1:B1結合。
    let p = try Presentation(data: fixture("keynote-formula-15.4.key.zip"))
    let table = try #require(p.slides[0].elements.first { $0.table != nil }?.table)
    #expect(table.rows[0][0].columnSpan == 2 && table.rows[0][1].isMergeContinuation)
    #expect(table.rows[1][2].value?.number == 5)
    let tokens = try #require(table.rows[1][2].nativeFormula).tokens
    #expect(tokens.map(\.kind) == ["CELL_REFERENCE_NODE", "CELL_REFERENCE_NODE", "ADDITION_NODE"])
    #expect(tokens[0].row == 1 && tokens[0].column == 0 && tokens[1].row == 1 && tokens[1].column == 1)
    #expect(!p.readWarnings.contains { $0.element == "table" })
}

@Test(arguments: ["1.2", "1.3", "1.4"])
func odpSemanticReadingAcrossDeclaredVersions(_ version: String) throws {
    let data = try changedFixture("semantic-reading.odp") { parts in
        for part in ["content.xml", "styles.xml", "META-INF/manifest.xml"] {
            let text = String(decoding: try #require(parts[part]), as: UTF8.self)
            parts[part] = Data(text.replacingOccurrences(of: "version=\"1.3\"", with: "version=\"\(version)\"").utf8)
        }
        if version == "1.4", let content = parts["content.xml"] {
            parts["content.xml"] = Data(String(decoding: content, as: UTF8.self).replacingOccurrences(of: "draw:handle-position=\"$0 ?edge\"", with: "draw:handle-position-x=\"$0\" draw:handle-position-y=\"?edge\"").utf8)
        }
    }
    let p = try Presentation(data: data)
    #expect(p.slides[0].elements.first { $0.id == "enhanced" }?.enhancedGeometry?.path?.count == 16)
    #expect(p.slides[0].elements.contains { $0.equation?.dialect == .mathML })
    let geometry = try #require(p.slides[0].elements.first { $0.id == "enhanced" }?.enhancedGeometry)
    #expect(try GeometryEvaluator.evaluate(geometry).handles[0].values["handle-position-y"] == 50)
}
