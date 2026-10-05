import Foundation
import CZlib

package enum Checksum {
    /// 大きなstored partのCRCでも協調キャンセルできる。
    package static func crc(_ data: Data) throws -> UInt32 {
        try data.withUnsafeBytes { bytes in
            var checksum: uLong = 0, offset = 0
            while offset < bytes.count {
                try Task.checkCancellation()
                let count = min(64 << 10, bytes.count - offset)
                checksum = crc32(checksum, bytes.baseAddress!.advanced(by: offset).assumingMemoryBound(to: UInt8.self), uInt(count))
                offset += count
            }
            try Task.checkCancellation()
            return UInt32(checksum)
        }
    }
}
