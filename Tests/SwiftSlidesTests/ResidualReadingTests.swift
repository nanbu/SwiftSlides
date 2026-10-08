import Foundation
import Testing
@testable import SlideCore
@testable import SlideDecrypt
import SwiftSlides

@Test(arguments:[128,192,256]) func agilePasswordsAndIntegrity(_ bits:Int) throws {
    let cipher=try fixture("encrypted-agile-\(bits).pptx"),plain=try fixture("stored.pptx")
    #expect(try decrypt(cipher,password:"fictional-鍵") == plain)
    #expect(throws:SlideError.wrongPassword) { try decrypt(cipher,password:"wrong") }
    let p=try Presentation(data:cipher,password:"fictional-鍵")
    #expect(p.slides.count == 2 && p.readWarnings.contains { $0.feature == "SEC-001" })
    #expect(try p.write().data == plain)
    #expect(throws:SlideError.self) { try decrypt(cipher,password:"fictional-鍵",limits:.init(maxPartBytes:100)) }
    #expect(throws:SlideError.self) { try decrypt(cipher,password:"fictional-鍵",limits:.init(maxEntries:1)) }
    #expect(try decrypt(cipher,password:"fictional-鍵",limits:.init(maxEntries:3)) == plain)
    var damaged=cipher
    // 最初のregular EncryptedPackage sectorはmini streamの後。
    let sector=bits == 192 ? 4096 : 512
    let file=try CompoundFile(data:cipher,limits:.init())
    let package=try file.stream("EncryptedPackage")
    let range=try #require(cipher.range(of:package.prefix(32)))
    damaged[range.lowerBound+16] ^= 1
    #expect(throws:SlideError.self) { try decrypt(damaged,password:"fictional-鍵") }
    #expect(cipher.count % sector == 0)
}

@Test(arguments:[128,256]) func odpPasswordsAndPlaintextSnapshot(_ bits:Int) throws {
    let encrypted=try fixture("encrypted-aes-\(bits).odp")
    let p=try Presentation(data:encrypted,password:"fictional-鍵")
    let expected=try Presentation(data:fixture("styles.odp"))
    #expect(p.slides == expected.slides)
    #expect(p.readWarnings.contains { $0.feature == "SEC-001" })
    #expect(throws:SlideError.wrongPassword) { try decrypt(encrypted,password:"incorrect") }
    let plain=try decrypt(encrypted,password:"fictional-鍵")
    #expect(try parts(plain)["content.xml"] == parts(fixture("styles.odp"))["content.xml"])
    #expect(!String(decoding:try #require(parts(plain)["META-INF/manifest.xml"]),as:UTF8.self).contains("encryption-data"))
    let invalid=try changedFixture("encrypted-aes-\(bits).odp") { parts in
        parts["META-INF/manifest.xml"]=Data(String(decoding:parts["META-INF/manifest.xml"]!,as:UTF8.self).replacingOccurrences(of:"iteration-count=\"1000\"",with:"iteration-count=\"NaN\"").utf8)
    }
    #expect(throws:SlideError.self) { try decrypt(invalid,password:"fictional-鍵") }
}

@Test func nativeKeynoteOrderUnknownsAndAssets() throws {
    let data=try fixture("native-synthetic.keynote.zip")
    #expect(try PresentationFormat.detect(data) == .keynote)
    let p=try Presentation(data:data)
    #expect(p.sourceFormat == .keynote && p.size == .init(width:960,height:540))
    #expect(p.slides.map(\.id) == ["20","21"] && p.slides[1].isHidden == true)
    #expect(p.slides[0].elements.map(\.nativeObjectID) == [30,31,32])
    #expect(p.slides[0].elements[0].frame == .init(x:12,y:24,width:200,height:80))
    #expect(p.slides[0].elements[0].text?.plainText == "Fictional title\nSecond line")
    #expect(abs(p.slides[0].elements[0].rotation-0.5*180 / .pi) < 0.0001)
    #expect(p.slides[0].notes?.plainText == "Fictional notes")
    #expect(p.slides[0].elements[1].image?.path == "Data/fixture.png")
    #expect(try p.asset(at:"Data/fixture.png") == fixture("fixture.png"))
    #expect(p.slides[0].elements[2].kind == .opaque)
    let inventory=try p.readKeynoteObjects(),unknown=try #require(inventory.objects.first { $0.id == 32 })
    #expect(unknown.type == 9999 && unknown.fields[0].number == 99)
    #expect(unknown.fields[0].bytes == Data([0,255])+Data("Fictional unknown".utf8))
    #expect(inventory.objects.first { $0.id == 2 }?.objectReferences == [10,11])
    let reader=try SlideReader(data:data)
    #expect(try reader.slide(id:"20").slide == p.slides[0])
    #expect(throws:SlideError.self) { try p.write().data }
    #expect(try Presentation(data:data,options:.init(includesNotes:false)).slides[0].notes == nil)
}

