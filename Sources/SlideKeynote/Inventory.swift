import Foundation
import SlideCore

extension KeynoteCodec: PreservationInspectingCodec {
    package func inspectPreservation(_ presentation: Presentation) throws -> PackageGraph {
        guard presentation.sourceFormat == .keynote, let storage = presentation.storage else { throw SlideError.unsupportedContainer("Keynote原本なし") }
        let source = try KeynoteSource(storage.data,options:.init(limits:storage.limits),archive:storage.archive)
        var references: [PackageReference] = [], scopes: [ReferenceLocation] = [], inspected = Set<String>()
        for object in source.index.locations {
            let location = ReferenceLocation(part:object.part,path:"object:\(object.id)/type:\(object.type)",elementID:String(object.id))
            inspected.insert(object.part)
            // headerに列挙されたrefは網羅する。本文の任意整数をrefと推測しない。
            for id in object.objectReferences {
                let target = source.index.byID[id]
                references.append(.init(kind:.nativeObject,knowledge:target?.count == 1 ? .known : .unknown,location:location,value:String(id),targetPart:target?.first?.part,targetElementID:String(id)))
            }
            for id in object.dataReferences {
                let data = source.dataReferences.first { $0.id == id }
                references.append(.init(kind:.nativeData,knowledge:data == nil ? .unknown : .known,location:location,value:String(id),targetPart:data?.path,isExternal:data?.path == nil && data?.remoteURL != nil))
            }
            scopes.append(location)
        }
        return .init(parts:source.summary.parts,identities:source.slideIDs.map { .init(slideID:String($0),part:source.index.byID[$0]![0].part,sourceID:String($0)) },references:references,unresolvedScopes:scopes,uninspectedParts:source.archive.paths.filter { !inspected.contains($0) && !$0.hasSuffix("/") })
    }
}
