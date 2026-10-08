import Foundation
import Testing
@testable import SlideCore
import SwiftSlides

private let projectionFixtures = ["reading-models.pptx", "reading-models-strict.pptx"]
private func projection(_ name: String) throws -> Presentation { try Presentation(data: fixture(name)) }

@Test(arguments: projectionFixtures)
func unitSpacingFieldsAndSourceStyles(_ name: String) throws {
    let p = try projection(name), e = p.slides[0].elements[0]
    let paragraph = try #require(e.text?.paragraphs[0])
    #expect(paragraph.style.lineSpacingValue == .points(18))
    #expect(paragraph.style.lineSpacing == nil)
    #expect(paragraph.style.spaceBeforeValue == .percentage(0.5))
    #expect(paragraph.style.spaceBefore == nil)
    #expect(paragraph.style.spaceAfterValue == .points(0))
    #expect(e.text?.listStyle?.levels[0]?.paragraph.effectiveLineSpacing == .percentage(1))
    #expect(e.text?.listStyle?.levels[0]?.paragraph.effectiveSpaceBefore == .percentage(0))
    #expect(p.defaultTextStyle?.levels[0]?.paragraph.effectiveLineSpacing == .percentage(1.2))
    #expect(paragraph.runs.count == 3)
    let run = paragraph.runs[1], field = try #require(run.field)
    #expect(field.type == "slidenum" && field.cachedText == "7")
    #expect(field.paragraphStyle?.paragraph.effectiveLineSpacing == .points(20))
    #expect(run.style.font.size == 24 && run.style.bold == false)
    #expect(try p.slideNumber(for:p.slides[0].id) == 7)
    let layout = try p.readLayout(at: #require(p.slides[0].layoutPath)).layout
    let master = try p.readMaster(at: #require(layout.masterPath)).master
    for style in ["titleStyle", "bodyStyle", "otherStyle"] {
        #expect(master.textStyles[style]?.levels[0]?.paragraph.effectiveLineSpacing == .points(22))
        #expect(master.textStyles[style]?.levels[0]?.paragraph.effectiveSpaceAfter == .percentage(1))
    }
    #expect(try p.write().data == fixture(name))
}

@Test func spacingOverlayAndFieldEvaluationAreExplicit() throws {
    let source = ParagraphStyle(lineSpacingValue:.points(18),spaceBeforeValue:.percentage(0.5))
    let direct = ParagraphStyle(spaceBefore:0,lineSpacingValue:.percentage(0))
    let combined = source.overlaying(direct)
    #expect(combined.effectiveLineSpacing == .percentage(0))
    #expect(combined.effectiveSpaceBefore == .points(0))
    let context = TextFieldContext(slideNumber:9,date:Date(timeIntervalSince1970:1_728_299_434),localeIdentifier:"en_US_POSIX",timeZoneIdentifier:"UTC")
    var field = TextField(id:"{11111111-1111-1111-1111-111111111111}",type:"slidenum",cachedText:"cached")
    #expect(TextFieldEvaluator.evaluate(field,context:context).text == "9")
    let formats = ["datetime1":"10/07/2024","datetime2":"Monday, October 07, 2024","datetime3":"07 October 2024","datetime4":"October 07, 2024","datetime5":"07-Oct-24","datetime6":"October 24","datetime7":"Oct-24","datetime8":"10/07/2024 11:10 AM","datetime9":"10/07/2024 11:10:34 AM","datetime10":"11:10","datetime11":"11:10:34","datetime12":"11:10 AM","datetime13":"11:10:34 AM","datetimeFigureOut":"10/07/2024"]
    for (type,text) in formats { field.type = type; let result = TextFieldEvaluator.evaluate(field,context:context); #expect(result.text == text); #expect(result.diagnostics.isEmpty) }
    field.type = "datetime"; #expect(TextFieldEvaluator.evaluate(field,context:context).diagnostics.isEmpty)
    field.type = "uaqdatetime1"; #expect(TextFieldEvaluator.evaluate(field,context:context).text == "cached")
    #expect(!TextFieldEvaluator.evaluate(field,context:context).diagnostics.isEmpty)
    field.type = "datetime1"
    var bad = context; bad.timeZoneIdentifier = "Unknown/Nowhere"
    #expect(TextFieldEvaluator.evaluate(field,context:bad).text == "cached")
    bad = context; bad.localeIdentifier = "th_TH@calendar=buddhist"
    #expect(TextFieldEvaluator.evaluate(field,context:bad).text == "cached")
    var p = try projection(projectionFixtures[0]); p.slides[1].isHidden = true; p.slides.reverse()
    #expect(try p.slideNumber(for:p.slides[1].id) == 8)
    #expect(p.slides[1].elements[0].text?.paragraphs[0].runs[1].text == "7")
}

@Test func spacingAndFieldsSaveWithoutFlattening() throws {
    var s = Slide(); s.addText("field",frame:.init(x:0,y:0,width:100,height:30))
    s.elements[0].text?.paragraphs[0] = .init(runs:[.init("7",field:.init(id:"{11111111-1111-1111-1111-111111111111}",type:"slidenum",cachedText:"7",paragraphStyle:.init(paragraph:.init(lineSpacingValue:.points(20)),text:.init(bold:false))))],style:.init(lineSpacing:9,lineSpacingValue:.points(0),spaceBeforeValue:.percentage(0.5),spaceAfterValue:.points(0)))
    var p = Presentation(slides:[s]); p.firstSlideNumber = 7
    let read = try Presentation(data:p.write().data)
    #expect(read.firstSlideNumber == 7)
    #expect(read.slides[0].elements[0].text?.paragraphs[0].style.effectiveLineSpacing == .points(0))
    #expect(read.slides[0].elements[0].text?.paragraphs[0].runs[0].field?.paragraphStyle?.paragraph.effectiveLineSpacing == .points(20))
    p.slides[0].elements[0].text?.paragraphs[0].runs[0].text = "8"
    #expect(throws:SlideError.self) { try p.write().data }
    var existing = try projection(projectionFixtures[0]); existing.firstSlideNumber = 9
    #expect(try Presentation(data:existing.write().data).firstSlideNumber == 9)
    let plan = try existing.planWrite(); existing.firstSlideNumber = 10
    #expect(throws:SlideError.stalePlan) { try existing.write(using:plan) }
}

@Test(arguments: projectionFixtures)
func colorGeometryAndOuterShadowProjection(_ name: String) throws {
    let p = try projection(name), e = p.slides[0].elements[0]
    guard case .solid(let color) = e.fill else { Issue.record("missing fill"); return }
    let resolved = ColorResolver.resolve(color,theme:["accent1":.rgb("336699")])
    #expect(abs(try #require(resolved.color).alpha - 0.35) < 0.000001)
    #expect(resolved.diagnostics.isEmpty)
    #expect(ColorResolver.resolve(e.stroke!.color).color?.alpha == 0)
    #expect(e.rotation == 90 && e.isFlippedHorizontally)
    let geometry = try #require(e.customGeometry), path = try #require(geometry.paths.first)
    #expect(e.geometry == nil && path.width == 100 && path.height == 50)
    #expect(path.fillMode == "none" && path.stroke == false && path.commands.count == 5)
    #expect(path.commands[2] == .quadratic(control:.init(x:"50",y:"25"),end:.init(x:"100",y:"50")))
    guard case .outerShadow(let shadow) = e.effects?.direct?.first else { Issue.record("missing shadow"); return }
    #expect(shadow.distance == 2 && shadow.direction == 90 && shadow.blurRadius == 1)
    #expect(shadow.scaleX == 1 && shadow.scaleY == 0.5 && shadow.rotatesWithShape == false)
    #expect(e.effects?.reference?.index == 1)
    #expect(ColorResolver.resolve(try #require(shadow.color)).color?.alpha == 0.5)
    #expect(!p.sourceThemes[0].effectStyles!.isEmpty)
}

@Test func colorOrderUnknownAndThemeComposition() throws {
    let alpha = ColorTransform(name:"alpha",value:"50000"), mod = ColorTransform(name:"alphaMod",value:"50000"), off = ColorTransform(name:"alphaOff",value:"20000")
    let one = Color.value(.init(base:.sRGB("123456"),transforms:[alpha,off,mod]))
    let two = Color.value(.init(base:.sRGB("123456"),transforms:[alpha,mod,off]))
    #expect(ColorResolver.resolve(one).color?.alpha != ColorResolver.resolve(two).color?.alpha)
    let themed = Color.value(.init(base:.scheme("tx1"),transforms:[mod]))
    #expect(ColorResolver.resolve(themed,theme:["dk1":one],colorMap:["tx1":"dk1"]).color?.alpha == 0.175)
    #expect(ColorResolver.resolve(.theme("phClr"),placeholder:one).color?.alpha == ColorResolver.resolve(one).color?.alpha)
    #expect(ColorResolver.resolve(.theme("cycle"),theme:["cycle":.theme("cycle")]).color == nil)
    let unknown = Color.value(.init(base:.sRGB("123456"),transforms:[.init(name:"tint",value:"50000")]))
    #expect(ColorResolver.resolve(unknown).color == nil && !ColorResolver.resolve(unknown).diagnostics.isEmpty)
    for value in ["0", "50000", "100000"] { #expect(ColorResolver.resolve(.value(.init(base:.sRGB("000000"),transforms:[.init(name:"alpha",value:value)]))).color?.alpha == Double(value)! / 100_000) }
}

@Test(arguments: projectionFixtures)
func inheritedPartsTablesChartsAndSavedDiagram(_ name: String) throws {
    let p = try projection(name), s = p.slides[0]
    #expect(s.showsMasterShapes == false && s.colorMapOverride?["accent1"] == "accent2")
    let result = try p.readLayout(at: #require(s.layoutPath)), layout = result.layout
    #expect(layout.showsMasterShapes == false && layout.usesMasterColorMapping == true)
    #expect(layout.elements[1].table?.rows[1][2].text.plainText == "作業時間")
    #expect(layout.elements[1].table?.columnWidths.count == 3)
    let image = try #require(layout.elements[2].image)
    #expect(try p.asset(at:#require(image.path)).starts(with:[137,80,78,71]))
    let master = try p.readMaster(at:#require(layout.masterPath)).master
    #expect(master.elements[0].id == s.elements[0].id && master.path != layout.path)
    #expect(master.themePath != nil && master.layoutPaths.contains(layout.path))
    let chart = try #require(s.elements[1].chart), series = try #require(chart.groups.first?.series.first)
    #expect(s.elements[1].kind == .opaque)
    #expect(chart.groups[0].kind == "barChart" && chart.groups[0].orientation == "col")
    #expect(series.title == "Series" && series.categories?.formula == "Sheet1!A1:A3")
    #expect(series.categories?.points.map(\.index) == [0,2])
    #expect(series.values?.source == .numberLiteral && series.values?.points.map(\.number) == [10,30])
    #expect(chart.axes[1].minimum == 0 && chart.axes[1].maximum == 40)
    #expect(chart.legendPosition == "r" && chart.title == "Fictional chart")
    let diagram = try #require(s.elements[2].diagram)
    #expect(diagram.dataTexts == ["Data text"] && diagram.elements.count == 1)
    #expect(diagram.elements[0].text?.plainText == "Before7After")
    #expect(diagram.drawingFrame == .init(x:1,y:2,width:100,height:100))
    #expect(diagram.drawingChildFrame == .init(x:0,y:0,width:200,height:200))
    #expect(diagram.elements[0].customGeometry != nil)
}

@Test(arguments: projectionFixtures)
func projectionPreservesSourceAndRefusesUnsupportedEdits(_ name: String) throws {
    let bytes = try fixture(name); var p = try Presentation(data:bytes)
    let original = try parts(bytes)
    p.slides[0].elements[0].frame?.x += 1
    let output = try p.write().data, saved = try parts(output)
    #expect(saved["ppt/charts/readingChart.xml"] == original["ppt/charts/readingChart.xml"])
    #expect(saved["ppt/diagrams/drawing.xml"] == original["ppt/diagrams/drawing.xml"])
    let reopened = try Presentation(data:output)
    #expect(reopened.slides[0].elements[0].customGeometry == p.slides[0].elements[0].customGeometry)
    p.slides[0].elements[0].customGeometry?.paths[0].width = 200
    #expect(throws:SlideError.self) { try p.write().data }
    p = try Presentation(data:bytes); p.slides[0].elements[0].effects?.reference?.index = 2
    #expect(throws:SlideError.self) { try p.write().data }
    p = try Presentation(data:bytes); p.slides[0].elements[1].chart?.groups[0].series[0].values?.points[0].text = "100"
    #expect(throws:SlideError.self) { try p.write().data }
    p = try Presentation(data:bytes); p.slides[0].elements[0].fill = .solid(.value(.init(base:.sRGB("FFFFFF"),transforms:[.init(name:"alpha",value:"0")])) )
    #expect(throws:SlideError.self) { try p.write().data }
}

@Test func missingCachesReferencesAndMalformedPartsAreVisible() throws {
    let bytes = try changedFixture("reading-models.pptx") { parts in
        parts["ppt/diagrams/data.xml"] = Data(String(decoding:parts["ppt/diagrams/data.xml"]!,as:UTF8.self).replacingOccurrences(of:"relId=\"drawing\"",with:"relId=\"absent\"").utf8)
    }
    #expect(throws:SlideError.self) { try Presentation(data:bytes) }
    let noDrawing = try changedFixture("reading-models.pptx") { parts in
        let root = try MarkupNode.parse(parts["ppt/diagrams/data.xml"]!,part:"data",limits:.init())
        root.content.removeAll { if case .node(let n) = $0 { n.name == "extLst" } else { false } }
        parts["ppt/diagrams/data.xml"] = Data(root.xml.utf8)
    }
    let p = try Presentation(data:noDrawing)
    #expect(p.slides[0].elements[2].diagram?.dataTexts == ["Data text"])
    #expect(p.readDiagnostics.contains { $0.feature == "OBJ-001" && $0.message.contains("ありません") })
    #expect(try p.write().data == noDrawing)
    let missing = try changedFixture("reading-models.pptx") { $0.removeValue(forKey:"ppt/charts/readingChart.xml") }
    #expect(throws:SlideError.self) { try Presentation(data:missing) }
    let brokenLayout = try changedFixture("reading-models.pptx") { $0["ppt/slideLayouts/slideLayout1.xml"] = Data("broken".utf8) }
    let broken = try Presentation(data:brokenLayout)
    #expect(throws:SlideError.self) { try broken.readLayout(at:"ppt/slideLayouts/slideLayout1.xml") }
}

@Test func oldJSONMissingProjectionPropertiesDecodes() throws {
    let encoder = JSONEncoder(), decoder = JSONDecoder()
    func legacy<T: Codable>(_ value: T, removing keys: [String]) throws -> T {
        var object = try JSONSerialization.jsonObject(with:encoder.encode(value)) as! [String:Any]
        for key in keys { object.removeValue(forKey:key) }
        return try decoder.decode(T.self,from:JSONSerialization.data(withJSONObject:object))
    }
    let style = try legacy(ParagraphStyle(lineSpacing:1.2),removing:["lineSpacingValue","spaceBeforeValue","spaceAfterValue"])
    #expect(style.effectiveLineSpacing == .percentage(1.2))
    #expect(try legacy(TextRun("old"),removing:["field"]).field == nil)
    #expect(try legacy(TextBody("old"),removing:["listStyle"]).listStyle == nil)
    #expect(try legacy(Element(),removing:["customGeometry","effects","chart","diagram"]).customGeometry == nil)
    #expect(try legacy(Slide(),removing:["showsMasterShapes","colorMapOverride","usesMasterColorMapping","backgroundReference","themeOverridePath"]).showsMasterShapes == nil)
}

@Test(arguments: projectionFixtures)
func fieldAndSpacingEditsKeepRunsAndStrictNamespace(_ name: String) throws {
    var p = try projection(name)
    let list = p.slides[0].elements[0].text?.listStyle
    p.slides[0].elements[0].text?.paragraphs[0].style.lineSpacingValue = .percentage(1.1)
    p.slides[0].elements[0].text?.paragraphs[0].runs[1].text = "8"
    p.slides[0].elements[0].text?.paragraphs[0].runs[1].field?.cachedText = "8"
    let output = try p.write().data, reopened = try Presentation(data:output)
    let body = try #require(reopened.slides[0].elements[0].text)
    #expect(body.listStyle == list && body.paragraphs[0].runs.count == 3)
    #expect(body.paragraphs[0].runs[1].field?.cachedText == "8")
    #expect(body.paragraphs[0].style.effectiveLineSpacing == .percentage(1.1))
    if name.contains("strict") {
        let xml = try #require(parts(output)["ppt/slides/slide1.xml"])
        let root = try MarkupNode.parse(xml,part:"slide",limits:.init())
        #expect(root.descendants("fld").first?.child("pPr")?.namespace == NS.strictA)
    }
}

@Test func clonedFieldsRenewModelIdentityAndChartReferences() throws {
    var s = Slide(); s.addText("7",frame:.init(x:0,y:0,width:100,height:40))
    s.elements[0].text?.paragraphs[0].runs[0].field = .init(id:"{11111111-1111-1111-1111-111111111111}",type:"slidenum",cachedText:"7")
    var p = try Presentation(data:Presentation(slides:[s]).write().data)
    let oldID = p.slides[0].elements[0].text?.paragraphs[0].runs[0].field?.id
    let id = try p.duplicateSlide(id:p.slides[0].id)
    let newID = try #require(p.slides.last?.elements[0].text?.paragraphs[0].runs[0].field?.id)
    #expect(oldID != newID)
    let reopened = try Presentation(data:p.write().data)
    #expect(reopened.slides.last?.elements[0].text?.paragraphs[0].runs[0].field?.id == newID)
    #expect(try p.slideNumber(for:id) == 2)
    var chartDocument = try Presentation(data:fixture())
    _ = try chartDocument.duplicateSlide(id:chartDocument.slides[1].id)
    let chartPath = try #require(chartDocument.slides.last?.elements[0].chart?.part.path)
    #expect(chartPath != chartDocument.slides[1].elements[0].chart?.part.path)
    #expect(try chartDocument.asset(at:chartPath).count > 0)
    let layoutPath = try #require(chartDocument.slides.last?.layoutPath)
    #expect(try chartDocument.readLayout(at:layoutPath).layout.masterPath != nil)
}

@Test func malformedUnknownValuesStayPreservedAndDiagnosed() throws {
    let changed = try changedFixture("reading-models.pptx") { parts in
        let xml = String(decoding:parts["ppt/slides/slide1.xml"]!,as:UTF8.self)
            .replacingOccurrences(of:"type=\"slidenum\"",with:"type=\"futureField\"")
            .replacingOccurrences(of:"<a:gdLst/>",with:"<a:gdLst><a:gd name=\"x\" fmla=\"val 20\"/></a:gdLst>")
            .replacingOccurrences(of:"<a:pt x=\"100\" y=\"0\"/>",with:"<a:pt x=\"x\" y=\"0\"/>")
        parts["ppt/slides/slide1.xml"] = Data(xml.utf8)
    }
    let p = try Presentation(data:changed)
    #expect(p.readDiagnostics.contains { $0.feature == "TXT-020" })
    #expect(p.readDiagnostics.contains { $0.feature == "GEO-004" })
    #expect(p.slides[0].elements[0].customGeometry?.guides.first?.formula == "val 20")
    #expect(try p.write().data == changed)
    let noCache = try changedFixture("reading-models.pptx") { parts in
        let xml = String(decoding:parts["ppt/charts/readingChart.xml"]!,as:UTF8.self)
        let start = xml.range(of:"<c:strCache>")!.lowerBound, end = xml.range(of:"</c:strCache>")!.upperBound
        parts["ppt/charts/readingChart.xml"] = Data(xml.replacingCharacters(in:start..<end,with:"").utf8)
    }
    let withoutCache = try Presentation(data:noCache)
    let data = withoutCache.slides[0].elements[1].chart?.groups[0].series[0].categories
    #expect(data?.formula == "Sheet1!A1:A3" && data?.source == .stringReference && data?.points.isEmpty == true)
    #expect(withoutCache.readDiagnostics.contains { $0.feature == "CHT-004" })
    let percent = Color.value(.init(base:.sRGB("000000"),transforms:[.init(name:"alpha",value:"50%")]))
    #expect(ColorResolver.resolve(percent).color?.alpha == 0.5)
}

@Test func inheritedReadingHonorsCancellationAndLimits() async throws {
    let p = try projection(projectionFixtures[0]), path = try #require(p.slides[0].layoutPath)
    let result = try await p.readLayout(at:path)
    #expect(result.layout.elements.count == 3)
    let master = try await p.readMaster(at:#require(result.layout.masterPath))
    #expect(master.master.elements.count == 1)
    let task = Task { try await p.readLayout(at:path) }; task.cancel()
    do { _ = try await task.value; Issue.record("cancelled read succeeded") } catch is CancellationError { }
}

@Test func themeOverrideAndColorValuesAreSharedAcrossProperties() throws {
    let bytes = try changedFixture("reading-models.pptx") { parts in
        let typeRoot = try MarkupNode.parse(parts["[Content_Types].xml"]!,part:"types",limits:.init())
        let override = try MarkupNode.parse(Data("<Override xmlns=\"\(NS.types)\" PartName=\"/ppt/theme/override.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.themeOverride+xml\"/>".utf8),part:"override",limits:.init())
        typeRoot.content.append(.node(override)); parts["[Content_Types].xml"] = Data(typeRoot.xml.utf8)
        parts["ppt/theme/override.xml"] = Data("<a:themeOverride xmlns:a=\"\(NS.a)\"><a:clrScheme name=\"override\"><a:accent1><a:srgbClr val=\"336699\"><a:alpha val=\"50000\"/></a:srgbClr></a:accent1></a:clrScheme></a:themeOverride>".utf8)
        let relPath = "ppt/slides/_rels/slide1.xml.rels"
        let rel = try MarkupNode.parse(parts[relPath]!,part:relPath,limits:.init())
        rel.content.append(.node(try MarkupNode.parse(Data("<Relationship xmlns=\"\(NS.rels)\" Id=\"override\" Type=\"\(NS.r)/themeOverride\" Target=\"../theme/override.xml\"/>".utf8),part:relPath,limits:.init())))
        parts[relPath] = Data(rel.xml.utf8)
        let slide = try MarkupNode.parse(parts["ppt/slides/slide1.xml"]!,part:"slide",limits:.init())
        let solid = try MarkupNode.fragment("<a:solidFill><a:srgbClr val=\"336699\"><a:alpha val=\"50000\"/></a:srgbClr></a:solidFill>")
        slide.descendants("rPr").first?.content.append(.node(solid))
        parts["ppt/slides/slide1.xml"] = Data(slide.xml.utf8)
        let layout = try MarkupNode.parse(parts["ppt/slideLayouts/slideLayout1.xml"]!,part:"layout",limits:.init())
        layout.descendants("tcPr").first?.content.append(.node(solid))
        parts["ppt/slideLayouts/slideLayout1.xml"] = Data(layout.xml.utf8)
    }
    let p = try Presentation(data:bytes)
    #expect(p.slides[0].themeOverridePath == "ppt/theme/override.xml")
    let override = try #require(p.sourceThemes.first { $0.isOverride == true })
    #expect(ColorResolver.resolve(try #require(override.colors["accent1"])).color?.alpha == 0.5)
    let text = try #require(p.slides[0].elements[0].text?.paragraphs[0].runs[0].style.color)
    #expect(ColorResolver.resolve(text).color?.alpha == 0.5)
    let layout = try p.readLayout(at:#require(p.slides[0].layoutPath))
    guard case .solid(let cellColor) = layout.layout.elements[1].table?.rows[0][0].fill,
          case .solid(let background) = p.slides[0].background else { Issue.record("missing direct colors"); return }
    #expect(ColorResolver.resolve(cellColor).color?.alpha == 0.5)
    #expect(ColorResolver.resolve(background).color?.alpha == 0.5)
    #expect(layout.diagnostics.allSatisfy { $0.location.slideID == nil })
    #expect(try p.write().data == bytes)
}
