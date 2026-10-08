// SwiftSheets（MIT、Copyright 2026 Shinichi Nambu）の実装を基に移植。
import Foundation
import SlideCore

package enum OOXMLEncryption {
    package static let encryptionNamespace = "http://schemas.microsoft.com/office/2006/encryption"
    package static let passwordKeyEncryptor = "http://schemas.microsoft.com/office/2006/keyEncryptor/password"
    package static let segmentSize = 4096
    package static let verifierHashInputKey: [UInt8] = [0xFE, 0xA7, 0xD2, 0x76, 0x3B, 0x4B, 0x9E, 0x79]
    package static let verifierHashValueKey: [UInt8] = [0xD7, 0xAA, 0x0F, 0x6D, 0x30, 0x61, 0x34, 0x4E]
    package static let keyValueKey: [UInt8] = [0x14, 0x6E, 0x0B, 0xE7, 0xAB, 0xAC, 0xD0, 0xD6]
    package static let hmacKeyKey: [UInt8] = [0x5F, 0xB2, 0xAD, 0x01, 0x0C, 0xB9, 0xE1, 0xF6]
    package static let hmacValueKey: [UInt8] = [0xA0, 0x67, 0x7F, 0x02, 0xB2, 0x2C, 0x84, 0x33]

    package enum Hash { case sha1, sha256, sha512
        package var size: Int { switch self { case .sha1: 20; case .sha256: 32; case .sha512: 64 } }
        package func hash(_ d: Data) -> Data { switch self { case .sha1: SHA1.hash(d); case .sha256: SHA256.hash(d); case .sha512: SHA512.hash(d) } }
        func hashRound(_ index: [UInt8], _ previous: Data) -> Data {
            func run<S: HashState>(_ state: S.Type) -> Data {
                var s = S()
                index.withUnsafeBytes { s.update($0) }
                s.update(previous)
                return s.finalize()
            }
            switch self { case .sha1: return run(SHA1.State.self); case .sha256: return run(SHA256.State.self); case .sha512: return run(SHA512.State.self) }
        }
        package func hmac(_ m: Data, key: Data) -> Data {
            switch self { case .sha1: HMAC<SHA1>.authenticate(m, key: key); case .sha256: HMAC<SHA256>.authenticate(m, key: key); case .sha512: HMAC<SHA512>.authenticate(m, key: key) }
        }
        init?(name: String) {
            switch name.uppercased() { case "SHA1", "SHA-1": self = .sha1; case "SHA256", "SHA-256": self = .sha256; case "SHA512", "SHA-512": self = .sha512; default: return nil }
        }
        package var name: String { switch self { case .sha1: "SHA1"; case .sha256: "SHA256"; case .sha512: "SHA512" } }
    }

    package struct Parameters {
        package var keyDataSalt = Data(), keyDataHash = Hash.sha512, keyBits = 256, blockSize = 16
        package var encryptedHmacKey: Data?, encryptedHmacValue: Data?
        package var spinCount = 100_000, passwordSalt = Data(), passwordHash = Hash.sha512, passwordKeyBits = 256, passwordBlockSize = 16
        package var encryptedVerifierHashInput = Data(), encryptedVerifierHashValue = Data(), encryptedKeyValue = Data()
        package init() {}
    }


    package static func decrypt(_ compound: Data, password: String, limits: PackageLimits) throws -> Data {
        let file = try CompoundFile(data: compound, limits: limits)
        let info = try file.stream("EncryptionInfo")
        guard info.count >= 8 else { throw SlideError.corruptedPackage("EncryptionInfoが切断されています") }
        let b = [UInt8](info.prefix(8))
        let major = LE.u16(b, 0), minor = LE.u16(b, 2)
        if [2,3,4].contains(major),minor == 2 { return try standard(info,package:file.stream("EncryptedPackage"),password:password,limits:limits) }
        guard major == 4, minor == 4 else {
            throw SlideError.unsupportedEncryption(detail: "OOXML暗号版\(major).\(minor)。Agile 4.4以外の方式です")
        }
        let params = try parse(Data(info.dropFirst(8)), limits: limits)
        let key = try intermediateKey(params, password: password)
        let package = try file.stream("EncryptedPackage")
        try verifyIntegrity(params, key: key, package: package)
        return try decryptPackage(package, key: key, params: params, limit: limits.maxExpandedBytes)
    }

    static func parse(_ xml: Data, limits: PackageLimits) throws -> Parameters {
        let root = try MarkupNode.parse(xml, part: "EncryptionInfo", limits: limits)
        guard root.namespace == encryptionNamespace, root.name == "encryption",
              let kdNode = root.child("keyData", ns: encryptionNamespace),
              let keys = root.child("keyEncryptors", ns: encryptionNamespace) else { throw SlideError.corruptedPackage("EncryptionInfoのroot/必須値が不正") }
        let candidates = keys.children.filter { $0.namespace == encryptionNamespace && $0.name == "keyEncryptor" && $0.attr("uri") == passwordKeyEncryptor }
        guard candidates.count == 1, let ekNode = candidates[0].child("encryptedKey", ns: passwordKeyEncryptor) else { throw SlideError.unsupportedEncryption(detail: "パスワード以外のkey encryptor") }
        let kd = kdNode.attributes, ek = ekNode.attributes
        let integrity = root.child("dataIntegrity", ns: encryptionNamespace)?.attributes
        func base64(_ s: String?, _ what: String) throws -> Data {
            guard let s, let d = Data(base64Encoded: s) else { throw SlideError.corruptedPackage("EncryptionInfoの\(what)がbase64ではありません") }
            return d
        }
        func hash(_ s: String?) throws -> Hash {
            guard let name = s, let h = Hash(name: name) else { throw SlideError.unsupportedEncryption(detail: "暗号hash方式\(s ?? "?")") }
            return h
        }
        func integer(_ attrs:[String:String],_ key:String) throws -> Int {
            guard let raw=attrs[key],let value=Int(raw),value >= 0 else { throw SlideError.corruptedPackage("EncryptionInfoの\(key)が不正です") };return value
        }
        var p = Parameters()
        guard kd["cipherAlgorithm"]?.uppercased() == "AES", ek["cipherAlgorithm"]?.uppercased() == "AES" else { throw SlideError.unsupportedEncryption(detail: "暗号cipher方式\(kd["cipherAlgorithm"] ?? "?")") }
        guard kd["cipherChaining"] == "ChainingModeCBC", ek["cipherChaining"] == "ChainingModeCBC" else { throw SlideError.unsupportedEncryption(detail: "暗号chaining方式\(kd["cipherChaining"] ?? "?")") }
        p.keyDataSalt = try base64(kd["saltValue"], "keyData salt")
        p.keyDataHash = try hash(kd["hashAlgorithm"])
        p.keyBits = try integer(kd,"keyBits")
        p.blockSize = try integer(kd,"blockSize")
        if let i = integrity {
            p.encryptedHmacKey = try base64(i["encryptedHmacKey"], "encryptedHmacKey")
            p.encryptedHmacValue = try base64(i["encryptedHmacValue"], "encryptedHmacValue")
        }
        p.spinCount = try integer(ek,"spinCount")
        guard p.spinCount <= 1_000_000 else { throw SlideError.limitExceeded("EncryptionInfoのhash反復回数") }
        p.passwordSalt = try base64(ek["saltValue"], "password salt")
        p.passwordHash = try hash(ek["hashAlgorithm"])
        p.passwordKeyBits = try integer(ek,"keyBits")
        p.passwordBlockSize = try integer(ek,"blockSize")
        p.encryptedVerifierHashInput = try base64(ek["encryptedVerifierHashInput"], "encryptedVerifierHashInput")
        p.encryptedVerifierHashValue = try base64(ek["encryptedVerifierHashValue"], "encryptedVerifierHashValue")
        p.encryptedKeyValue = try base64(ek["encryptedKeyValue"], "encryptedKeyValue")
        guard [128, 192, 256].contains(p.keyBits), [128, 192, 256].contains(p.passwordKeyBits), p.blockSize == 16, p.passwordBlockSize == 16 else {
            throw SlideError.unsupportedEncryption(detail: "AESの鍵/ブロック長: \(p.keyBits)bit / \(p.blockSize)byte")
        }
        func rounded(_ n:Int) -> Int { (n+15)/16*16 }
        guard try integer(kd,"saltSize") == p.keyDataSalt.count, try integer(ek,"saltSize") == p.passwordSalt.count,
              try integer(kd,"hashSize") == p.keyDataHash.size, try integer(ek,"hashSize") == p.passwordHash.size,
              p.passwordSalt.count == 16, p.keyDataSalt.count == 16,
              p.encryptedVerifierHashInput.count == 16,
              p.encryptedVerifierHashValue.count == rounded(p.passwordHash.size),
              p.encryptedKeyValue.count == rounded(p.keyBits / 8),
              p.encryptedHmacKey == nil || p.encryptedHmacKey?.count == rounded(p.keyDataHash.size),
              p.encryptedHmacValue == nil || p.encryptedHmacValue?.count == rounded(p.keyDataHash.size) else { throw SlideError.corruptedPackage("EncryptionInfoのsalt/hash/暗号値の長さが不正") }
        return p
    }

    package static func passwordHash(_ params: Parameters, password: String) throws -> Data {
        var pw = Data()
        for unit in password.utf16 { pw.append(UInt8(unit & 0xff)); pw.append(UInt8(unit >> 8)) }
        var h = params.passwordHash.hash(params.passwordSalt + pw)
        var index = [UInt8](repeating: 0, count: 4)
        for i in 0..<params.spinCount {
            if i % 256 == 0 { try Task.checkCancellation() }
            index[0] = UInt8(i & 0xff); index[1] = UInt8((i >> 8) & 0xff); index[2] = UInt8((i >> 16) & 0xff); index[3] = UInt8((i >> 24) & 0xff)
            h = params.passwordHash.hashRound(index, h)
        }
        return h
    }

    package static func blockKey(_ params: Parameters, hash: Data, block: [UInt8]) -> Data {
        var k = params.passwordHash.hash(hash + Data(block))
        let size = params.passwordKeyBits / 8
        if k.count < size { k.append(Data(repeating: 0x36, count: size - k.count)) }
        return k.prefix(size)
    }

    package static func iv(_ salt: Data, blockSize: Int) -> Data {
        var v = salt
        if v.count < blockSize { v.append(Data(repeating: 0x36, count: blockSize - v.count)) }
        return v.prefix(blockSize)
    }

    static func intermediateKey(_ params: Parameters, password: String) throws -> Data {
        let h = try passwordHash(params, password: password)
        let iv = iv(params.passwordSalt, blockSize: params.passwordBlockSize)
        let input = try AES(key: blockKey(params, hash: h, block: verifierHashInputKey)).decryptCBC(params.encryptedVerifierHashInput, iv: iv)
        let expected = params.passwordHash.hash(input.prefix(params.passwordSalt.count))
        let stored = try AES(key: blockKey(params, hash: h, block: verifierHashValueKey)).decryptCBC(params.encryptedVerifierHashValue, iv: iv)
        guard stored.prefix(expected.count) == expected else { throw SlideError.wrongPassword }
        let key = try AES(key: blockKey(params, hash: h, block: keyValueKey)).decryptCBC(params.encryptedKeyValue, iv: iv)
        return key.prefix(params.keyBits / 8)
    }

    static func verifyIntegrity(_ params: Parameters, key: Data, package: Data) throws {
        guard let encryptedHmacKey = params.encryptedHmacKey, let encryptedHmacValue = params.encryptedHmacValue else { return }
        let aes = try AES(key: key)
        let hmacKey = try aes.decryptCBC(encryptedHmacKey, iv: iv(params.keyDataHash.hash(params.keyDataSalt + Data(hmacKeyKey)), blockSize: params.blockSize)).prefix(params.keyDataHash.size)
        let stored = try aes.decryptCBC(encryptedHmacValue, iv: iv(params.keyDataHash.hash(params.keyDataSalt + Data(hmacValueKey)), blockSize: params.blockSize)).prefix(params.keyDataHash.size)
        let computed = params.keyDataHash.hmac(package, key: hmacKey)
        guard computed == stored else { throw SlideError.corruptedPackage("暗号packageの整合性検査に失敗しました") }
    }

    static func decryptPackage(_ package: Data, key: Data, params: Parameters, limit: Int) throws -> Data {
        guard package.count >= 8 else { throw SlideError.corruptedPackage("EncryptedPackageが切断されています") }
        let declared = LE.u64([UInt8](package.prefix(8)), 0)
        guard limit >= 0, declared <= UInt64(min(limit,Int.max-15)) else { throw SlideError.limitExceeded("復号packageサイズ") }
        let size = Int(declared)
        let body = package.dropFirst(8)
        guard body.count == (size+15)/16*16 else { throw SlideError.corruptedPackage("EncryptedPackageの宣言長と暗号長が一致しません") }
        let aes = try AES(key: key)
        var out = Data(capacity: size)
        var segment = 0
        var offset = body.startIndex
        while offset < body.endIndex {
            try Task.checkCancellation()
            let end = Swift.min(offset + segmentSize, body.endIndex)
            var index = Data(count: 4)
            index.withUnsafeMutableBytes { $0.storeBytes(of: UInt32(segment).littleEndian, as: UInt32.self) }
            let iv = iv(params.keyDataHash.hash(params.keyDataSalt + index), blockSize: params.blockSize)
            out.append(try aes.decryptCBC(Data(body[offset..<end]), iv: iv))
            offset = end
            segment += 1
        }
        return out.prefix(size)
    }
}
