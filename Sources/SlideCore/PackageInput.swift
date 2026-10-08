import Foundation

package enum PackageInput {
    package static func read(_ url: URL, limits: PackageLimits) throws -> Data {
        try Task.checkCancellation()
        let values=try url.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
        guard values.isDirectory == true else { return try Data(contentsOf:url,options:.mappedIfSafe) }
        guard values.isSymbolicLink != true else { throw SlideError.unsupportedContainer("symlink package") }
        let directory=url.resolvingSymlinksInPath().standardizedFileURL
        let base=directory.path.hasSuffix("/") ? String(directory.path.dropLast()) : directory.path
        let keys:[URLResourceKey]=[.isRegularFileKey,.isDirectoryKey,.isSymbolicLinkKey,.fileSizeKey]
        var failure:(any Error)?
        guard let enumerator=FileManager.default.enumerator(at:directory,includingPropertiesForKeys:keys,options:[],errorHandler:{ _,error in failure=error;return false }) else { throw SlideError.corruptedPackage("package directoryを走査できません") }
        var parts:[String:Data]=[:],total=0
        for case let entry as URL in enumerator {
            try Task.checkCancellation()
            let value=try entry.resourceValues(forKeys:Set(keys))
            guard value.isSymbolicLink != true else { throw SlideError.unsupportedContainer("package内symlink") }
            if value.isDirectory == true { continue }
            guard value.isRegularFile == true else { throw SlideError.unsupportedContainer("package内の非通常file") }
            let normalized=entry.resolvingSymlinksInPath().standardizedFileURL.path
            guard normalized.hasPrefix(base+"/") else { throw SlideError.corruptedPackage("package内パス境界") }
            guard let size=value.fileSize,size >= 0,size <= limits.maxPartBytes,size <= limits.maxExpandedBytes-total,parts.count < limits.maxEntries else { throw SlideError.limitExceeded("directory packageサイズ/件数") }
            let name=String(normalized.dropFirst(base.count+1)),bytes=try Data(contentsOf:entry)
            guard bytes.count == size else { throw SlideError.corruptedPackage("package走査中のfile変更") }
            total += size;parts[name]=bytes
        }
        if let failure { throw failure }
        guard parts["Index/Document.iwa"] != nil || parts["Index.zip"] != nil || parts[".iwpv2"] != nil || parts[".iwph"] != nil || parts["index.apxl"] != nil || parts["index.xml"] != nil || parts["presentation.apxl"] != nil || parts["index.apxl.gz"] != nil || parts["index.xml.gz"] != nil else { throw SlideError.unknownFormat }
        return try ZIPWriter.write(parts,compress:false)
    }
}
