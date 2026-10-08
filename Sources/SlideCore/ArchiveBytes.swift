import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

package struct ArchiveBytes: Sendable {
    let memory: Data?
    let file: FileArchiveBytes?
    package var count: Int { memory?.count ?? file!.count }
    package init(_ data: Data) { memory = data.startIndex == 0 ? data : Data(data); file = nil }
    package init(url: URL, cacheBytes: Int) throws { memory = nil; file = try .init(url: url, cacheBytes: cacheBytes) }
    package func check() throws { try file?.check() }
    package func read(_ range: Range<Int>) throws -> Data {
        guard range.lowerBound >= 0, range.upperBound <= count else { throw SlideError.corruptedPackage("archive範囲外") }
        if let memory { return memory.subdata(in: range) }; return try file!.read(range)
    }
    package subscript(_ index: Int) -> UInt8 { get throws { if let memory { return memory[index] }; return try file!.read(index..<index + 1)[0] } }
    package subscript(_ range: Range<Int>) -> Data { get throws { try read(range) } }
}

/// 開いたdescriptorを保持。全操作とcacheは同じlockの下で直列化する。
package final class FileArchiveBytes: @unchecked Sendable {
    package struct Identity: Equatable, Sendable {
        let device: UInt64, inode: UInt64, size: Int64, modified: Int64, nanos: Int64, changed: Int64, changeNanos: Int64
        init(_ s: stat) {
            device = UInt64(s.st_dev); inode = UInt64(s.st_ino); size = Int64(s.st_size)
            #if canImport(Darwin)
            modified = Int64(s.st_mtimespec.tv_sec); nanos = Int64(s.st_mtimespec.tv_nsec); changed = Int64(s.st_ctimespec.tv_sec); changeNanos = Int64(s.st_ctimespec.tv_nsec)
            #else
            modified = Int64(s.st_mtim.tv_sec); nanos = Int64(s.st_mtim.tv_nsec); changed = Int64(s.st_ctim.tv_sec); changeNanos = Int64(s.st_ctim.tv_nsec)
            #endif
        }
    }
    private let handle: FileHandle, url: URL, cacheLimit: Int, lock = NSLock()
    package let identity: Identity
    private var cache: LRUDataCache<Int>
    private var fetchedBytes = 0
    package var statistics: (fetchedBytes: Int, peakCachedBytes: Int) { lock.withLock { (fetchedBytes, cache.statistics.peakRetainedBytes) } }
    package var cacheStatistics: ReadingCacheStatistics { lock.withLock { cache.statistics } }
    package let count: Int
    package init(url: URL, cacheBytes: Int) throws {
        guard url.isFileURL, cacheBytes >= 0 else { throw SlideError.invalidModel("file-backed設定") }
        handle = try FileHandle(forReadingFrom: url); self.url = url; cacheLimit = cacheBytes; cache = .init(limit: cacheBytes)
        var info = stat(); guard fstat(handle.fileDescriptor, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_size >= 0, info.st_size <= Int.max else { throw SlideError.unsupportedContainer("file-backedは通常fileのみ") }
        identity = Identity(info); count = Int(info.st_size)
    }
    deinit { try? handle.close() }
    private func validate() throws {
        var descriptor = stat(), path = stat()
        guard fstat(handle.fileDescriptor, &descriptor) == 0, lstat(url.path, &path) == 0, Identity(descriptor) == identity, Identity(path) == identity else { throw SlideError.corruptedPackage("file-backed入力が変更または置換されました") }
    }
    package func check() throws { try lock.withLock { try validate() } }
    package func read(_ range: Range<Int>) throws -> Data { try lock.withLock {
        try Task.checkCancellation(); try validate()
        guard range.lowerBound >= 0, range.upperBound <= count else { throw SlideError.corruptedPackage("file-backed範囲外") }
        if range.isEmpty { return Data() }
        let blockSize = min(64 << 10, cacheLimit)
        if blockSize > 0, range.count <= blockSize {
            let start = range.lowerBound / blockSize * blockSize
            if range.upperBound <= min(count, start + blockSize) {
                let data: Data
                if let hit = cache.value(for: start) { data = hit }
                else {
                    data = try fetch(start..<min(count, start + blockSize))
                    cache.insert(data, for: start)
                }
                try validate(); return data.subdata(in: (range.lowerBound - start)..<(range.upperBound - start))
            }
        }
        let data = try fetch(range); try validate(); return data
    } }
    private func fetch(_ range: Range<Int>) throws -> Data {
        try handle.seek(toOffset: UInt64(range.lowerBound)); var data = Data(); data.reserveCapacity(range.count)
        while data.count < range.count { try Task.checkCancellation(); guard let chunk = try handle.read(upToCount: min(64 << 10, range.count - data.count)), !chunk.isEmpty else { throw SlideError.corruptedPackage("file-backed読取切断") }; data.append(chunk) }
        fetchedBytes += data.count; return data
    }
}
