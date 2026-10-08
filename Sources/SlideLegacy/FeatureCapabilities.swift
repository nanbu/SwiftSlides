// docs/capabilities.jsonから生成。直接編集せずscripts/build-capabilities.pyを使う。
import SlideCore

enum LegacyFeatureCapabilities {
    private static let evidence: [CapabilityEvidence] = [
        .init(id: "R81", fixture: "libreoffice-legacy.ppt", fixtureSHA256: "353123fbce22ce2cd4e5bea0507462d08e609d45c495aee3a9496836cd78c54b", test: "legacyPPTLivePersistOrderAndProducerText", scope: "旧形式の明示codec、寸法・文書順・文字と原本/未知構造。PPTはLibreOffice生成物、XMLは架空合成fixture。"),
        .init(id: "R82", fixture: "legacy-xml.key.zip", fixtureSHA256: "cd0f26ffca665f8220cc603e0e9650cc22b479b71294e2f7d2ce6dad76b80172", test: "legacyXMLDetectionRequiresPresentationAndRetainsUnknown", scope: "旧形式の明示codec、寸法・文書順・文字と原本/未知構造。PPTはLibreOffice生成物、XMLは架空合成fixture。"),
        .init(id: "R83", fixture: "legacy-impress.sxi", fixtureSHA256: "8dbacd8824007151e49b2e419b1a6065be6d02551e7d54a0c830715749e62227", test: "legacyXMLReadOnlyCodecs", scope: "旧形式の明示codec、寸法・文書順・文字と原本/未知構造。PPTはLibreOffice生成物、XMLは架空合成fixture。"),
    ]

    static func features(for format: PresentationFormat) -> [FeatureCapability] {
        switch format {
        case .keynoteLegacy:
            return [
                .init(feature: "PKG-012", profile: .keynoteXML, operation: .read, status: .partial, evidence: [evidence[1]], notes: "読取専用の限定subset。全書式は原本に保持し診断。旧PPTはlive persistとtext record、Keynote2 XML/plain/gzip、SXI旧office XML。暗号・変換・保存なし。"),
                .init(feature: "DOC-001", profile: .keynoteXML, operation: .read, status: .partial, evidence: [evidence[1]], notes: "読取専用の限定subset。全書式は原本に保持し診断。旧PPTはlive persistとtext record、Keynote2 XML/plain/gzip、SXI旧office XML。暗号・変換・保存なし。"),
                .init(feature: "DOC-002", profile: .keynoteXML, operation: .read, status: .partial, evidence: [evidence[1]], notes: "読取専用の限定subset。全書式は原本に保持し診断。旧PPTはlive persistとtext record、Keynote2 XML/plain/gzip、SXI旧office XML。暗号・変換・保存なし。"),
                .init(feature: "TXT-001", profile: .keynoteXML, operation: .read, status: .partial, evidence: [evidence[1]], notes: "読取専用の限定subset。全書式は原本に保持し診断。旧PPTはlive persistとtext record、Keynote2 XML/plain/gzip、SXI旧office XML。暗号・変換・保存なし。"),
            ]
        case .ppt:
            return [
                .init(feature: "PKG-013", profile: .pptBinary, operation: .read, status: .partial, evidence: [evidence[0]], notes: "読取専用の限定subset。全書式は原本に保持し診断。旧PPTはlive persistとtext record、Keynote2 XML/plain/gzip、SXI旧office XML。暗号・変換・保存なし。"),
                .init(feature: "DOC-001", profile: .pptBinary, operation: .read, status: .partial, evidence: [evidence[0]], notes: "読取専用の限定subset。全書式は原本に保持し診断。旧PPTはlive persistとtext record、Keynote2 XML/plain/gzip、SXI旧office XML。暗号・変換・保存なし。"),
                .init(feature: "DOC-002", profile: .pptBinary, operation: .read, status: .partial, evidence: [evidence[0]], notes: "読取専用の限定subset。全書式は原本に保持し診断。旧PPTはlive persistとtext record、Keynote2 XML/plain/gzip、SXI旧office XML。暗号・変換・保存なし。"),
                .init(feature: "TXT-001", profile: .pptBinary, operation: .read, status: .partial, evidence: [evidence[0]], notes: "読取専用の限定subset。全書式は原本に保持し診断。旧PPTはlive persistとtext record、Keynote2 XML/plain/gzip、SXI旧office XML。暗号・変換・保存なし。"),
            ]
        case .sxi:
            return [
                .init(feature: "PKG-014", profile: .impressXML, operation: .read, status: .partial, evidence: [evidence[2]], notes: "読取専用の限定subset。全書式は原本に保持し診断。旧PPTはlive persistとtext record、Keynote2 XML/plain/gzip、SXI旧office XML。暗号・変換・保存なし。"),
                .init(feature: "DOC-001", profile: .impressXML, operation: .read, status: .partial, evidence: [evidence[2]], notes: "読取専用の限定subset。全書式は原本に保持し診断。旧PPTはlive persistとtext record、Keynote2 XML/plain/gzip、SXI旧office XML。暗号・変換・保存なし。"),
                .init(feature: "DOC-002", profile: .impressXML, operation: .read, status: .partial, evidence: [evidence[2]], notes: "読取専用の限定subset。全書式は原本に保持し診断。旧PPTはlive persistとtext record、Keynote2 XML/plain/gzip、SXI旧office XML。暗号・変換・保存なし。"),
                .init(feature: "TXT-001", profile: .impressXML, operation: .read, status: .partial, evidence: [evidence[2]], notes: "読取専用の限定subset。全書式は原本に保持し診断。旧PPTはlive persistとtext record、Keynote2 XML/plain/gzip、SXI旧office XML。暗号・変換・保存なし。"),
            ]
        default: return []
        }
    }
}