@Test func keynoteNestedDirectoryAndMalformedWire() throws {
    let source=try parts(fixture("native-synthetic.keynote.zip"))
    let nested=try ZIPWriter.write(["Document.iwa":source["Index/Document.iwa"]!],compress:false)
    let data=try ZIPWriter.write(["Index.zip":nested,"Data/fixture.png":source["Data/fixture.png"]!],compress:false)
    #expect(try Presentation(data:data).slides.count == 2)
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".key")
    try FileManager.default.createDirectory(at:directory.appendingPathComponent("Index"),withIntermediateDirectories:true)
    try FileManager.default.createDirectory(at:directory.appendingPathComponent("Data"),withIntermediateDirectories:true)
    defer { try? FileManager.default.removeItem(at:directory) }
    for (path,bytes) in source { try bytes.write(to:directory.appendingPathComponent(path)) }
    #expect(try Presentation(contentsOf:directory).slides.count == 2)
    try FileManager.default.createSymbolicLink(at:directory.appendingPathComponent("unsafe"),withDestinationURL:directory.appendingPathComponent("Data/fixture.png"))
    #expect(throws:SlideError.self) { try Presentation(contentsOf:directory) }
    #expect(throws:SlideError.self) { try Presentation(data:fixture("native-synthetic.keynote.zip"),options:.init(limits:.init(maxXMLNodes:10))) }
    // Snappy overlapping copy: abc -> abcabcabc; bounds and truncated varints.
    #expect(try IWAFraming.snappy([9,8,97,98,99,22,3,0],limit:10) == Array("abcabcabc".utf8))
    for bad:[UInt8] in [[3,2,0,0],[1,240],[255],[1,0,65,0,66]] {
        #expect(throws:SlideError.self) { try IWAFraming.snappy(bad,limit:100) }
    }
    #expect(throws:SlideError.self) { try IWAFraming.isKeynote(Data([0,4,0,0,1,0,255,0]),limit:100) }
}

@Test func sourceXMLRetainsNamespacesAndMixedOrder() throws {
    let data=try changedFixture { $0["fictional.xml"]=Data("<x:r xmlns:x=\"urn:fictional\" xmlns=\"urn:default\" x:flag=\"keep\" kind=\"x:Outer\">before<x:c xmlns:x=\"urn:inner\" kind=\"x:Inner\"/>after</x:r>".utf8) }
    let p=try Presentation(data:data),read=try p.readSourceXML(at:"fictional.xml")
    #expect(read.root.namespace == "urn:fictional" && read.root.attributes["urn:fictional|flag"] == "keep")
    #expect(read.root.content.count == 3 && read.root.text == "beforeafter")
    #expect(read.root.qualifiedName == "x:r" && read.root.attributeNames["urn:fictional|flag"] == "x:flag")
    #expect(read.root.namespaceBindings["x"] == "urn:fictional" && read.root.namespaceBindings[""] == "urn:default")
    #expect(read.root.children[0].namespaceBindings["x"] == "urn:inner")
    #expect(read.root.children[0].attributes["kind"] == "x:Inner" && read.root.namespaceBindings["xml"] == "http://www.w3.org/XML/1998/namespace")
    #expect(try JSONDecoder().decode(SourceXMLNode.self,from:JSONEncoder().encode(read.root)) == read.root)
    #expect(!read.diagnostics.isEmpty)
    #expect(throws:SlideError.self) { try p.readSourceXML(at:"ppt/media/image1.png") }
    #expect(p.slides[0].elements[0].sourceProperties?.name == "sp")
}

@Test func passwordAsyncAPIsAndCancellation() async throws {
    let data=try fixture("encrypted-agile-256.pptx")
    let result=try await Presentation.read(data,password:"fictional-鍵")
    #expect(result.presentation.slides.count == 2)
    #expect(try await Presentation.inspect(data,password:"fictional-鍵").slideCount == 2)
    let reader=try await CodecSet.all.slideReader(data,password:"fictional-鍵")
    #expect(reader.slideDescriptors.count == 2)
    let task=Task { try await decrypt(data,password:"fictional-鍵") }
    task.cancel()
    await #expect(throws:CancellationError.self) { try await task.value }
}

