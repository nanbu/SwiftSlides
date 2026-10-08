import Foundation
import SlideCore

extension PPTXReader {
    func relationships(from source: String) throws -> [String: Relationship] {
        let path = OPCPackage.relationshipPart(for: source)
        guard let bytes = extraParts[path] else { return try package.relationships(from: source) }
        let root = try MarkupNode.parse(bytes, part: path, limits: options.limits)
        guard root.name == "Relationships", root.namespace == NS.rels else { throw SlideError.invalidRelationship(part: path, detail: "不正なrelationship root") }
        var result: [String: Relationship] = [:]
        for child in root.children {
            guard child.namespace == NS.rels, child.name == "Relationship", let id = child.attr("Id"), !id.isEmpty,
                  result[id] == nil, let uri = child.attr("Type"), let target = child.attr("Target"), !target.isEmpty else { throw SlideError.invalidRelationship(part:path,detail:"不正または重複したrelationship") }
            let mode = child.attr("TargetMode")
            guard mode == nil || mode == "Internal" || mode == "External" else { throw SlideError.invalidRelationship(part:path,detail:"不正なTargetMode") }
            let targetPath = mode == "External" ? nil : try OPCPackage.resolve(target, from: source)
            if let targetPath, extraParts[targetPath] == nil, package.archive.entries[targetPath] == nil { throw SlideError.missingPart(targetPath) }
            let known = uri.hasPrefix(NS.r + "/") || uri.hasPrefix(NS.strictR + "/") || uri.hasPrefix(NS.rels + "/")
            result[id] = .init(id:id,type:known ? String(uri.split(separator:"/").last!) : uri,target:target,path:targetPath)
        }
        return result
    }
    func layout(at path: String) throws -> SlideLayoutPart {
        let root = try tree(path)
        guard root.isP, root.name == "sldLayout", let c = root.child("cSld"), let sp = c.child("spTree") else { throw SlideError.corruptedPackage("不正なlayout: \(path)") }
        let rels = try relationships(from: path); var ids: Set<String> = []
        for child in root.children where !["cSld","clrMapOvr"].contains(child.name) { warn(path,child) }
        return .init(path:path,name:c.attr("name") ?? "",masterPath:rels.values.first { $0.type == "slideMaster" }?.path,
            themeOverridePath:rels.values.first { $0.type == "themeOverride" }?.path,
            elements:try elements(sp,rels:rels,part:path,slideID:nil,ids:&ids),background:try fill(c.child("bg")?.child("bgPr"),part:path),
            backgroundReference:styleReference(c.child("bg")?.child("bgRef"),part:path),colorMapOverride:root.child("clrMapOvr")?.child("overrideClrMapping")?.attributes,
            usesMasterColorMapping:root.child("clrMapOvr").map { $0.child("masterClrMapping") != nil },showsMasterShapes:boolean(root.attr("showMasterSp")),layoutType:root.attr("type"))
    }
    func master(at path: String) throws -> SlideMasterPart {
        let root = try tree(path)
        guard root.isP, root.name == "sldMaster", let c = root.child("cSld"), let sp = c.child("spTree") else { throw SlideError.corruptedPackage("不正なmaster: \(path)") }
        let rels = try relationships(from:path); var ids: Set<String> = [], textStyles: [String:TextListStyle] = [:]
        for name in ["titleStyle","bodyStyle","otherStyle"] { if let value = listStyle(root.child("txStyles")?.child(name),part:path) { textStyles[name] = value } }
        var layouts: [String] = []
        for entry in root.child("sldLayoutIdLst")?.named("sldLayoutId") ?? [] {
            guard let rid = entry.rel("id"), let rel = rels[rid], rel.type == "slideLayout", let target = rel.path else { throw SlideError.invalidRelationship(part:path,detail:"masterのlayout参照が不正です") }; layouts.append(target)
        }
        for child in root.children where !["cSld","clrMap","txStyles","sldLayoutIdLst"].contains(child.name) { warn(path,child) }
        return .init(path:path,name:c.attr("name") ?? "",themePath:rels.values.first { $0.type == "theme" }?.path,
            elements:try elements(sp,rels:rels,part:path,slideID:nil,ids:&ids),background:try fill(c.child("bg")?.child("bgPr"),part:path),
            backgroundReference:styleReference(c.child("bg")?.child("bgRef"),part:path),colorMap:root.child("clrMap")?.attributes,textStyles:textStyles,layoutPaths:layouts)
    }
}

extension Presentation {
    func sourcePartReader() throws -> PPTXReader {
        try Task.checkCancellation()
        guard sourceFormat == nil || sourceFormat == .pptx || sourceFormat == .pptm else { throw SlideError.unsafeEdit("この形式のmaster/layout読取は未対応です") }
        if let storage {
            var extra: [String:Data] = [:], types: [String:String] = [:]
            for clone in slideClones.values { extra.merge(clone.parts,uniquingKeysWith:{ a,_ in a }); types.merge(clone.contentTypes,uniquingKeysWith:{ a,_ in a }) }
            return try PPTXReader(storage.data,options:.init(limits:storage.limits),extraParts:extra,extraTypes:types)
        }
        guard !slideClones.isEmpty else { throw SlideError.missingPart("原本master/layout") }
        return try PPTXReader(CodecSet([.pptx]).write(self).data,options:.init())
    }
    public func readLayout(at path: String) throws -> SlideLayoutReadResult {
        let reader = try sourcePartReader(); let layout = try reader.layout(at:path)
        return .init(layout:layout,warnings:reader.warnings.result)
    }
    public func readMaster(at path: String) throws -> SlideMasterReadResult {
        let reader = try sourcePartReader(); let master = try reader.master(at:path)
        return .init(master:master,warnings:reader.warnings.result)
    }
    @concurrent public func readLayout(at path: String) async throws -> SlideLayoutReadResult { try readLayoutSync(at:path) }
    @concurrent public func readMaster(at path: String) async throws -> SlideMasterReadResult { try readMasterSync(at:path) }
    private func readLayoutSync(at path: String) throws -> SlideLayoutReadResult { try readLayout(at:path) }
    private func readMasterSync(at path: String) throws -> SlideMasterReadResult { try readMaster(at:path) }
}
