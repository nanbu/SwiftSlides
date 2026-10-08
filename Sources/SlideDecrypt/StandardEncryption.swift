import Foundation
import SlideCore

extension OOXMLEncryption {
    static func standard(_ info:Data,package:Data,password:String,limits:PackageLimits) throws -> Data {
        let b=[UInt8](info)
        guard b.count >= 12 else { throw SlideError.corruptedPackage("Standard EncryptionInfo切断") }
        let length=Int(LE.u32(b,8))
        guard length >= 34,length <= b.count-12, (length-32)%2 == 0 else { throw SlideError.corruptedPackage("Standard header長不正") }
        let flags=LE.u32(b,12),alg=LE.u32(b,20),hash=LE.u32(b,24),bits=Int(LE.u32(b,28)),v=12+length
        guard flags & 0x3c == 0x24,LE.u32(b,4) & 0x3c == 0x24,[0,0x8004].contains(hash),[0,0x660e,0x660f,0x6610].contains(alg) else { throw SlideError.unsupportedEncryption(detail: "StandardのAES/SHA-1以外の方式") }
        let expected=alg == 0x660f ? 192 : alg == 0x6610 ? 256 : 128,keyBits=bits == 0 ? 128 : bits
        guard keyBits == expected,LE.u32(b,16) == 0,LE.u16(b,12+length-2) == 0,b.count-v == 72 else { throw SlideError.corruptedPackage("Standard鍵/header/verifier不整合") }
        guard LE.u32(b,v) == 16,LE.u32(b,v+36) == 20 else { throw SlideError.corruptedPackage("Standard verifier salt/hash長不正") }
        var params=Parameters();params.passwordSalt=Data(b[v+4..<v+20]);params.passwordHash = .sha1;params.spinCount=50_000
        let final=SHA1.hash(try passwordHash(params,password:password)+Data(repeating:0,count:4))
        func derive(_ byte:UInt8) -> Data {
            var input=Data(repeating:byte,count:64)
            for i in final.indices { input[i] ^= final[i] };return SHA1.hash(input)
        }
        let key=Data((derive(0x36)+derive(0x5c)).prefix(keyBits/8)),aes=try AES(key:key)
        let verifier=try aes.decryptECB(Data(b[v+20..<v+36]))
        let stored=try aes.decryptECB(Data(b[v+40..<v+72]))
        guard SHA1.hash(verifier) == stored.prefix(20) else { throw SlideError.wrongPassword }
        guard package.count >= 8 else { throw SlideError.corruptedPackage("Standard package切断") }
        let size=LE.u64([UInt8](package.prefix(8)),0)
        guard size <= UInt64(min(limits.maxExpandedBytes,Int.max-15)) else { throw SlideError.limitExceeded("Standard復号サイズ") }
        guard package.count-8 == (Int(size)+15)/16*16 else { throw SlideError.corruptedPackage("Standard package長不整合") }
        return try Data(aes.decryptECB(Data(package.dropFirst(8))).prefix(Int(size)))
    }
}