@Test(arguments:[128,192,256]) func standardPasswordsAndHeaderValidation(_ bits:Int) throws {
    let encrypted=try fixture("encrypted-standard-\(bits).pptx")
    #expect(try decrypt(encrypted,password:"fictional-鍵") == fixture("stored.pptx"))
    #expect(throws:SlideError.wrongPassword) { try decrypt(encrypted,password:"wrong") }
    let info=try CompoundFile(data:encrypted,limits:.init()).stream("EncryptionInfo")
    let range=try #require(encrypted.range(of:info.prefix(16)))
    var broken=encrypted;broken[range.lowerBound+8]=0
    #expect(throws:SlideError.self) { try decrypt(broken,password:"fictional-鍵") }
}

@Test func keynotePasswordVerifierPaddingAndUnknownProtection() throws {
    let cipher=try fixture("encrypted-native.keynote.zip")
    #expect(throws:SlideError.unsupportedEncryption(detail: "Keynote .iwpv2保護")) { try PresentationFormat.detect(cipher) }
    #expect(throws:SlideError.wrongPassword) { try decrypt(cipher,password:"wrong") }
    let p=try Presentation(data:cipher,password:"fictional-鍵")
    let expected=try Presentation(data:fixture("native-synthetic.keynote.zip"))
    #expect(p.slides == expected.slides)
    #expect(p.readWarnings.contains { $0.message.contains("末尾20bytes") })
    let bad=try changedFixture("encrypted-native.keynote.zip") { parts in
        parts[".iwpv2"]![0]=3
    }
    #expect(throws:SlideError.self) { try decrypt(bad,password:"fictional-鍵") }
    let badPadding=try changedFixture("encrypted-native.keynote.zip") { parts in
        parts["Index/Document.iwa"]![40] ^= 1
    }
    #expect(throws:SlideError.self) { try Presentation(data:badPadding,password:"fictional-鍵") }
}

