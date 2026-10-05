import Foundation
import CZlib

/// ZIP32 writer with deterministic ordering and timestamps. The reader also accepts ZIP64.
package enum ZIPWriter {
    package static func write(_ parts: [String: Data], compress: Bool, original: PackageArchive? = nil, unchanged: Set<String> = []) throws -> Data {
        try Task.checkCancellation()
        guard parts.count < 65_535 else { throw SlideError.limitExceeded("ZIP32 entry count") }
        var output = Data(), directory = Data()
        func put16(_ n: UInt16, into data: inout Data) { data.append(UInt8(truncatingIfNeeded: n)); data.append(UInt8(truncatingIfNeeded: n >> 8)) }
        func put32(_ n: UInt32, into data: inout Data) { put16(UInt16(truncatingIfNeeded: n), into: &data); put16(UInt16(truncatingIfNeeded: n >> 16), into: &data) }
        func u32(_ n: Int) throws -> UInt32 { guard n < Int(UInt32.max) else { throw SlideError.limitExceeded("ZIP32 byte count") }; return UInt32(n) }
        for name in parts.keys.sorted() {
            try Task.checkCancellation()
            let bytes = parts[name]!, filename = Data(name.utf8)
            guard filename.count <= Int(UInt16.max), !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"), !name.contains(":"), !name.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == "." || $0 == ".." || $0.isEmpty }) else { throw SlideError.invalidModel("不正なパーツ名") }
            let offset = try u32(output.count)
            let packed: Data, method: UInt16, size: UInt32, crc: UInt32
            if unchanged.contains(name), let original, let entry = original.entries[name] {
                packed = try original.compressedBytes(name); method = entry.method; size = try u32(entry.expandedSize); crc = entry.crc
            } else {
                size = try u32(bytes.count)
                packed = compress && !bytes.isEmpty ? try deflate(bytes) : bytes
                method = compress && !bytes.isEmpty ? 8 : 0
                crc = try Checksum.crc(bytes)
            }
            let packedSize = try u32(packed.count)
            put32(0x04034b50, into: &output); put16(20, into: &output); put16(0x800, into: &output); put16(method, into: &output); put16(0, into: &output); put16(33, into: &output)
            put32(crc, into: &output); put32(packedSize, into: &output); put32(size, into: &output); put16(UInt16(filename.count), into: &output); put16(0, into: &output); output.append(filename); output.append(packed)
            put32(0x02014b50, into: &directory); put16(20, into: &directory); put16(20, into: &directory); put16(0x800, into: &directory); put16(method, into: &directory); put16(0, into: &directory); put16(33, into: &directory)
            put32(crc, into: &directory); put32(packedSize, into: &directory); put32(size, into: &directory); put16(UInt16(filename.count), into: &directory)
            for _ in 0..<4 { put16(0, into: &directory) }; put32(0, into: &directory); put32(offset, into: &directory); directory.append(filename)
        }
        let start = try u32(output.count), size = try u32(directory.count); output.append(directory); _ = try u32(output.count)
        put32(0x06054b50, into: &output); put16(0, into: &output); put16(0, into: &output); put16(UInt16(parts.count), into: &output); put16(UInt16(parts.count), into: &output); put32(size, into: &output); put32(start, into: &output); put16(0, into: &output)
        return output
    }
    private static func deflate(_ input: Data) throws -> Data {
        try Task.checkCancellation()
        var stream = z_stream()
        guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw SlideError.corruptedPackage("deflate init") }
        defer { deflateEnd(&stream) }
        var output = Data(count: Int(deflateBound(&stream, uLong(input.count))))
        let status = try input.withUnsafeBytes { src in try output.withUnsafeMutableBytes { dst in
            var supplied = 0
            while true {
                try Task.checkCancellation()
                if stream.avail_in == 0, supplied < src.count {
                    let count = min(64 << 10, src.count - supplied)
                    stream.next_in = UnsafeMutablePointer(mutating: src.baseAddress!.advanced(by: supplied).assumingMemoryBound(to: UInt8.self))
                    stream.avail_in = uInt(count); supplied += count
                }
                let offset = Int(stream.total_out), previousInput = stream.total_in
                guard offset < dst.count else { throw SlideError.corruptedPackage("deflate output overflow") }
                stream.next_out = dst.baseAddress!.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
                stream.avail_out = uInt(min(64 << 10, dst.count - offset))
                let status = CZlib.deflate(&stream, supplied == src.count ? Z_FINISH : Z_NO_FLUSH)
                if status == Z_STREAM_END { return status }
                guard status == Z_OK, stream.total_in != previousInput || stream.total_out != offset else { throw SlideError.corruptedPackage("deflate failed") }
            }
        } }
        guard status == Z_STREAM_END else { throw SlideError.corruptedPackage("deflate failed") }; output.count = Int(stream.total_out); return output
    }
}
