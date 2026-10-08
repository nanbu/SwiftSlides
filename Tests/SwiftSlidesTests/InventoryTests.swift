import Foundation
import Testing
@testable import SlideCore
import SwiftSlides

@Test func inventoryListsLocatedReferencesAndIdentities() throws {
    let data = try changedFixture { parts in
        let path = "ppt/slides/slide1.xml"
        parts[path] = parts[path]!.replacingUTF8("</p:sld>", "<p:timing><p:tnLst><p:par><p:cTn id=\"1\"><p:childTnLst><p:set><p:cBhvr><p:cTn id=\"2\"/><p:tgtEl><p:spTgt spid=\"2\"/></p:tgtEl></p:cBhvr></p:set></p:childTnLst></p:cTn></p:par></p:tnLst></p:timing><p:extLst><p:ext uri=\"test\"><v:ref xmlns:v=\"urn:fixture\" spid=\"2\"/></p:ext></p:extLst></p:sld>")
    }
    let p = try Presentation(data: data), graph = try p.inspectPreservation()
    let timing = try #require(graph.references.first { $0.kind == .timing })
    #expect(timing.targetElementID == "2")
    #expect(timing.location.slideID == p.slides[0].id)
    #expect(timing.location.path.contains("spTgt[1]"))
    #expect(timing.location.attribute == "spid")
    #expect(graph.references.contains { $0.kind == .unknown && $0.value == "2" && $0.knowledge == .unknown })
    #expect(graph.identities.contains { $0.elementID == "2" && $0.part == "ppt/slides/slide1.xml" })
    #expect(!graph.unresolvedScopes.isEmpty)
    #expect(try p.write().data == data)
    #expect(try Presentation().inspectPreservation().parts.isEmpty)
}

@Test func inventoryConnectorAndUnknownDeletionSafety() throws {
    let data = try textPresentation().write().data
    let archive = try PackageArchive(data)
    var parts = try Dictionary(uniqueKeysWithValues: archive.paths.map { ($0, try archive.read($0)) })
    parts["ppt/slides/slide1.xml"] = parts["ppt/slides/slide1.xml"]!.replacingUTF8("</p:sld>", "<p:extLst><p:ext uri=\"test\"><v:ref xmlns:v=\"urn:fixture\" target=\"2\"/></p:ext></p:extLst></p:sld>")
    var p = try Presentation(data: ZIPWriter.write(parts, compress: true))
    p.slides[0].elements.removeFirst()
    #expect(throws: SlideError.self) { try p.write().data }
    p = try Presentation(data: ZIPWriter.write(parts, compress: true))
    p.slides[0].elements[0].frame?.x = 25
    #expect(try Presentation(data: p.write().data).slides[0].elements[0].frame?.x == 25)

    var slide = Slide()
    slide.addShape(frame: .init(x: 0, y: 0, width: 30, height: 30))
    slide.addLine(from: (30, 30), to: (60, 60))
    let connectorData = try Presentation(slides: [slide]).write().data
    let connectorArchive = try PackageArchive(connectorData)
    var cp = try Dictionary(uniqueKeysWithValues: connectorArchive.paths.map { ($0, try connectorArchive.read($0)) })
    cp["ppt/slides/slide1.xml"] = cp["ppt/slides/slide1.xml"]!.replacingUTF8("<p:cNvCxnSpPr/>", "<p:cNvCxnSpPr><a:stCxn id=\"2\" idx=\"0\"/></p:cNvCxnSpPr>")
    // Serialized XML may use explicit closing tags.
    cp["ppt/slides/slide1.xml"] = cp["ppt/slides/slide1.xml"]!.replacingUTF8("<p:cNvCxnSpPr></p:cNvCxnSpPr>", "<p:cNvCxnSpPr><a:stCxn id=\"2\" idx=\"0\"/></p:cNvCxnSpPr>")
    var connected = try Presentation(data: ZIPWriter.write(cp, compress: true))
    let connectorGraph = try connected.inspectPreservation()
    #expect(connectorGraph.references.contains { $0.kind == .connector && $0.targetElementID == "2" && $0.location.elementID == "3" })
    connected.slides[0].elements.removeFirst()
    #expect(throws: SlideError.self) { try connected.write().data }
    connected.slides[0].elements.removeAll()
    #expect(try Presentation(data: connected.write().data).slides[0].elements.isEmpty)
}

@Test func inventoryDetectsDanglingUnmodeledRelationship() throws {
    let data = try changedFixture { parts in
        parts["ppt/slides/slide1.xml"] = parts["ppt/slides/slide1.xml"]!.replacingUTF8("</p:sld>", "<p:extLst><p:ext uri=\"test\"><v:ref xmlns:v=\"urn:fixture\" r:id=\"missing\"/></p:ext></p:extLst></p:sld>")
    }
    let p = try Presentation(data: data)
    #expect(throws: SlideError.self) { try p.inspectPreservation() }
}

@Test func unknownReferenceWithinKnownNamespaceIsNotAssumedSafe() throws {
    let data = try changedFixture { parts in
        parts["ppt/slides/slide1.xml"] = parts["ppt/slides/slide1.xml"]!.replacingUTF8("</p:sld>", "<p:extLst><p:ext uri=\"test\"><p:futureRef targetId=\"2\"/></p:ext></p:extLst></p:sld>")
    }
    var p = try Presentation(data: data)
    let graph = try p.inspectPreservation()
    #expect(graph.references.contains { $0.kind == .unknown && $0.location.attribute == "targetId" })
    #expect(graph.references.contains { $0.kind == .relationship && $0.location.part.hasSuffix(".rels") && !$0.sourcePart.hasSuffix(".rels") })
    p.slides[0].elements.removeFirst()
    #expect(try !p.planWrite().canSave)
}

@Test func opaqueSyntheticIdentityDoesNotInventSourceID() throws {
    let data = try changedFixture { parts in
        parts["ppt/slides/slide1.xml"] = parts["ppt/slides/slide1.xml"]!.replacingUTF8("</p:spTree>", "<v:object xmlns:v=\"urn:fixture\" target=\"2\"/></p:spTree>")
    }
    let p = try Presentation(data: data), graph = try p.inspectPreservation()
    let id = try #require(p.slides[0].elements.last?.id)
    #expect(id.hasPrefix("opaque-"))
    #expect(graph.identities.contains { $0.elementID == id && $0.sourceID == nil })
    #expect(graph.references.contains { $0.kind == .unknown && $0.location.elementID == id })
}
