import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// ファイル本文を保持しないKeynote directory package。symlinkと変更を拒否する。
package final class DirectoryArchive: Sendable {
    let root: URL
    let sizes: [String: Int]
    private let identities: [String: FileArchiveBytes.Identity]
    init(_ url: URL, limits: PackageLimits) throws {
        guard url.isFileURL, limits.maxEntries > 0, limits.maxPartBytes >= 0, limits.maxExpandedBytes >= 0 else { throw SlideError.invalidModel("directory package設定") }
        guard try url.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink != true else { throw SlideError.unsupportedContainer("directory packageのsymlink") }
        root = url.resolvingSymlinksInPath().standardizedFileURL
        var identities: [String:FileArchiveBytes.Identity] = [:], sizes: [String:Int] = [:], total = 0, failure: (any Error)?
        func inspect(_ path: String) throws -> stat {
            var value = stat(); guard lstat(path,&value) == 0 else { throw SlideError.corruptedPackage("directory packageのstat失敗") }
            guard value.st_mode & mode_t(S_IFMT) != mode_t(S_IFLNK) else { throw SlideError.unsupportedContainer("directory package内symlink") }; return value
        }
        let rootInfo = try inspect(root.path); guard rootInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { throw SlideError.unknownFormat }
        identities[""] = .init(rootInfo)
        guard let enumerator = FileManager.default.enumerator(at:root,includingPropertiesForKeys:nil,options:[],errorHandler:{ _,error in failure = error; return false }) else { throw SlideError.corruptedPackage("directory package走査") }
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let info = try inspect(url.path), normalized = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard normalized.hasPrefix(root.path + "/") else { throw SlideError.corruptedPackage("directory package境界") }
            let path = String(normalized.dropFirst(root.path.count+1))
            guard !path.contains(":"), !path.contains("\\"), identities.count <= limits.maxEntries else { throw SlideError.limitExceeded("directory package名/entry数") }
            identities[path] = .init(info)
            if info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) { continue }
            guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_size >= 0 else { throw SlideError.unsupportedContainer("directory package非通常file") }
            guard info.st_size <= limits.maxPartBytes, info.st_size <= limits.maxExpandedBytes-total else { throw SlideError.limitExceeded("directory package展開量") }
            sizes[path] = Int(info.st_size); total += Int(info.st_size)
        }
        if let failure { throw failure }
        guard sizes["Index/Document.iwa"] != nil || sizes["Index.zip"] != nil || sizes[".iwpv2"] != nil || sizes[".iwph"] != nil else { throw SlideError.unknownFormat }
        self.identities = identities; self.sizes = sizes
        try validate()
    }
    func validate() throws {
        for (path, expected) in identities {
            try Task.checkCancellation(); var info = stat()
            let url = path.isEmpty ? root : root.appendingPathComponent(path)
            guard lstat(url.path,&info) == 0, FileArchiveBytes.Identity(info) == expected else { throw SlideError.corruptedPackage("file-backed directory入力が変更または置換されました") }
        }
    }
    func read(_ path: String) throws -> Data {
        guard let count = sizes[path], let expected = identities[path] else { throw SlideError.missingPart(path) }
        try validate()
        let file = try FileArchiveBytes(url:root.appendingPathComponent(path),cacheBytes:0)
        guard file.identity == expected else { throw SlideError.corruptedPackage("directory packageのfile置換") }
        let result = try file.read(0..<count); try validate(); return result
    }
}
