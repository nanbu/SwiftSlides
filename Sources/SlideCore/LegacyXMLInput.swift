import Foundation
import CZlib

package enum LegacyXMLInput {
    package static let paths = ["index.apxl", "presentation.apxl", "index.xml", "index.apxl.gz", "index.xml.gz"]
    package static func decode(_ data: Data, limits: PackageLimits) throws -> Data {
        guard data.starts(with: [0x1f, 0x8b]) else { guard data.count <= limits.maxPartBytes else { throw SlideError.limitExceeded("旧XMLサイズ") }; return data }
        guard data.count <= Int(uInt.max), limits.maxPartBytes >= 0 else { throw SlideError.limitExceeded("旧XML gzip入力") }
        return try data.withUnsafeBytes { raw in
            var stream = z_stream()
            guard inflateInit2_(&stream, MAX_WBITS + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw SlideError.corruptedPackage("gzip初期化") }
            defer { inflateEnd(&stream) }
            stream.next_in = UnsafeMutablePointer(mutating: raw.baseAddress!.assumingMemoryBound(to: UInt8.self)); stream.avail_in = uInt(data.count)
            var result = Data(), chunk = [UInt8](repeating: 0, count: 64 << 10)
            while true {
                try Task.checkCancellation()
                let previous = stream.total_in
                let status = chunk.withUnsafeMutableBytes { out in stream.next_out = out.baseAddress!.assumingMemoryBound(to: UInt8.self); stream.avail_out = uInt(out.count); return inflate(&stream, Z_NO_FLUSH) }
                let count = chunk.count - Int(stream.avail_out)
                guard count <= min(limits.maxPartBytes, limits.maxExpandedBytes) - result.count else { throw SlideError.limitExceeded("旧XML gzip展開量") }
                result.append(contentsOf: chunk.prefix(count))
                if status == Z_STREAM_END { guard stream.total_in == data.count else { throw SlideError.corruptedPackage("gzip余剰bytes") }; return result }
                guard status == Z_OK, count > 0 || stream.total_in > previous else { throw SlideError.corruptedPackage("gzip破損") }
            }
        }
    }
    package static func isKeynote(_ root: MarkupNode) -> Bool {
        root.name == "presentation" && (root.namespace == "http://developer.apple.com/namespaces/keynote2" || root.namespace.isEmpty)
    }
}
