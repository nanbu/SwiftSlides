import Foundation
import SlideCore

// iWorkFileFormatの一次解析に示されたstream構造。アプリ固有の末尾20bytesは未解釈。
package enum KeynoteEncryption {
    static func decrypt(_ archive:PackageArchive,password:String,limits:PackageLimits) throws -> Data {
        let header=try archive.read(".iwpv2"),b=[UInt8](header)
        guard b.count == 104 else { throw SlideError.corruptedPackage("Keynote .iwpv2長不正") }
        guard LE.u16(b,0) == 2,LE.u16(b,2) == 1 else { throw SlideError.unsupportedEncryption(detail: "Keynote .iwpv2版/方式") }
        let rounds=Int(LE.u32(b,4))
        guard rounds > 0,rounds <= 1_000_000 else { throw SlideError.limitExceeded("Keynote KDF回数") }
        let key=try PBKDF2<SHA1>.derive(password:Data(password.utf8),salt:Data(b[8..<24]),iterations:rounds,length:16),aes=try AES(key:key)
        let verifier=try aes.decryptCBC(Data(b[40..<104]),iv:Data(b[24..<40]))
        guard SHA256.hash(Data(verifier.prefix(32))) == verifier.suffix(32) else { throw SlideError.wrongPassword }
        var parts:[String:Data]=[:],total=0
        for path in archive.paths where !path.hasSuffix("/") && path != ".iwpv2" && path != ".iwph" {
            try Task.checkCancellation()
            let input=try archive.read(path)
            let encrypted=path.hasPrefix("Index/") || path.hasPrefix("Data/") || path == "Index.zip" || path == "Metadata/BuildVersionHistory.plist"
            let value:Data
            if encrypted {
                guard input.count >= 68,(input.count-36)%16 == 0 else { throw SlideError.corruptedPackage("Keynote暗号stream長不正: \(path)") }
                let raw=try aes.decryptCBC(Data(input.dropFirst(16).dropLast(20)),iv:Data(input.prefix(16)))
                guard let n=raw.last,n > 0,n <= 16,raw.count-Int(n) >= 16,raw.suffix(Int(n)).allSatisfy({ $0 == n }) else { throw SlideError.corruptedPackage("Keynote暗号padding不正: \(path)") }
                value=Data(raw.dropFirst(16).dropLast(Int(n)))
            } else { value=input }
            guard value.count <= limits.maxPartBytes,value.count <= limits.maxExpandedBytes-total else { throw SlideError.limitExceeded("Keynote復号展開量") };total += value.count;parts[path]=value
        }
        guard parts["Index/Document.iwa"] != nil || parts["Index.zip"] != nil else { throw SlideError.corruptedPackage("Keynote復号後のIndexなし") }
        return try ZIPWriter.write(parts,compress:false)
    }
}
