import Foundation
import SlideCore
import CZlib

package enum ODPEncryption {
    static let ns = "urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"
    static func decrypt(_ archive: PackageArchive, password: String, limits: PackageLimits) throws -> Data? {
        guard archive.entries["META-INF/manifest.xml"] != nil else { return nil }
        let path = "META-INF/manifest.xml", root = try MarkupNode.parse(archive.read(path),part:path,limits:limits)
        guard root.namespace == ns, root.name == "manifest" else { throw SlideError.corruptedPackage("ODF manifest不正") }
        var entries: [(String, Int, MarkupNode)] = [], seen = Set<String>(), total = 0, rounds = 0
        func attr(_ n: MarkupNode, _ key: String) -> String? { n.attr(ns + "|" + key) }
        for n in root.children where n.namespace == ns && n.name == "file-entry" {
            guard let name = attr(n,"full-path"), seen.insert(name).inserted else { throw SlideError.corruptedPackage("ODF manifestパス重複") }
            if let enc = n.child("encryption-data",ns:ns) {
                guard name != "mimetype", name != path, archive.entries[name] != nil, let size = attr(n,"size").flatMap(Int.init), size >= 0 else { throw SlideError.corruptedPackage("暗号ODF entry不正") }
                guard size <= limits.maxPartBytes, size <= limits.maxExpandedBytes-total else { throw SlideError.limitExceeded("ODF復号展開量") }; total += size
                guard let count = enc.child("key-derivation",ns:ns).flatMap({ attr($0,"iteration-count") }).flatMap(Int.init) else { throw SlideError.corruptedPackage("ODF KDF回数不正") }
                guard count > 0, count <= 1_000_000, rounds <= 10_000_000-count else { throw SlideError.limitExceeded("ODF KDF回数") }; rounds += count
                entries.append((name,size,enc))
            } else if let entry = archive.entries[name] {
                guard entry.expandedSize <= limits.maxExpandedBytes-total else { throw SlideError.limitExceeded("ODF全展開量") }; total += entry.expandedSize
            }
        }
        for name in archive.paths where !seen.contains(name) {
            let entry=archive.entries[name]!
            guard entry.expandedSize <= limits.maxExpandedBytes-total else { throw SlideError.limitExceeded("ODF全展開量") };total += entry.expandedSize
        }
        guard !entries.isEmpty else { return nil }
        var parts: [String:Data] = [:]
        for name in archive.paths where !name.hasSuffix("/") { parts[name] = try archive.read(name) }
        for (name,size,enc) in entries {
            try Task.checkCancellation()
            parts[name] = try entry(parts[name]!,size:size,enc:enc,password:password)
        }
        for n in root.children { n.content.removeAll { if case .node(let c) = $0 { c.namespace == ns && c.name == "encryption-data" } else { false } } }
        parts[path] = Data(root.xml.utf8)
        return try ZIPWriter.write(parts,compress:false)
    }
    private static func entry(_ cipher: Data, size: Int, enc: MarkupNode, password: String) throws -> Data {
        func attr(_ node: MarkupNode?, _ name: String) -> String? { node?.attr(ns + "|" + name) }
        func binary(_ value: String?) throws -> Data { guard let value, let bytes = Data(base64Encoded:value) else { throw SlideError.corruptedPackage("ODF暗号base64不正") }; return bytes }
        let algorithm = enc.child("algorithm",ns:ns), derivation = enc.child("key-derivation",ns:ns), generation = enc.child("start-key-generation",ns:ns)
        let names = ["http://www.w3.org/2001/04/xmlenc#aes128-cbc":16,"http://www.w3.org/2001/04/xmlenc#aes192-cbc":24,"http://www.w3.org/2001/04/xmlenc#aes256-cbc":32]
        guard let name = attr(algorithm,"algorithm-name"), let expected = names[name], attr(derivation,"key-derivation-name") == "PBKDF2" else { throw SlideError.unsupportedEncryption(detail: "ODFのAES-CBC/PBKDF2以外の方式") }
        func integer(_ raw:String?,default value:Int) throws -> Int { guard let raw else { return value };guard let n=Int(raw),n > 0 else { throw SlideError.corruptedPackage("ODF暗号整数不正") };return n }
        let keySize = try integer(attr(derivation,"key-size"),default:expected)
        guard keySize == expected else { throw SlideError.corruptedPackage("ODF暗号鍵サイズ不一致") }
        let salt = try binary(attr(derivation,"salt")), iv = try binary(attr(algorithm,"initialisation-vector"))
        guard iv.count == 16, !salt.isEmpty, salt.count <= 64 else { throw SlideError.corruptedPackage("ODFのsalt/IV長不正") }
        let start: Data
        switch attr(generation,"start-key-generation-name") {
        case "http://www.w3.org/2000/09/xmldsig#sha1", nil: start = SHA1.hash(Data(password.utf8))
        case "http://www.w3.org/2000/09/xmldsig#sha256", "http://www.w3.org/2001/04/xmlenc#sha256": start = SHA256.hash(Data(password.utf8))
        default: throw SlideError.unsupportedEncryption(detail: "ODF start-key hash")
        }
        let startSize = try integer(attr(generation,"key-size"),default:start.count)
        guard startSize > 0, startSize <= start.count else { throw SlideError.corruptedPackage("ODF start-keyサイズ不正") }
        let rounds = try integer(attr(derivation,"iteration-count"),default:1024)
        let key = try PBKDF2<SHA1>.derive(password:Data(start.prefix(startSize)),salt:salt,iterations:rounds,length:keySize)
        var plain = try AES(key:key).decryptCBC(cipher,iv:iv)
        guard let padding = plain.last, padding >= 1, padding <= 16, plain.count >= Int(padding) else { throw SlideError.wrongPassword }
        plain = Data(plain.prefix(plain.count-Int(padding)))
        let computed: Data
        switch attr(enc,"checksum-type") {
        case "http://www.w3.org/2000/09/xmldsig#sha1-1k", "SHA1/1K": computed = SHA1.hash(Data(plain.prefix(1024)))
        case "http://www.w3.org/2000/09/xmldsig#sha256-1k", "http://www.w3.org/2001/04/xmlenc#sha256-1k": computed = SHA256.hash(Data(plain.prefix(1024)))
        default: throw SlideError.unsupportedEncryption(detail: "ODF checksum")
        }
        guard computed == (try binary(attr(enc,"checksum"))) else { throw SlideError.wrongPassword }
        return try inflate(plain,size:size)
    }
    private static func inflate(_ input: Data, size: Int) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream,-MAX_WBITS,ZLIB_VERSION,Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw SlideError.corruptedPackage("ODF inflate初期化") }
        defer { inflateEnd(&stream) }
        var out = Data(count:max(1,size))
        try input.withUnsafeBytes { src in try out.withUnsafeMutableBytes { dst in
            stream.next_in=UnsafeMutablePointer(mutating:src.baseAddress!.assumingMemoryBound(to:UInt8.self)); stream.avail_in=uInt(src.count)
            var status:Int32=Z_OK
            while status != Z_STREAM_END {
                try Task.checkCancellation()
                let offset=Int(stream.total_out)
                guard offset < dst.count else { throw SlideError.corruptedPackage("ODF復号サイズ超過") }
                stream.next_out=dst.baseAddress!.advanced(by:offset).assumingMemoryBound(to:UInt8.self); stream.avail_out=uInt(min(64<<10,dst.count-offset))
                let before=stream.total_in; status=CZlib.inflate(&stream,Z_NO_FLUSH)
                guard (status == Z_OK || status == Z_STREAM_END), stream.total_in != before || Int(stream.total_out) != offset else { throw SlideError.corruptedPackage("ODF復号DEFLATE不正") }
            }
            guard stream.total_out == size, stream.total_in == src.count else { throw SlideError.corruptedPackage("ODF復号サイズ不一致") }
        } }
        out.count=size; return out
    }
}
