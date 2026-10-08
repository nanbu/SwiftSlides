import Foundation
import Testing
@testable import SlideCore
import SwiftSlides
@testable import SlideKeynote

@Test func drawingMLGuideOperatorsAndEllipticalArc() throws {
    let formulas: [(String, Double)] = [("*/ 6 7 2",21),("+- 6 7 2",11),("+/ 6 8 2",7),("?: -1 4 9",9),("abs -7",7),("at2 0 1",5_400_000),("cat2 10 3 4",6),("sat2 10 3 4",8),("cos 10 cd2",-10),("sin 10 cd4",10),("tan 10 cd8",10),("max 2 3",3),("min 2 3",2),("mod 3 4 12",13),("pin 0 15 10",10),("sqrt 81",9),("val wd2",100)]
    let geometry = CustomGeometry(paths: [.init(commands: [.move(.init(x:"10",y:"0")), .arc(widthRadius:"10",heightRadius:"20",startAngle:"0",sweepAngle:"2700000"), .close])], guides: formulas.enumerated().map { .init(name:"g\($0.offset)",formula:$0.element.0) }, adjustments:[.init(name:"adjust",formula:"val 5")])
    let result = try GeometryEvaluator.evaluate(geometry,width:200,height:100,adjustments:["adjust":9])
    for (i, expected) in formulas.enumerated() { #expect(abs(try #require(result.guides["g\(i)"]) - expected.1) < 1e-8) }
    #expect(result.adjustments["adjust"] == 9)
    guard case .arc(let arc) = result.paths[0].commands[1] else { Issue.record("arc不在"); return }
    #expect(abs(arc.center.x) < 1e-10 && abs(arc.center.y) < 1e-10)
    #expect(abs(arc.end.x - 200 / sqrt(500)) < 1e-10 && abs(arc.end.x - arc.end.y) < 1e-10)
    #expect(arc.sweepAngle == 45)
    for formula in ["val later", "*/ 1 1 0", "sqrt -1", "unknown 1"] {
        #expect(throws: SlideError.self) { try GeometryEvaluator.evaluate(CustomGeometry(guides:[.init(name:"a",formula:formula)]),width:100,height:100) }
    }
    #expect(throws: SlideError.self) { try GeometryEvaluator.evaluate(geometry,width:200,height:100,maxOperations:2) }
}

@Test func workbookNamesUnionIntersectionAndSharedFormula() throws {
    func sheet(_ name: String, _ values: [String:String]) -> WorkbookSheet { .init(name:name,cells:values.mapValues { $0 }.reduce(into: [:]) { $0[$1.key] = .init(address:$1.key,type:"n",value:$1.value) }) }
    let book = WorkbookData(sheets:[sheet("First",["A1":"1","A3":"3","B2":"20"]),sheet("Second",["A1":"9"]),sheet("Third",["A1":"10"])],definedNames:[.init(name:"Values",formula:"First!A1:A3"),.init(name:"Values",formula:"Second!A1",sheet:"Second"),.init(name:"Loop",formula:"Loop")])
    #expect(try book.resolve("vAlUeS").points.map(\.text) == ["1","3"])
    #expect(try book.resolve("Values",sheet:"Second").points.map(\.text) == ["9"])
    #expect(try book.resolve("(First!A1:A3,Second!A1)").points.map(\.index) == [0,2,3])
    #expect(try book.resolve("First!A1:B3 First!B2:C2").points == [.init(index:0,text:"20")])
    #expect(try book.resolve("First:Third!A1").points.map(\.text) == ["1","9","10"])
    #expect(throws: SlideError.self) { try book.resolve("Loop") }
    #expect(throws: SlideError.self) { try book.resolve("Missing!Values") }
    #expect(throws: SlideError.self) { try book.resolve("First!A:A",maxCells:50) }
    #expect(throws: SlideError.self) { try book.resolve("SUM(First!A1)") }
    let formula = #"A1+$B1+C$2+$D$3+"A1"+'A1 sheet'!A1+LOG10(A1)+Table1[Column1]"#
    #expect(try WorkbookFormulaResolver.translate(formula,from:"B2",to:"C4") == #"B3+$B3+D$2+$D$3+"A1"+'A1 sheet'!B3+LOG10(B3)+Table1[Column1]"#)
    #expect(try WorkbookFormulaResolver.translate("A1",from:"B2",to:"A1") == "#REF!")
    #expect(try WorkbookFormulaResolver.translate("\"😀\"+'架空😀'!A1",from:"A1",to:"B2") == "\"😀\"+'架空😀'!B2")
    #expect(try WorkbookFormulaResolver.translate("SUM(A:$C)+SUM(1:$3)+架空A1",from:"A1",to:"B2") == "SUM(B:$C)+SUM(2:$3)+架空A1")
    let source = ["B1":WorkbookCell(address:"B1",type:"n",value:"3",formula:"A1+$A$1",formulaAttributes:["t":"shared","si":"0","ref":"B1:B2"]),"B2":WorkbookCell(address:"B2",type:"n",value:"5",formula:"",formulaAttributes:["t":"shared","si":"0"])]
    let resolved = try WorkbookFormulaResolver.expandShared(source)
    #expect(resolved["B2"]?.formula == "" && resolved["B2"]?.resolvedFormula == "A2+$A$1")
    #expect(try JSONDecoder().decode(WorkbookData.self,from:JSONEncoder().encode(book)) == book)
}

@Test func model3DBuffersSparseSceneAndMaterial() throws {
    let bytes = Data([0,0,0,0,0,0,128,63,0,0,0,64, 1,0,0,0, 0,0,64,64])
    let json: [String:Any] = ["asset":["version":"2.0"],"buffers":[["byteLength":bytes.count,"uri":"data:application/octet-stream;base64,"+bytes.base64EncodedString()]],"bufferViews":[["buffer":0,"byteOffset":0,"byteLength":12],["buffer":0,"byteOffset":12,"byteLength":1],["buffer":0,"byteOffset":16,"byteLength":4]],"accessors":[["bufferView":0,"componentType":5126,"count":3,"type":"SCALAR","sparse":["count":1,"indices":["bufferView":1,"componentType":5121],"values":["bufferView":2]]]],"nodes":[["translation":[2,3,4],"scale":[2,2,2]]],"scenes":[["nodes":[0]]],"scene":0,"materials":[["pbrMetallicRoughness":["baseColorFactor":[0.5,0.6,0.7,1],"metallicFactor":0,"roughnessFactor":0.25],"alphaMode":"BLEND"]]]
    let model = try Model3DReader.read(JSONSerialization.data(withJSONObject:json))
    #expect(try model.values(forAccessor:0) == [[0],[3],[2]])
    #expect(Array(model.nodes[0].matrix[12...14]) == [2,3,4] && model.nodes[0].matrix[0] == 2)
    #expect(try model.materials[0].roughness == 0.25 && model.materials[0].alphaMode == "BLEND")
    #expect(throws:SlideError.self) { try model.values(forAccessor:0,maxComponents:2) }
    var invalid = json; invalid["nodes"] = [["children":[0]]]
    #expect(throws:SlideError.self) { try Model3DReader.read(JSONSerialization.data(withJSONObject:invalid)) }
    invalid = json; invalid["bufferViews"] = [["buffer":0,"byteOffset":21,"byteLength":1]]
    #expect(throws:SlideError.self) { try Model3DReader.read(JSONSerialization.data(withJSONObject:invalid)) }
    for (key,value): (String,Any) in [("nodes",[false]),("scenes",[["nodes":true]]),("materials",[["pbrMetallicRoughness":false]])] {
        invalid = json; invalid[key] = value
        #expect(throws:SlideError.self) { try Model3DReader.read(JSONSerialization.data(withJSONObject:invalid)) }
    }
    #expect(throws:SlideError.self) { try Model3DReader.read(JSONSerialization.data(withJSONObject:json),limits:.init(maxXMLNodes:4)) }
    // GLBの同じscene。JSON chunk長と全体宣言長は独立に作る。
    var minimal = Data(#"{"asset":{"version":"2.0"},"nodes":[{}],"scenes":[{"nodes":[0]}]}"#.utf8)
    while minimal.count % 4 != 0 { minimal.append(32) }
    func word(_ value: Int) -> Data { Data((0..<4).map { UInt8(truncatingIfNeeded:value >> ($0*8)) }) }
    var glb = Data([0x67,0x6c,0x54,0x46])+word(2)+word(20+minimal.count)+word(minimal.count)+word(0x4e4f534a)+minimal
    #expect(try Model3DReader.read(glb).scenes == [[0]])
    glb[8] ^= 1
    #expect(throws:SlideError.self) { try Model3DReader.read(glb) }
}

private func completionVarint(_ n: UInt64) -> Data { var n = n, b = Data(); while n >= 128 { b.append(UInt8(n & 127)|128); n >>= 7 }; b.append(UInt8(n)); return b }
private func completionWire(_ field: UInt32, _ n: UInt64) -> Data { completionVarint(UInt64(field)<<3)+completionVarint(n) }
private func completionWire(_ field: UInt32, _ bytes: Data) -> Data { completionVarint(UInt64(field)<<3|2)+completionVarint(UInt64(bytes.count))+bytes }

@Test func keynoteNestedReferencesSchemasAndInventory() throws {
    let uid = completionWire(1,UInt64(7))+completionWire(2,UInt64(9))
    let ref = completionWire(1,uid)+completionWire(2,uid)+completionWire(3,UInt64(1))
    let reference = completionWire(1,UInt64(48))+completionWire(30,ref)
    let nested = completionWire(1,UInt64(26))+completionWire(14,completionWire(1,reference))+completionWire(99,Data([0xff]))
    let formula = completionWire(1,completionWire(1,nested))+completionWire(7,uid)
    let source = try KeynoteSource(fixture("native-synthetic.keynote.zip"),options:.init())
    let parsed = try source.nativeFormula(formula,row:0,column:0)
    #expect(parsed.tokens[0].details?.children.count == 1)
    #expect(parsed.tokens[0].details?.children[0].details?.properties["uidCoordinate"]?["column"]?["lower"] == .unsigned(7))
    #expect(parsed.context?["tableUID"]?["upper"] == .unsigned(9))
    #expect(parsed.tokens[0].details?.properties["field:99"] != nil)
    #expect(try JSONDecoder().decode(CellFormula.self,from:JSONEncoder().encode(parsed)) == parsed)
    #expect(throws:SlideError.self) { try KeynoteSchemaReader.read(formula,schema:"formula",registry:KeynoteSchemaReader.formulaSchemas,limits:.init(maxXMLDepth:2)) }
    let p = try Presentation(data:fixture("native-synthetic.keynote.zip")), graph = try CodecSet.all.inspectPreservation(p)
    #expect(graph.references.contains { $0.kind == .nativeObject && $0.value == "10" })
    #expect(!graph.unresolvedScopes.isEmpty && graph.identities.count == 2)
    var count = 0
    let raw = try IWAFraming.iwa(PackageArchive(fixture("native-synthetic.keynote.zip")).read("Index/Document.iwa"),limit:1<<20)
    let locations = try Wire.locations(raw,part:"test",limits:.init(),fieldCount:&count)
    count = 0; let objects = try Wire.objects(raw,part:"test",limits:.init(),fieldCount:&count)
    #expect(locations.map(\.id) == objects.map(\.id))
    #expect(zip(locations,objects).allSatisfy { raw.subdata(in:$0.range) == $1.rawData })
}

@Test func indexedParallelAndDirectoryReading() async throws {
    for name in ["styles.odp","native-advanced.keynote.zip","stored.pptx"] {
        let data = try fixture(name), reference = try Presentation(data:data)
        var options = ReadOptions(); options.indexedCacheBytes = 0
        let reader = try SlideReader(data:data,codecs:.all,options:options), ids = reader.slideDescriptors.map(\.id).reversed()
        let results = try await reader.readSlides(selection:.ids(Array(ids)),maxConcurrentReads:2)
        #expect(results.map(\.slide) == reference.slides.reversed())
        await #expect(throws:SlideError.self) { try await reader.readSlides(maxConcurrentReads:0) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:url) }
        try data.write(to:url)
        let bounded = try SlideReader(fileBackedURL:url,codecs:.all,cacheBudget:.init(totalBytes:2048))
        let selected = try await bounded.readSlides(maxConcurrentReads:2)
        #expect(selected.map(\.slide) == reference.slides)
        #expect(try #require(bounded.cacheStatistics).peakRetainedBytes <= 2048)
    }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".key")
    defer { try? FileManager.default.removeItem(at:folder) }
    let archive = try PackageArchive(fixture("native-synthetic.keynote.zip"))
    for path in archive.paths where !path.hasSuffix("/") { let url = folder.appendingPathComponent(path); try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true); try archive.read(path).write(to:url) }
    let reader = try SlideReader(fileBackedURL:folder,codecs:.all,cacheBytes:0)
    #expect(try await reader.readSlides(maxConcurrentReads:2).count == 2)
    try Data("changed".utf8).write(to:folder.appendingPathComponent("Data/fixture.png"))
    await #expect(throws:SlideError.self) { try await reader.slide(id:"20") }
    try FileManager.default.createSymbolicLink(at:folder.appendingPathComponent("linked.iwa"),withDestinationURL:folder.appendingPathComponent("Index/Document.iwa"))
    #expect(throws:SlideError.self) { try SlideReader(fileBackedURL:folder,codecs:.all) }
}

