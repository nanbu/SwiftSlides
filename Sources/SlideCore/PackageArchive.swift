import Foundation
import CZlib

/// Immutable memory/file ZIP or nested package view. No files are extracted to disk.
package struct PackageArchive: Sendable {
    package struct Entry: Sendable {
        package let path: String
        package let compressedSize: Int
        package let expandedSize: Int
        package let method: UInt16
        package let crc: UInt32
        let payload: Range<Int>
    }
    private let data: ArchiveBytes
    private final class Overlay: Sendable {
        let outer: PackageArchive, nested: PackageArchive, aliases: [String: String]
        init(outer: PackageArchive, nested: PackageArchive, aliases: [String: String]) { self.outer = outer; self.nested = nested; self.aliases = aliases }
    }
    private let overlay: Overlay?
    private let directory: DirectoryArchive?
    private let memoryParts: [String:Data]?
    package let entries: [String: Entry]
    package let paths: [String]
    package var fileStatistics: (fetchedBytes: Int, peakCachedBytes: Int)? { data.file?.statistics }
    package var cacheStatistics: ReadingCacheStatistics {
        if let overlay { return overlay.outer.cacheStatistics.adding(overlay.nested.cacheStatistics) }
        return data.file?.cacheStatistics ?? .init(retainedBytes:0,peakRetainedBytes:0,hits:0,misses:0)
    }

    package init(_ data: Data, limits: PackageLimits = .init()) throws { try self.init(ArchiveBytes(data), limits: limits) }
    package init(contentsOf url: URL, limits: PackageLimits = .init(), cacheBytes: Int = 8 << 20) throws {
        if try url.resourceValues(forKeys:[.isDirectoryKey]).isDirectory == true {
            self.init(directory:try DirectoryArchive(url,limits:limits))
        } else { try self.init(ArchiveBytes(url: url, cacheBytes: cacheBytes), limits: limits) }
    }
    private init(directory: DirectoryArchive) {
        self.directory = directory; data = .init(Data()); overlay = nil; memoryParts = nil
        entries = Dictionary(uniqueKeysWithValues:directory.sizes.map { path,size in (path,Entry(path:path,compressedSize:size,expandedSize:size,method:0,crc:0,payload:0..<size)) })
        paths = entries.keys.sorted()
    }
    private init(_ backing: ArchiveBytes, limits: PackageLimits) throws {
        try Task.checkCancellation()
        guard limits.maxEntries > 0, limits.maxExpandedBytes >= 0, limits.maxPartBytes >= 0 else { throw SlideError.limitExceeded("limits must be nonnegative") }
        self.data = backing
        overlay = nil
        directory = nil
        memoryParts = nil
        let parsed = try { () throws -> ([String: Entry], [String]) in
            let b = backing
            func fail(_ s: String) -> SlideError { .corruptedPackage(s) }
            func contains(_ offset: Int, _ length: Int) -> Bool { offset >= 0 && length >= 0 && offset <= b.count && length <= b.count - offset }
            // 索引の連続領域を一度に読む。byteごとのfstat/seekを避け、前後の変更検査は維持する。
            let tailStart = max(0,b.count-65557), tail = try b.read(tailStart..<b.count)
            var directoryWindow: (Range<Int>,Data)?, localWindow: (Range<Int>,Data)?
            func read(_ range: Range<Int>) throws -> Data {
                if let (bounds,bytes) = localWindow, range.lowerBound >= bounds.lowerBound, range.upperBound <= bounds.upperBound { return bytes.subdata(in:range.lowerBound-bounds.lowerBound..<range.upperBound-bounds.lowerBound) }
                if let (bounds,bytes) = directoryWindow, range.lowerBound >= bounds.lowerBound, range.upperBound <= bounds.upperBound { return bytes.subdata(in:range.lowerBound-bounds.lowerBound..<range.upperBound-bounds.lowerBound) }
                if range.lowerBound >= tailStart, range.upperBound <= b.count { return tail.subdata(in:range.lowerBound-tailStart..<range.upperBound-tailStart) }
                return try b.read(range)
            }
            func byte(_ i: Int) throws -> UInt8 {
                guard contains(i,1) else { throw fail("ZIP header範囲外") }
                if let (bounds,bytes) = localWindow, bounds.contains(i) { return bytes[i-bounds.lowerBound] }
                if let (bounds,bytes) = directoryWindow, bounds.contains(i) { return bytes[i-bounds.lowerBound] }
                if i >= tailStart { return tail[i-tailStart] }; return try b[i]
            }
            func u16(_ i: Int) throws -> UInt16 { UInt16(try byte(i)) | UInt16(try byte(i + 1)) << 8 }
            func u32(_ i: Int) throws -> UInt32 { UInt32(try u16(i)) | UInt32(try u16(i + 2)) << 16 }
            func u64(_ i: Int) throws -> UInt64 { UInt64(try u32(i)) | UInt64(try u32(i + 4)) << 32 }
            func integer(_ n: UInt64) throws -> Int {
                guard n <= UInt64(Int.max) else { throw fail("ZIP64 integer overflow") }; return Int(n)
            }
            guard b.count >= 22 else { throw fail("missing ZIP end record") }
            var eocd: Int?
            for i in stride(from: b.count - 22, through: max(0, b.count - 65557), by: -1) {
                if try u32(i) == 0x06054b50, i + 22 + Int(try u16(i + 20)) == b.count { eocd = i; break }
            }
            guard let end = eocd else { throw fail("missing ZIP end record") }
            guard try u16(end + 4) == 0, try u16(end + 6) == 0, try u16(end + 8) == (try u16(end + 10)) else { throw fail("split ZIP is unsupported") }
            var count = Int(try u16(end + 10)), size = Int(try u32(end + 12)), offset = Int(try u32(end + 16))
            var directoryEnd = end
            if end >= 20, try u32(end - 20) == 0x07064b50 {
                guard try u32(end - 16) == 0, try u32(end - 4) == 1 else { throw fail("split ZIP64") }
                let z = try integer(try u64(end - 12))
                guard contains(z, 56), try u32(z) == 0x06064b50 else { throw fail("invalid ZIP64 end record") }
                let recordSize = try integer(try u64(z + 4))
                guard recordSize >= 44, contains(z + 12, recordSize), z + 12 + recordSize == end - 20,
                      try u32(z + 16) == 0, try u32(z + 20) == 0, try u64(z + 24) == (try u64(z + 32)) else { throw fail("invalid ZIP64 layout") }
                count = try integer(try u64(z + 32)); size = try integer(try u64(z + 40)); offset = try integer(try u64(z + 48)); directoryEnd = z
            } else if count == 65535 || size == Int(UInt32.max) || offset == Int(UInt32.max) { throw fail("ZIP64 markers without record") }
            guard count <= limits.maxEntries else { throw SlideError.limitExceeded("ZIP entry count") }
            guard contains(offset, size), offset + size == directoryEnd else { throw fail("invalid ZIP directory bounds") }
            guard size <= limits.maxPartBytes else { throw SlideError.limitExceeded("ZIP directory byte予算") }
            directoryWindow = (offset..<directoryEnd,try read(offset..<directoryEnd))
            var p = offset, total = 0
            var entries: [String: Entry] = [:], paths: [String] = [], ranges: [Range<Int>] = []
            for _ in 0..<count {
                try Task.checkCancellation()
                guard contains(p, 46), p + 46 <= directoryEnd, try u32(p) == 0x02014b50 else { throw fail("invalid ZIP directory entry") }
                let flags = try u16(p + 8), method = try u16(p + 10), crc = try u32(p + 16)
                guard flags & 0x0041 == 0 else { throw SlideError.unsupportedContainer("encrypted ZIP") }
                guard method == 0 || method == 8 else { throw SlideError.unsupportedContainer("ZIP method \(method)") }
                let nameSize = Int(try u16(p + 28)), extraSize = Int(try u16(p + 30)), commentSize = Int(try u16(p + 32))
                let length = 46 + nameSize + extraSize + commentSize
                guard contains(p, length), p + length <= directoryEnd else { throw fail("ZIP directory entry overflow") }
                guard let name = String(bytes: try read((p + 46)..<(p + 46 + nameSize)), encoding: .utf8), !name.isEmpty,
                      !name.hasPrefix("/"), !name.contains("\\"), !name.contains("\0"), !name.split(separator: "/", omittingEmptySubsequences: false).contains(".."),
                      !name.split(separator: "/").contains("."), !name.contains("//"), !name.contains(":") else { throw fail("unsafe ZIP part name") }
                guard entries[name] == nil else { throw fail("duplicate ZIP part \(name)") }
                var expanded = Int(try u32(p + 24)), compressed = Int(try u32(p + 20)), local = Int(try u32(p + 42)), disk = Int(try u16(p + 34))
                let needs64 = expanded == Int(UInt32.max) || compressed == Int(UInt32.max) || local == Int(UInt32.max) || disk == 65535
                if needs64 {
                    var q = p + 46 + nameSize, found = false
                    let stop = q + extraSize
                    while q + 4 <= stop {
                        let tag = try u16(q), n = Int(try u16(q + 2)); q += 4
                        guard n <= stop - q else { throw fail("invalid ZIP extra field") }
                        if tag == 1 {
                            var r = q
                            func take() throws -> Int { guard r + 8 <= q + n else { throw fail("short ZIP64 extra field") }; defer { r += 8 }; return try integer(try u64(r)) }
                            if expanded == Int(UInt32.max) { expanded = try take() }
                            if compressed == Int(UInt32.max) { compressed = try take() }
                            if local == Int(UInt32.max) { local = try take() }
                            if disk == 65535 { guard r + 4 <= q + n else { throw fail("short ZIP64 disk field") }; disk = Int(try u32(r)) }
                            found = true; break
                        }
                        q += n
                    }
                    guard found else { throw fail("missing ZIP64 extra field") }
                }
                guard disk == 0 else { throw fail("split ZIP entry") }
                guard compressed <= Int(UInt32.max), expanded < Int(UInt32.max) else { throw SlideError.unsupportedContainer("ZIP part exceeds the zlib buffer size") }
                guard expanded <= limits.maxPartBytes, expanded <= limits.maxExpandedBytes - total else { throw SlideError.limitExceeded("ZIP expanded bytes") }
                total += expanded
                guard contains(local,30) else { throw fail("invalid local ZIP bounds") }
                localWindow = (local..<local+30,try read(local..<local+30))
                guard contains(local, 30), local + 30 <= offset, try u32(local) == 0x04034b50,
                      try u16(local + 6) == flags, try u16(local + 8) == method else { throw fail("invalid local ZIP header") }
                let localNameSize = Int(try u16(local + 26)), localExtraSize = Int(try u16(local + 28))
                let headerSize = 30 + localNameSize + localExtraSize
                guard contains(local, headerSize), localNameSize == nameSize,
                      try read((local + 30)..<(local + 30 + localNameSize)).elementsEqual(try read((p + 46)..<(p + 46 + nameSize))) else { throw fail("local ZIP name mismatch") }
                if flags & 8 == 0 {
                    guard try u32(local + 14) == crc,
                          try u32(local + 18) == UInt32.max || Int(try u32(local + 18)) == compressed,
                          try u32(local + 22) == UInt32.max || Int(try u32(local + 22)) == expanded else { throw fail("local ZIP size or CRC mismatch") }
                }
                let start = local + headerSize
                guard contains(start, compressed), start + compressed <= offset else { throw fail("ZIP entry overlaps directory") }
                if method == 0, expanded != compressed { throw fail("stored ZIP size mismatch") }
                var occupiedEnd = start + compressed
                if flags & 8 != 0 {
                    var d = occupiedEnd
                    if contains(d, 4), try u32(d) == 0x08074b50 { d += 4 }
                    let is64 = try needs64 || u32(local + 18) == UInt32.max || u32(local + 22) == UInt32.max
                    let descriptorSize = is64 ? 20 : 12
                    guard contains(d, descriptorSize), d + descriptorSize <= offset, try u32(d) == crc else { throw fail("invalid ZIP data descriptor") }
                    if is64 {
                        guard try u64(d + 4) == UInt64(compressed), try u64(d + 12) == UInt64(expanded) else { throw fail("ZIP64 descriptor mismatch") }
                    } else { guard Int(try u32(d + 4)) == compressed, Int(try u32(d + 8)) == expanded else { throw fail("ZIP descriptor mismatch") } }
                    occupiedEnd = d + descriptorSize
                }
                ranges.append(local..<occupiedEnd)
                entries[name] = Entry(path: name, compressedSize: compressed, expandedSize: expanded, method: method, crc: crc, payload: start..<(start + compressed))
                paths.append(name); p += length
            }
            guard p == offset + size else { throw fail("ZIP directory count mismatch") }
            let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
            for i in sorted.indices.dropFirst() where sorted[i].lowerBound < sorted[i - 1].upperBound { throw fail("overlapping ZIP entries") }
            try backing.check()
            return (entries, paths)
        }()
        entries = parsed.0; paths = parsed.1
    }

    /// Nested IWA索引を展開しても、outerの画像/動画は元backingから必要時だけ読む。
    package init(outer: PackageArchive, nested: PackageArchive, excluding: String, prefix: String, limits: PackageLimits) throws {
        var entries = outer.entries.filter { $0.key != excluding }, aliases: [String: String] = [:]
        for path in nested.paths where !path.hasSuffix("/") {
            let destination = path.hasPrefix(prefix) ? path : prefix + path
            guard entries[destination] == nil else { throw SlideError.corruptedPackage("入れ子パーツ重複") }
            let entry = nested.entries[path]!
            entries[destination] = Entry(path: destination, compressedSize: entry.compressedSize, expandedSize: entry.expandedSize, method: entry.method, crc: entry.crc, payload: entry.payload)
            aliases[destination] = path
        }
        guard entries.count <= limits.maxEntries else { throw SlideError.limitExceeded("入れ子entry予算") }
        var total = 0
        for entry in entries.values { guard entry.expandedSize <= limits.maxExpandedBytes - total else { throw SlideError.limitExceeded("入れ子展開量") }; total += entry.expandedSize }
        data = ArchiveBytes(Data()); self.entries = entries; paths = entries.keys.sorted(); overlay = Overlay(outer: outer, nested: nested, aliases: aliases); directory = nil; memoryParts = nil
    }

    /// Flat文書の読取専用パーツ。ZIP化やディスク展開は行わない。
    package init(parts: [String:Data], limits: PackageLimits) throws {
        guard parts.count <= limits.maxEntries else { throw SlideError.limitExceeded("仮想パーツ数") }
        var total = 0, entries: [String:Entry] = [:]
        for (path,bytes) in parts {
            guard bytes.count <= limits.maxPartBytes, bytes.count <= limits.maxExpandedBytes-total else { throw SlideError.limitExceeded("仮想パーツのbyte予算") }
            total += bytes.count
            entries[path] = .init(path:path,compressedSize:bytes.count,expandedSize:bytes.count,method:0,crc:0,payload:0..<bytes.count)
        }
        self.entries = entries; paths = entries.keys.sorted(); memoryParts = parts; data = .init(Data()); overlay = nil; directory = nil
    }

    /// Untouched compressed payload, without inflation. Headers are normalized by the writer.
    package func compressedBytes(_ path: String) throws -> Data {
        try Task.checkCancellation()
        guard directory == nil, memoryParts == nil else { throw SlideError.unsafeEdit("directory/flat packageは読取専用です") }
        if let overlay { return try overlay.aliases[path].map { try overlay.nested.compressedBytes($0) } ?? overlay.outer.compressedBytes(path) }
        guard let entry = entries[path] else { throw SlideError.missingPart(path) }
        return try data.read(entry.payload)
    }

    package func validateFile() throws { if let overlay { try overlay.outer.validateFile(); try overlay.nested.validateFile() }; try directory?.validate(); try data.check() }

    package func read(_ path: String) throws -> Data {
        if let memoryParts { try Task.checkCancellation(); guard let value = memoryParts[path] else { throw SlideError.missingPart(path) }; return value }
        if let directory { return try directory.read(path) }
        if let overlay { return try overlay.aliases[path].map { try overlay.nested.read($0) } ?? overlay.outer.read(path) }
        try data.check()
        try Task.checkCancellation()
        guard let entry = entries[path] else { throw SlideError.missingPart(path) }
        let output: Data
        if entry.method == 0 { output = try data.read(entry.payload) }
        else {
            let compressed = try data.read(entry.payload)
            output = try compressed.withUnsafeBytes { raw in
                var stream = z_stream()
                guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw SlideError.corruptedPackage("inflate initialization") }
                defer { inflateEnd(&stream) }
                var expanded = Data(count: entry.expandedSize + 1)
                let status: Int32 = try expanded.withUnsafeMutableBytes { dst in
                    stream.next_in = UnsafeMutablePointer(mutating: raw.baseAddress!.assumingMemoryBound(to: UInt8.self))
                    stream.avail_in = uInt(entry.compressedSize)
                    while true {
                        try Task.checkCancellation()
                        let offset = Int(stream.total_out), previousInput = stream.total_in
                        guard offset < dst.count else { throw SlideError.corruptedPackage("deflate length mismatch in \(path)") }
                        stream.next_out = dst.baseAddress!.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
                        stream.avail_out = uInt(min(64 << 10, dst.count - offset))
                        let status = inflate(&stream, Z_NO_FLUSH)
                        if status == Z_STREAM_END { return status }
                        guard status == Z_OK, stream.total_in != previousInput || stream.total_out != offset else { throw SlideError.corruptedPackage("invalid deflate stream in \(path)") }
                    }
                }
                guard status == Z_STREAM_END, stream.total_out == entry.expandedSize, stream.total_in == entry.compressedSize else { throw SlideError.corruptedPackage("deflate length mismatch in \(path)") }
                expanded.removeLast(); return expanded
            }
        }
        guard try Checksum.crc(output) == entry.crc else { throw SlideError.corruptedPackage("CRC mismatch in \(path)") }
        return output
    }
}
