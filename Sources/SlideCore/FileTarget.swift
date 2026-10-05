import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// エンコード済Dataを分割してatomic保存するsink。エンコード自体はstreamingではない。
public struct FileTarget: Sendable {
    public let url: URL
    public init(_ url: URL) { self.url = url }
    /// 一時fileへの書込・fsyncが成功した後にrenameで確定する。
    public func write(_ data: Data) throws { try write(data,beforeChunk:nil,beforeCommit:nil) }
    @concurrent public func write(_ data: Data) async throws { try writeSync(data) }
    private func writeSync(_ data: Data) throws { try write(data) }
    // 操作ローカルの障害注入。global stateや環境変数は使わない。
    package func write(_ data: Data, beforeChunk: ((Int) throws -> Void)?, beforeCommit: (() throws -> Void)?) throws {
        try Task.checkCancellation()
        guard url.isFileURL, !url.lastPathComponent.isEmpty else { throw SlideError.invalidModel("FileTargetにはfile URLが必要です") }
        let destination = url.path
        let template = url.deletingLastPathComponent().appendingPathComponent(".swiftslides-XXXXXX").path
        var chars = Array(template.utf8CString)
        let fd = mkstemp(&chars)
        guard fd >= 0 else { throw Self.ioError() }
        let temporary = String(decoding:chars.prefix { $0 != 0 }.map { UInt8(bitPattern:$0) },as:UTF8.self)
        var committed = false
        defer { _ = close(fd); if !committed { _ = unlink(temporary) } }
        // 既存fileのpermissionだけを維持。ACL/xattrの転送は契約に含めない。
        var info = stat()
        if lstat(destination,&info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) {
            guard fchmod(fd,info.st_mode & 0o777) == 0 else { throw Self.ioError() }
        }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                try Task.checkCancellation(); try beforeChunk?(offset)
                let amount = min(64 << 10,bytes.count-offset)
                #if canImport(Darwin)
                let written = Darwin.write(fd,bytes.baseAddress!.advanced(by:offset),amount)
                #else
                let written = Glibc.write(fd,bytes.baseAddress!.advanced(by:offset),amount)
                #endif
                if written < 0 { if errno == EINTR { continue }; throw Self.ioError() }
                guard written > 0 else { throw POSIXError(.EIO) }
                offset += written
            }
        }
        try Task.checkCancellation()
        guard fsync(fd) == 0 else { throw Self.ioError() }
        try beforeCommit?(); try Task.checkCancellation()
        guard rename(temporary,destination) == 0 else { throw Self.ioError() }
        committed = true
        // rename後は成功として返す。directory fsyncによる停電耐性は保証しない。
    }
    private static func ioError() -> POSIXError { POSIXError(POSIXErrorCode(rawValue:errno) ?? .EIO) }
}