@Test func xmlSubtreeIndexPreservesNamespacesCDATAAndBudget() throws {
    let xml = Data("<doc xmlns:x=\"urn:test\"><x:page a=\">\"><!-- <x:page/> --><![CDATA[<x:page/>]]><b/></x:page><x:page/></doc>".utf8)
    let tree = try MarkupNode.parse(xml,part:"test",limits:.init(),pruning:["urn:test|page"])
    #expect(tree.children.count == 2 && tree.children[0].children.isEmpty)
    let selected = Set(tree.children.compactMap(\.sourceElementIndex)), ranges = try XMLSubtreeIndex.ranges(xml,selected:selected)
    #expect(ranges.count == 2)
    #expect(String(decoding:xml.subdata(in:try #require(ranges[2])),as:UTF8.self).contains("<![CDATA["))
    #expect(throws:SlideError.self) { try MarkupNode.parse(xml,part:"test",limits:.init(maxXMLDepth:2),pruning:["urn:test|page"]) }
    let cache = ReadingDataCache(limit:8); cache.insert(Data(repeating:1,count:5),for:"a"); cache.insert(Data(repeating:2,count:4),for:"b")
    #expect(cache.value(for:"a") == nil && cache.value(for:"b")?.count == 4)
    #expect(cache.statistics.retainedBytes == 4 && cache.statistics.peakRetainedBytes == 5)
    let utf16 = Data([0xff,0xfe]) + (try #require(String(data:xml,encoding:.utf8))).data(using:.utf16LittleEndian)!
    #expect(try XMLSubtreeIndex.utf8(utf16) == xml)
}

@Test func flatODPAndDifferentPageSizes() throws {
    let data = try fixture("completion-flat.fodp"), p = try Presentation(data:data)
    #expect(try p.asset(at:"flat.xml") == data)
    #expect(try PresentationFormat.detect(data) == .odp)
    #expect(p.size == .init(width:100,height:80) && p.slides[0].sizeOverride == nil)
    #expect(p.slides[1].sizeOverride == .init(width:200,height:150) && p.slides[0].plainText == "Fictional")
    #expect(try JSONDecoder().decode(Slide.self,from:JSONEncoder().encode(p.slides[1])) == p.slides[1])
    #expect(throws:SlideError.self) { try p.write().data }
}

@Test func textAppearanceExplicitClearOverridesInheritedValues() throws {
    var base = TextStyle(underline:true); base.appearance = .init(spacing:2,underlineStyle:"wavy",outline:.init(color:.rgb("000000"),width:1))
    var direct = TextStyle(underline:false); direct.appearance = .init(outlineIsNone:true)
    let merged = base.overlaying(direct)
    #expect(merged.appearance?.spacing == 2 && merged.appearance?.underlineStyle == "none")
    #expect(merged.appearance?.outline == nil && merged.appearance?.outlineIsNone == true)
    base.appearance = .init(fill:.gradient(.init(stops:[.init(position:0,color:.rgb("111111"))])))
    #expect(base.overlaying(.init(color:.rgb("FF0000"))).appearance?.fill == .solid(.rgb("FF0000")))
    let shape = try Shape3D(extrusionHeight:3,source:SourceXMLNode(MarkupNode(name:"sp3d",namespace:NS.a,qualifiedName:"a:sp3d")))
    #expect(TextAppearance(shape3D:shape).overlaying(.init(flatTextDepth:0)).shape3D == nil)
    #expect(TextAppearance(flatTextDepth:0).overlaying(.init(shape3D:shape)).flatTextDepth == nil)
}

@Test func spatialTransformsAndAnalyticGeometry() throws {
    let matrix = try ODPTransformReader.read3D("scale(2 3 4) rotatez(90) translate(5 6 7)")
    let p = matrix.applying(to:.init(x:1,y:1,z:1))
    #expect(abs(p.x-2) < 1e-9 && abs(p.y-8) < 1e-9 && abs(p.z-11) < 1e-9)
    let source = try SourceXMLNode(MarkupNode(name:"sphere",namespace:"test",qualifiedName:"sphere"))
    let sphere = SpatialGeometry(kind:.sphere,vectors:["center":.init(x:0,y:0,z:0),"size":.init(x:2,y:4,z:6)],matrix:matrix.values,source:source)
    let evaluated = try sphere.evaluated()
    #expect(evaluated.ellipsoidCenter == .init(x:5,y:6,z:7))
    #expect(abs(try #require(evaluated.ellipsoidAxes)[2].z-12) < 1e-9)
    let path = try VectorPath.readSVG("M 0 0 L 1 2 C 1 2 3 4 5 6 A 2 3 45 1 0 8 9 Z")
    #expect(path.commands.map(\.name) == ["M","L","C","A","Z"])
    #expect(try VectorPath.readSVG("M0 0A2 3 45 018 9").commands[1].values == [2,3,45,0,1,8,9])
    #expect(throws:SlideError.self) { try VectorPath.readSVG("M 0 0 A 1 1 0 2 0 3 4") }
    #expect(throws:SlideError.self) { try ODPTransformReader.read3D("matrix(1 2)") }
    #expect(throws:(any Error).self) { try JSONDecoder().decode(AffineTransform3D.self,from:Data(#"{"values":[1]}"#.utf8)) }
}

@Test func chart3DAndAxisDetails() throws {
    let data = try changedFixture("advanced-reading.pptx") { parts in
        let path = "ppt/charts/chart1.xml", ns = "http://schemas.openxmlformats.org/drawingml/2006/chart"
        let root = try MarkupNode.parse(#require(parts[path]),part:path,limits:.init()), chart = try #require(root.child("chart",ns:ns))
        chart.content.insert(.node(try MarkupNode.parse(Data("<c:view3D xmlns:c=\"\(ns)\"><c:rotX val=\"30\"/><c:rotY val=\"45\"/><c:depthPercent val=\"125\"/><c:rAngAx val=\"1\"/></c:view3D>".utf8),part:path,limits:.init())),at:0)
        chart.content.append(.node(try MarkupNode.parse(Data("<c:floor xmlns:c=\"\(ns)\" xmlns:a=\"\(NS.a)\"><c:thickness val=\"2\"/><c:spPr><a:solidFill><a:srgbClr val=\"123456\"/></a:solidFill></c:spPr></c:floor>".utf8),part:path,limits:.init())))
        if let axis = chart.descendants("valAx",ns:ns).first {
            for (name,value) in [("majorUnit","10"),("minorUnit","2"),("crossesAt","3")] { axis.content.append(.node(MarkupNode(name:name,namespace:ns,qualifiedName:"c:"+name,attributes:["val":value]))) }
        }
        parts[path] = Data(root.xml.utf8)
    }
    let p = try Presentation(data:data), chart = try #require(p.slides.flatMap(\.elements).compactMap(\.chart).first)
    #expect(chart.view3D?.rotationX == 30 && chart.view3D?.depth == 1.25)
    #expect(chart.surfaces?.first?.fill == .solid(.rgb("123456")))
    #expect(chart.axes.first { $0.kind == "valAx" }?.scale?.minorUnit == 2)
    #expect(try JSONDecoder().decode(Chart.self,from:JSONEncoder().encode(chart)) == chart)
}

@Test func customODPEngineRequiresExplicitProvider() throws {
    let draw = "urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
    let data = try changedFixture("semantic-reading.odp") { parts in
        let root = try MarkupNode.parse(#require(parts["content.xml"]),part:"content.xml",limits:.init()), shape = try #require(root.descendants("custom-shape",ns:draw).first)
        shape.attributes[draw+"|engine"] = "fictional.engine"; shape.attributeNames[draw+"|engine"] = "draw:engine"
        parts["content.xml"] = Data(root.xml.utf8)
    }
    let opaque = try Presentation(data:data)
    #expect(opaque.slides[0].elements.first { $0.geometryEngine == "fictional.engine" }?.kind == .opaque)
    var options = ReadOptions()
    options.geometryProvider = { request in
        #expect(request.engine == "fictional.engine")
        return .init(viewBox:.init(x:0,y:0,width:12,height:13),source:request.source)
    }
    let parsed = try Presentation(data:data,options:options)
    #expect(parsed.slides[0].elements.first { $0.geometryEngine == "fictional.engine" }?.enhancedGeometry?.viewBox?.width == 12)
}

@Test func contentMathMLBindingsAndNumericComponents() throws {
    let data = try changedFixture("semantic-reading.odp") { parts in
        let archive = try PackageArchive(fixture("semantic-reading.odp"))
        let path = try #require(archive.paths.first { $0 != "content.xml" && $0.hasSuffix("content.xml") })
        parts[path] = Data("<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><apply><plus/><cn type=\"rational\">1<sep/>2</cn><bind><csymbol cd=\"fns1\">lambda</csymbol><bvar><ci>x</ci></bvar><apply><times/><ci>x</ci><cn>2</cn></apply></bind></apply></math>".utf8)
    }
    let p = try Presentation(data:data)
    let equation = try #require(p.slides.flatMap(\.elements).compactMap(\.equation).first { $0.root.children.first?.kind == .application })
    let apply = equation.root.children[0]
    #expect(apply.appliedOperator?.kind == .contentOperator && apply.appliedOperator?.name == "plus")
    #expect(apply.children[1].tokenParts == ["1","2"])
    #expect(apply.children[2].kind == .binding && apply.children[2].boundVariables.count == 1)
    #expect(apply.children[2].appliedOperator?.attributes["cd"] == "fns1")
}

@Test func odfTransformOrderAnglesAndTextPath() throws {
    let t = try ODPTransformReader.read("scale(2 3) rotate(90) translate(10pt 20pt)",angleUnit:.degrees)
    let point = t.matrix.applying(to:.init(x:1,y:2))
    #expect(abs(point.x-4) < 1e-10 && abs(point.y-22) < 1e-10)
    #expect(try ODPTransformReader.read("rotate(100grad)").matrix.b == 1)
    #expect(throws:SlideError.self) { try ODPTransformReader.read("rotate(NaN)") }
    let data = try changedFixture("semantic-reading.odp") { parts in
        let path = "content.xml", root = try MarkupNode.parse(#require(parts[path]),part:path,limits:.init())
        let shape = try #require(root.descendants("custom-shape",ns:"urn:oasis:names:tc:opendocument:xmlns:drawing:1.0").first)
        shape.set("urn:oasis:names:tc:opendocument:xmlns:drawing:1.0|transform","translate(3pt 4pt)"); shape.attributeNames["urn:oasis:names:tc:opendocument:xmlns:drawing:1.0|transform"] = "draw:transform"
        let geometry = try #require(shape.child("enhanced-geometry",ns:"urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"))
        geometry.set("urn:oasis:names:tc:opendocument:xmlns:drawing:1.0|text-path","true"); geometry.attributeNames["urn:oasis:names:tc:opendocument:xmlns:drawing:1.0|text-path"] = "draw:text-path"
        geometry.set("urn:oasis:names:tc:opendocument:xmlns:drawing:1.0|text-path-mode","path"); geometry.attributeNames["urn:oasis:names:tc:opendocument:xmlns:drawing:1.0|text-path-mode"] = "draw:text-path-mode"
        parts[path] = Data(root.xml.utf8)
    }
    let p = try Presentation(data:data), shape = try #require(p.slides[0].elements.first { $0.enhancedGeometry != nil })
    #expect(shape.transform2D?.matrix.tx == 3 && shape.transform2D?.matrix.ty == 4)
    #expect(shape.textPath?.enabled == true && shape.textPath?.mode == "path")
}

@Test func keynoteEditableBezierAndParameterizedGeometry() throws {
    func float(_ field: UInt32, _ value: Float) -> Data { completionVarint(UInt64(field)<<3|5) + Data((0..<4).map { UInt8(truncatingIfNeeded:value.bitPattern >> ($0*8)) }) }
    func point(_ x: Float, _ y: Float) -> Data { float(1,x)+float(2,y) }
    func node(_ x: Float) -> Data { completionWire(1,point(x-1,0))+completionWire(2,point(x,0))+completionWire(3,point(x+1,0))+completionWire(4,UInt64(2)) }
    let subpath = completionWire(1,node(0))+completionWire(1,node(10))+completionWire(2,UInt64(1))
    let raw = completionWire(8,completionWire(1,subpath)+completionWire(2,point(20,10)))
    let source = try KeynoteSource(fixture("native-synthetic.keynote.zip"),options:.init())
    let parsed = try source.nativeGeometry(Wire.fields(raw,limit:100))
    let geometry = try #require(parsed)
    let result = try GeometryEvaluator.evaluate(geometry,width:20,height:10)
    #expect(result.paths[0].commands.count == 4)
    guard case .cubic(let a,let b,let end) = result.paths[0].commands[1] else { Issue.record("cubic不在"); return }
    #expect(a.x == 1 && b.x == 9 && end.x == 10)
    let native = try source.parameterizedGeometry(Wire.fields(completionWire(4,completionWire(1,UInt64(0))+float(2,0.25)),limit:100))
    #expect(native.kind == "roundedRectangle" && native.properties["scalarPath"]?["scalar"] == .number(0.25))
}

@Test func odpChartInheritedAxesAndSurfaceAppearance() throws {
    let data = try changedFixture("styles.odp") { parts in
        let root = try MarkupNode.parse(#require(parts["content.xml"]),part:"content.xml",limits:.init())
        let page = try #require(root.descendants("page",ns:"urn:oasis:names:tc:opendocument:xmlns:drawing:1.0").first)
        page.content.append(.node(try MarkupNode.parse(Data(#"<draw:frame xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" xmlns:xlink="http://www.w3.org/1999/xlink"><draw:object xlink:href="./CompletionChart"/></draw:frame>"#.utf8),part:"content.xml",limits:.init())))
        parts["content.xml"] = Data(root.xml.utf8)
        parts["CompletionChart/content.xml"] = Data(##"<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:chart="urn:oasis:names:tc:opendocument:xmlns:chart:1.0" xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"><office:automatic-styles><style:style style:name="axis" style:family="chart" style:parent-style-name="base"><style:chart-properties chart:maximum="100" chart:reverse-direction="true"/></style:style><style:style style:name="plot" style:family="chart"><style:chart-properties chart:stacked="true"/></style:style><style:style style:name="surface" style:family="chart"><style:graphic-properties draw:fill="solid" draw:fill-color="#123456"/></style:style></office:automatic-styles><office:body><office:chart><chart:chart chart:class="chart:bar"><chart:plot-area chart:style-name="plot"><chart:axis chart:dimension="y" chart:style-name="axis"/><chart:series chart:style-name="surface"/><chart:floor chart:style-name="surface"/></chart:plot-area></chart:chart></office:chart></office:body></office:document-content>"##.utf8)
        parts["CompletionChart/styles.xml"] = Data(#"<office:document-styles xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" xmlns:chart="urn:oasis:names:tc:opendocument:xmlns:chart:1.0"><office:styles><style:style style:name="base" style:family="chart"><style:chart-properties chart:minimum="0" chart:interval-major="20" chart:interval-minor-divisor="4"/></style:style></office:styles></office:document-styles>"#.utf8)
    }
    let p = try Presentation(data:data), chart = try #require(p.slides[0].elements.last?.chart)
    #expect(chart.axes[0].minimum == 0 && chart.axes[0].maximum == 100)
    #expect(chart.axes[0].scale?.minorUnit == 5 && chart.axes[0].scale?.reversed == true)
    #expect(chart.groups[0].grouping == "stacked" && chart.groups[0].series[0].fill == .solid(.rgb("123456")))
    #expect(chart.surfaces?.first?.fill == .solid(.rgb("123456")))
}
