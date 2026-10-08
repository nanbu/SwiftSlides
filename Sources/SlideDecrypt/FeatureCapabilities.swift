// docs/capabilities.jsonから生成。直接編集せずscripts/build-capabilities.pyを使う。
import SlideCore

enum DecryptFeatureCapabilities {
    private static let evidence: [CapabilityEvidence] = [
        .init(id: "E51", fixture: "encrypted-agile-128.pptx", fixtureSHA256: "d22c6c11b8b907ffb3f168f5b6cda2b0146a8de8679990a47c3b52f821e00325", test: "agilePasswordsAndIntegrity", scope: "Python cryptography/hashlibで独立生成。Unicode password、平文byte一致、誤password/破損/上限拒否。StandardはHMACなし。"),
        .init(id: "E52", fixture: "encrypted-agile-192.pptx", fixtureSHA256: "16c071bd930c02e9511ceeb76118bb8669b1cd26c3ae82368cc1718612c5bcd6", test: "agilePasswordsAndIntegrity", scope: "Python cryptography/hashlibで独立生成。Unicode password、平文byte一致、誤password/破損/上限拒否。StandardはHMACなし。"),
        .init(id: "E53", fixture: "encrypted-agile-256.pptx", fixtureSHA256: "9e4d96e5a7e6ebfb8382e85b0a037b223ff0a6b2205690801841d178cf307399", test: "agilePasswordsAndIntegrity", scope: "Python cryptography/hashlibで独立生成。Unicode password、平文byte一致、誤password/破損/上限拒否。StandardはHMACなし。"),
        .init(id: "E54", fixture: "encrypted-standard-128.pptx", fixtureSHA256: "d0ccca9b46eb7d2cd42e37a3ae1b3b5c9b4b35a823bb6dca382264a9500a36d9", test: "standardPasswordsAndHeaderValidation", scope: "Python cryptography/hashlibで独立生成。Unicode password、平文byte一致、誤password/破損/上限拒否。StandardはHMACなし。"),
        .init(id: "E55", fixture: "encrypted-standard-192.pptx", fixtureSHA256: "a03eda8518beaca30b38fe5eb069d9c8fc1a444c49cd4f8503c9acc8729b925c", test: "standardPasswordsAndHeaderValidation", scope: "Python cryptography/hashlibで独立生成。Unicode password、平文byte一致、誤password/破損/上限拒否。StandardはHMACなし。"),
        .init(id: "E56", fixture: "encrypted-standard-256.pptx", fixtureSHA256: "38a49318f2b54533fbedc8574ae9f224ffe3fe1260359cd3f8c98abfb5daf4c7", test: "standardPasswordsAndHeaderValidation", scope: "Python cryptography/hashlibで独立生成。Unicode password、平文byte一致、誤password/破損/上限拒否。StandardはHMACなし。"),
        .init(id: "E57", fixture: "encrypted-aes-128.odp", fixtureSHA256: "36b62ebc54f9bebe8da1be2618040f44bcb8e1e46c0ebfcd375ac5965e1962cf", test: "odpPasswordsAndPlaintextSnapshot", scope: "Python cryptographyで独立AES/PBKDF2暗号化。復号content.xml byte一致、誤password、KDF不正拒否。"),
        .init(id: "E58", fixture: "encrypted-aes-256.odp", fixtureSHA256: "ef364993c8e958af093b28309d2f3cff124f1c7e36aadfd2ddeb2ad16bebab21", test: "odpPasswordsAndPlaintextSnapshot", scope: "Python cryptographyで独立AES/PBKDF2暗号化。復号content.xml byte一致、誤password、KDF不正拒否。"),
        .init(id: "E59", fixture: "encrypted-native.keynote.zip", fixtureSHA256: "ef48f33bde382f137d749b604ba5cf3acfbc3e4abe522c8a8119ec7e08ccb10c", test: "keynotePasswordVerifierPaddingAndUnknownProtection", scope: "独立PBKDF2/AES生成。password検証、padding/版の拒否、IWA索引読取。末尾20bytesの認証を含まない。"),
    ]

    static func features(for format: PresentationFormat) -> [FeatureCapability] {
        switch format {
        case .keynote:
            return [
                .init(feature: "SEC-003", profile: .keynoteIWA, operation: .read, status: .partial, evidence: [evidence[8]], notes: "iwpv2 version2/format1、PBKDF2SHA1/AES128CBC。現行15.4の架空producerでも照合。末尾20bytes未解釈、再暗号化なし。"),
            ]
        case .odp:
            return [
                .init(feature: "SEC-002", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[6], evidence[7]], notes: "AES-CBC/PBKDF2、SHA1/SHA256 start、SHA1/1K等のchecksum。Blowfish/再暗号化なし。"),
            ]
        case .pptx:
            return [
                .init(feature: "SEC-001", profile: .ooxmlAgile, operation: .read, status: .partial, evidence: [evidence[0], evidence[1], evidence[2]], notes: "復号専用製品。AES128/192/256。AgileはSHA1/256/512とHMAC、StandardはSHA1/ECB。証明書/IRM/RC4/再暗号化なし。"),
                .init(feature: "SEC-001", profile: .ooxmlStandard, operation: .read, status: .partial, evidence: [evidence[3], evidence[4], evidence[5]], notes: "復号専用製品。AES128/192/256。AgileはSHA1/256/512とHMAC、StandardはSHA1/ECB。証明書/IRM/RC4/再暗号化なし。"),
            ]
        default: return []
        }
    }
}