@Test func placeholderAndThemeStyleResolutionHasProvenance() throws {
    let data=try changedFixture("reading-models.pptx") { parts in
        let path="ppt/slides/slide1.xml",root=try MarkupNode.parse(parts[path]!,part:path,limits:.init())
        let sp=try #require(root.descendants("sp").first)
        let nv=try #require(sp.child("nvSpPr")?.child("nvPr"))
        nv.remove(["ph"])
        nv.content.append(.node(try MarkupNode.fragment("<p:ph type=\"body\" idx=\"7\"/>")))
        sp.child("spPr")?.remove(["xfrm","solidFill","gradFill","pattFill","blipFill","noFill","ln","effectLst","prstGeom","custGeom"])
        sp.remove(["style"])
        sp.content.append(.node(try MarkupNode.fragment("<p:style><a:fillRef idx=\"1\"><a:schemeClr val=\"accent1\"/></a:fillRef><a:lnRef idx=\"1\"><a:srgbClr val=\"ABCDEF\"/></a:lnRef><a:fontRef idx=\"minor\"><a:schemeClr val=\"tx1\"/></a:fontRef></p:style>")))
        sp.replace("txBody",with:try MarkupNode.fragment("<p:txBody><a:bodyPr/><a:lstStyle><a:lvl1pPr><a:defRPr sz=\"2000\" b=\"0\"><a:latin typeface=\"+mn-lt\"/></a:defRPr></a:lvl1pPr></a:lstStyle><a:p><a:pPr algn=\"r\"/><a:r><a:t>Fictional inherited text</a:t></a:r></a:p></p:txBody>"))
        parts[path]=Data(root.xml.utf8)
        for (path,master) in [("ppt/slideLayouts/slideLayout1.xml",false),("ppt/slideMasters/slideMaster1.xml",true)] {
            let root=try MarkupNode.parse(try #require(parts[path]),part:path,limits:.init()),sp=try #require(root.descendants("sp").first)
            let nv=try #require(sp.child("nvSpPr")?.child("nvPr"));nv.remove(["ph"]);nv.content.append(.node(try MarkupNode.fragment("<p:ph type=\"body\" idx=\"7\"/>")))
            if !master {
                sp.child("spPr")?.replace("xfrm",with:try MarkupNode.fragment("<a:xfrm rot=\"5400000\" flipH=\"1\"><a:off x=\"127000\" y=\"254000\"/><a:ext cx=\"1270000\" cy=\"635000\"/></a:xfrm>"))
                sp.child("spPr")?.remove(["prstGeom","custGeom","effectLst","effectDag"])
                sp.child("spPr")?.content.append(.node(try MarkupNode.fragment("<a:custGeom><a:pathLst><a:path w=\"100\" h=\"100\"><a:moveTo><a:pt x=\"0\" y=\"0\"/></a:moveTo><a:lnTo><a:pt x=\"100\" y=\"100\"/></a:lnTo></a:path></a:pathLst></a:custGeom>")))
                sp.remove(["style"])
                sp.content.append(.node(try MarkupNode.fragment("<p:style><a:effectRef idx=\"1\"><a:srgbClr val=\"114477\"/></a:effectRef></p:style>")))
            }
            // 他のbody placeholderを除き照合を一意にする。
            for other in root.descendants("sp").dropFirst() { other.child("nvSpPr")?.child("nvPr")?.remove(["ph"]) }
            parts[path]=Data(root.xml.utf8)
        }
        let themePath="ppt/theme/theme1.xml",theme=try MarkupNode.parse(parts[themePath]!,part:themePath,limits:.init())
        theme.child("themeElements")?.child("fmtScheme")?.replace("fillStyleLst",with:try MarkupNode.fragment("<a:fillStyleLst><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:fillStyleLst>"))
        theme.child("themeElements")?.child("fmtScheme")?.replace("lnStyleLst",with:try MarkupNode.fragment("<a:lnStyleLst><a:ln w=\"25400\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:ln></a:lnStyleLst>"))
        theme.child("themeElements")?.child("fmtScheme")?.replace("effectStyleLst",with:try MarkupNode.fragment("<a:effectStyleLst><a:effectStyle><a:effectLst><a:outerShdw dist=\"38100\" dir=\"5400000\"><a:schemeClr val=\"phClr\"/></a:outerShdw></a:effectLst></a:effectStyle></a:effectStyleLst>"))
        parts[themePath]=Data(theme.xml.utf8)
    }
    let p=try Presentation(data:data),slide=p.slides[0],element=slide.elements[0]
    let read=try p.resolveElement(slideID:slide.id,elementID:element.id)
    #expect(element.frame == nil)
    #expect(read.element.frame == .init(x:10,y:20,width:100,height:50))
    #expect(read.origins["frame"]?.kind == .layout)
    #expect(read.element.rotation == 90 && read.element.isFlippedHorizontally && !read.element.isFlippedVertically)
    #expect(read.element.fill == .solid(.theme("accent1")))
    #expect(read.origins["fill"]?.kind == .theme)
    #expect(read.element.stroke?.color == .rgb("ABCDEF") && read.element.stroke?.width == 2)
    #expect(read.element.geometry == nil && read.element.customGeometry?.paths.first?.commands.count == 2)
    #expect(read.element.effects?.direct == [.outerShadow(.init(distance:3,direction:90,color:.rgb("114477")))])
    #expect(read.origins["effects"]?.kind == .theme)
    #expect(read.element.text?.paragraphs[0].runs[0].style.font.size == 20)
    #expect(read.element.text?.paragraphs[0].runs[0].style.bold == false)
    #expect(read.element.text?.paragraphs[0].runs[0].style.font.family == read.theme?.bodyFont.family)
    #expect(read.element.text?.paragraphs[0].style.alignment == .right)
    #expect(read.colorMap["accent1"] == "accent2")
    #expect(try p.write().data == data)
    // 明示的な空の効果リストは継承した影を消す。
    var directParts=try parts(data)
    let path="ppt/slides/slide1.xml",root=try MarkupNode.parse(directParts[path]!,part:path,limits:.init())
    root.descendants("sp").first?.child("spPr")?.content.append(.node(try MarkupNode.fragment("<a:effectLst/>")))
    directParts[path]=Data(root.xml.utf8)
    let cleared=try Presentation(data:ZIPWriter.write(directParts,compress:false))
    let empty=try cleared.resolveElement(slideID:cleared.slides[0].id,elementID:cleared.slides[0].elements[0].id)
    #expect(empty.element.effects?.direct == [] && empty.origins["effects"]?.kind == .direct)
    // 解決不能な上位参照を継承元の値へ置き換えて成功扱いしない。
    let invalidShape=try #require(root.descendants("sp").first)
    invalidShape.child("spPr")?.remove(["effectLst"])
    invalidShape.replace("style",with:try MarkupNode.fragment("<p:style><a:fillRef idx=\"999\"/><a:lnRef idx=\"999\"/><a:effectRef idx=\"999\"/></p:style>"))
    directParts[path]=Data(root.xml.utf8)
    let invalid=try Presentation(data:ZIPWriter.write(directParts,compress:false))
    let unresolved=try invalid.resolveElement(slideID:invalid.slides[0].id,elementID:invalid.slides[0].elements[0].id)
    #expect(unresolved.element.fill == nil && unresolved.element.stroke == nil && unresolved.element.effects == nil)
    #expect(unresolved.origins["fill"] == nil && unresolved.origins["stroke"] == nil && unresolved.origins["effects"] == nil)
    #expect(unresolved.diagnostics.filter { $0.code == "styleUnresolved" && $0.message.contains("999") }.count == 3)
}

@Test func scatterBubbleAndMultilevelChartStructures() throws {
    let data=try changedFixture("reading-models.pptx") { parts in
        let path="ppt/charts/readingChart.xml",ns="http://schemas.openxmlformats.org/drawingml/2006/chart"
        let cache="<c:numLit><c:ptCount val=\"3\"/><c:pt idx=\"2\"><c:v>42</c:v></c:pt></c:numLit>"
        parts[path]=Data("<c:chartSpace xmlns:c=\"\(ns)\"><c:chart><c:plotArea><c:bubbleChart><c:ser><c:idx val=\"0\"/><c:order val=\"0\"/><c:xVal>\(cache)</c:xVal><c:yVal>\(cache)</c:yVal><c:bubbleSize>\(cache)</c:bubbleSize><c:cat><c:multiLvlStrRef><c:f>Sheet1!A1:B3</c:f><c:multiLvlStrCache><c:ptCount val=\"3\"/><c:lvl><c:pt idx=\"0\"><c:v>Outer</c:v></c:pt></c:lvl><c:lvl><c:pt idx=\"2\"><c:v>Inner</c:v></c:pt></c:lvl></c:multiLvlStrCache></c:multiLvlStrRef></c:cat><c:trendline><c:trendlineType val=\"linear\"/></c:trendline></c:ser></c:bubbleChart></c:plotArea></c:chart></c:chartSpace>".utf8)
    }
    let p=try Presentation(data:data),chart=try #require(p.slides[0].elements[1].chart),series=try #require(chart.groups.first?.series.first)
    #expect(chart.groups[0].kind == "bubbleChart")
    #expect(series.xValues?.points.map(\.index) == [2])
    #expect(series.yValues?.points[0].number == 42 && series.bubbleSizes?.pointCount == 3)
    #expect(series.categories?.levels?.map { $0.map(\.index) } == [[0],[2]])
    #expect(series.categories?.points == [])
    #expect(series.properties?.children.contains { $0.name == "trendline" } == true)
    #expect(try p.write().data == data)
}

@Test func odpTimingMediaAnnotationsAndCustomGeometryAreReadable() throws {
    let data=try changedFixture("styles.odp") { parts in
        let path="content.xml",root=try MarkupNode.parse(parts[path]!,part:path,limits:.init())
        let page=try #require(root.descendants("page",ns:"urn:oasis:names:tc:opendocument:xmlns:drawing:1.0").first)
        let xml="<wrapper xmlns:anim=\"urn:oasis:names:tc:opendocument:xmlns:animation:1.0\" xmlns:smil=\"urn:oasis:names:tc:opendocument:xmlns:smil-compatible:1.0\" xmlns:draw=\"urn:oasis:names:tc:opendocument:xmlns:drawing:1.0\" xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\" xmlns:xlink=\"http://www.w3.org/1999/xlink\"><anim:par smil:begin=\"rect-one.click\"><anim:animate smil:targetElement=\"rect-one\" smil:dur=\"2s\"/><anim:audio xlink:href=\"https://example.com/fictional.wav\"/></anim:par><office:annotation office:name=\"fictional-comment\"><dc:creator>Fictional Reviewer</dc:creator><dc:date>2026-01-01T00:00:00Z</dc:date><text:p>Fictional review</text:p></office:annotation><draw:custom-shape draw:id=\"custom\"><draw:enhanced-geometry draw:enhanced-path=\"M 0 0 L 10 10 Z\"/></draw:custom-shape></wrapper>"
        let extra=try MarkupNode.parse(Data(xml.utf8),part:path,limits:.init());page.content += extra.children.map { .node($0) };parts[path]=Data(root.xml.utf8)
    }
    let p=try Presentation(data:data),slide=p.slides[0]
    #expect(slide.timing?.targetElementIDs == ["rect-one"])
    #expect(slide.timing?.root.children.first?.attributes["urn:oasis:names:tc:opendocument:xmlns:smil-compatible:1.0|begin"] == "rect-one.click")
    #expect(slide.media?.first?.reference.externalTarget == "https://example.com/fictional.wav")
    #expect(slide.comments?.first?.text == "Fictional review" && slide.comments?.first?.authorName == "Fictional Reviewer")
    #expect(slide.elements.last?.sourceProperties?.children.first?.attributes["urn:oasis:names:tc:opendocument:xmlns:drawing:1.0|enhanced-path"] == "M 0 0 L 10 10 Z")
    #expect(slide.elements.last?.kind == .shape && slide.elements.last?.enhancedGeometry != nil)
}

@Test func modernCommentAuthorsRepliesAndTaskAnchors() throws {
    let namespace="http://schemas.microsoft.com/office/powerpoint/2018/8/main"
    let rel="http://schemas.microsoft.com/office/2018/10/relationships/"
    let data=try changedFixture { parts in
        for (path,id,type,target) in [("ppt/slides/_rels/slide1.xml.rels","fictional-comments","comments","../comments/fictional.xml"),("ppt/_rels/presentation.xml.rels","fictional-authors","authors","authors/fictional.xml")] {
            let root=try MarkupNode.parse(parts[path]!,part:path,limits:.init())
            root.content.append(.node(try MarkupNode.parse(Data("<Relationship xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\" Id=\"\(id)\" Type=\"\(rel+type)\" Target=\"\(target)\"/>".utf8),part:path,limits:.init())))
            parts[path]=Data(root.xml.utf8)
        }
        parts["ppt/authors/fictional.xml"]=Data("<m:authorLst xmlns:m=\"\(namespace)\"><m:author id=\"a1\" name=\"Fictional Reviewer\" initials=\"FR\" providerId=\"fictional\"/></m:authorLst>".utf8)
        parts["ppt/comments/fictional.xml"]=Data("<m:cmLst xmlns:m=\"\(namespace)\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><m:cm id=\"c1\" authorId=\"a1\" status=\"resolved\" created=\"2026-01-01T00:00:00Z\"><m:pos x=\"12700\" y=\"25400\"/><m:txBody><a:bodyPr/><a:p><a:r><a:rPr b=\"1\"/><a:t>Fictional review</a:t></a:r></a:p></m:txBody><m:spMkLst><m:spMk id=\"2\"/></m:spMkLst><m:task completed=\"1\"/><m:replyLst><m:reply id=\"r1\" authorId=\"a1\"><m:txBody><a:bodyPr/><a:p><a:r><a:t>Fictional reply</a:t></a:r></a:p></m:txBody></m:reply></m:replyLst></m:cm></m:cmLst>".utf8)
    }
    let p=try Presentation(data:data),thread=try #require(p.slides[0].commentThreads?.first)
    #expect(thread.authorName == "Fictional Reviewer" && thread.authorProperties?["providerId"] == "fictional")
    #expect(thread.x == 1 && thread.y == 2 && thread.status == "resolved")
    #expect(thread.text.paragraphs[0].runs[0].style.bold == true)
    #expect(thread.anchors.map(\.name) == ["spMkLst","task"])
    #expect(thread.replies.first?.text.plainText == "Fictional reply")
    #expect(try p.write().data == data)
    var edited=p;edited.slides[0].commentThreads=[]
    #expect(throws:SlideError.self) { try edited.write().data }
    var duplicateParts=try parts(data)
    duplicateParts["ppt/comments/fictional.xml"]=Data(String(decoding:duplicateParts["ppt/comments/fictional.xml"]!,as:UTF8.self).replacingOccurrences(of:"id=\"r1\"",with:"id=\"c1\"").utf8)
    #expect(throws:SlideError.self) { try Presentation(data:ZIPWriter.write(duplicateParts,compress:false)) }
}

@Test func keynoteNativeStylesTablesChartsAndBuilds() throws {
    let data=try fixture("native-advanced.keynote.zip"),p=try Presentation(data:data),slide=p.slides[0]
    let shape=slide.elements[0],table=try #require(slide.elements[1].table),chart=try #require(slide.elements[2].chart)
    #expect(shape.fill == .solid(.rgb("FF0000")))
    #expect(shape.text?.plainText == "A😀B\n次の行")
    #expect(shape.text?.paragraphs[0].runs.map(\.text) == ["A😀","B"])
    #expect(shape.text?.paragraphs[0].runs[0].style.bold == true)
    #expect(shape.text?.paragraphs[0].runs[1].style.bold == nil)
    #expect(shape.text?.paragraphs[0].runs[0].style.font.size == 24 && shape.text?.paragraphs[0].style.alignment == .center)
    #expect(table.columnWidths == [100,100] && table.rowHeights == [25,25])
    #expect(table.rows[0][0].text.plainText == "Fictional cell" && table.rows[0][1].value?.number == 42.5)
    #expect(table.rows[1].allSatisfy { $0.text.plainText.isEmpty && $0.value == nil })
    #expect(chart.groups[0].series[0].title == "Fictional series" && chart.groups[0].series[0].values?.points.map(\.index) == [0])
    #expect(chart.groups[0].series[0].values?.points[0].number == 12.5)
    #expect(slide.transition?.effect == "Dissolve" && slide.transition?.durationMilliseconds == 1500)
    #expect(slide.timing?.targetElementIDs == ["30"] && slide.timing?.root.children.map(\.name) == ["build","chunk"])
    #expect(slide.timing?.root.children[1].attributes["delay"] == "0.25")
    #expect(throws:SlideError.self) { try Presentation(data:data,options:.init(limits:.init(maxTableCells:3))) }
    #expect(throws:SlideError.self) { try Presentation(data:data,options:.init(limits:.init(maxTableCells:-1))) }
}

@Test func directLineNoneAndBackgroundReferenceOverrideInheritance() throws {
    let data=try changedFixture("reading-models.pptx") { parts in
        let path="ppt/slides/slide1.xml",root=try MarkupNode.parse(parts[path]!,part:path,limits:.init()),sp=try #require(root.descendants("sp").first)
        sp.child("spPr")?.replace("ln",with:try MarkupNode.fragment("<a:ln><a:noFill/></a:ln>"))
        sp.remove(["style"]);sp.content.append(.node(try MarkupNode.fragment("<p:style><a:lnRef idx=\"1\"><a:srgbClr val=\"ABCDEF\"/></a:lnRef></p:style>")))
        root.child("cSld")?.replace("bg",with:try MarkupNode.fragment("<p:bg><p:bgRef idx=\"0\"><a:srgbClr val=\"FFFFFF\"/></p:bgRef></p:bg>"))
        parts[path]=Data(root.xml.utf8)
        let masterPath="ppt/slideMasters/slideMaster1.xml",master=try MarkupNode.parse(parts[masterPath]!,part:masterPath,limits:.init())
        master.child("cSld")?.replace("bg",with:try MarkupNode.fragment("<p:bg><p:bgPr><a:solidFill><a:srgbClr val=\"FF0000\"/></a:solidFill></p:bgPr></p:bg>"));parts[masterPath]=Data(master.xml.utf8)
    }
    let p=try Presentation(data:data),slide=p.slides[0],resolved=try p.resolveElement(slideID:slide.id,elementID:slide.elements[0].id)
    #expect(resolved.element.stroke == nil && resolved.origins["stroke"]?.kind == .direct)
    #expect(resolved.background == Fill.none)
}

@Test func odpEmbeddedChartLocalTableAndSparseRanges() throws {
    let data=try changedFixture("styles.odp") { parts in
        let path="content.xml",root=try MarkupNode.parse(parts[path]!,part:path,limits:.init()),page=try #require(root.descendants("page",ns:"urn:oasis:names:tc:opendocument:xmlns:drawing:1.0").first)
        let frame=try MarkupNode.parse(Data("<draw:frame xmlns:draw=\"urn:oasis:names:tc:opendocument:xmlns:drawing:1.0\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" draw:id=\"fictional-chart\"><draw:object xlink:href=\"./ObjectFictional\"/></draw:frame>".utf8),part:path,limits:.init())
        page.content.append(.node(frame));parts[path]=Data(root.xml.utf8)
        parts["ObjectFictional/content.xml"]=Data("<office:document-content xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:chart=\"urn:oasis:names:tc:opendocument:xmlns:chart:1.0\" xmlns:table=\"urn:oasis:names:tc:opendocument:xmlns:table:1.0\" xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\"><office:body><office:chart><chart:chart chart:class=\"chart:bar\"><chart:plot-area><chart:axis chart:dimension=\"x\"><chart:categories table:cell-range-address=\"$local-table.$A$2:.$A$3\"/></chart:axis><chart:series chart:label-cell-address=\"$local-table.$B$1\" chart:values-cell-range-address=\"$local-table.$B$2:.$B$3\"/></chart:plot-area><table:table table:name=\"local-table\"><table:table-row><table:table-cell/><table:table-cell><text:p>Fictional series</text:p></table:table-cell></table:table-row><table:table-row><table:table-cell><text:p>A</text:p></table:table-cell><table:table-cell office:value-type=\"float\" office:value=\"12.5\"/></table:table-row><table:table-row><table:table-cell><text:p>B</text:p></table:table-cell><table:table-cell/></table:table-row></table:table></chart:chart></office:chart></office:body></office:document-content>".utf8)
    }
    let p=try Presentation(data:data),chart=try #require(p.slides[0].elements.last?.chart),series=chart.groups[0].series[0]
    #expect(chart.part.path == "ObjectFictional/content.xml" && chart.properties?.name == "document-content")
    #expect(series.title == "Fictional series" && series.categories?.points.map(\.text) == ["A","B"])
    #expect(series.values?.points.map(\.index) == [0] && series.values?.points[0].number == 12.5)
    #expect(chart.axes[0].kind == "x")
    var source=try parts(data)
    source["ObjectFictional/content.xml"]=Data(String(decoding:source["ObjectFictional/content.xml"]!,as:UTF8.self).replacingOccurrences(of:"$local-table.$B$2",with:"$external-table.$B$2").utf8)
    let external=try Presentation(data:ZIPWriter.write(source,compress:false))
    #expect(external.slides[0].elements.last?.chart?.groups[0].series[0].values?.points == [])
    #expect(external.readWarnings.contains { $0.message.contains("rangeを解決") })
}

@Test func keynoteUnsupportedCellsRemainOpaque() throws {
    let data=try fixture("native-unsupported-cell.keynote.zip"),p=try Presentation(data:data),table=p.slides[0].elements[1]
    #expect(table.kind == .opaque && table.table == nil && table.nativeObjectID == 80)
    #expect(p.readWarnings.contains { $0.message.contains("セルstorage版6") })
    let original=try #require(parts(data)["Index/Document.iwa"])
    #expect(try p.asset(at:"Index/Document.iwa") == original)
    #expect(try p.readKeynoteObjects().objects.contains { $0.type == 6002 })
    #expect(p.slides[0].elements[2].chart != nil)
}

@Test func keynoteNativeBezierPathsAndConnectors() throws {
    let presentation=try Presentation(data:fixture("native-paths.keynote.zip")),elements=presentation.slides[0].elements
    #expect(elements.map(\.kind) == [.shape,.connector])
    #expect(elements[0].isFlippedHorizontally && !elements[0].isFlippedVertically)
    let path=try #require(elements[0].customGeometry?.paths.first)
    #expect(path.width == 200 && path.height == 80)
    #expect(path.commands == [.move(.init(x:"0.0",y:"0.0")),.line(.init(x:"20.0",y:"10.0")),.quadratic(control:.init(x:"25.0",y:"15.0"),end:.init(x:"30.0",y:"20.0")),.cubic(control1:.init(x:"35.0",y:"25.0"),control2:.init(x:"40.0",y:"30.0"),end:.init(x:"45.0",y:"35.0")),.close])
    #expect(elements[1].customGeometry?.paths.first == path)
    let inventory=try presentation.readKeynoteObjects()
    #expect(inventory.objects(id:31).first?.objectReferences == [30])
    #expect(throws:SlideError.self) { try Presentation(data:fixture("native-invalid-path.keynote.zip")) }
    let unknown=try Presentation(data:fixture("native-unknown-path.keynote.zip"))
    let rawUnknown=try unknown.readKeynoteObjects()
    #expect(unknown.slides[0].elements[0].customGeometry == nil)
    #expect(!unknown.readWarnings.isEmpty && rawUnknown.objects(id:30).first?.rawData.isEmpty == false)
}
