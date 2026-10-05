// docs/capabilities.jsonから生成。直接編集せずscripts/build-capabilities.pyを使う。
import SlideCore

enum ODPFeatureCapabilities {
    private static let evidence: [CapabilityEvidence] = [
        .init(id: "E24", fixture: "styles.odp", fixtureSHA256: "04257a783591daad3e5ea1d700ad590727eaa22812663ee0c6edb780bf6301b0", test: "odpBasicReadPreservesOriginalAndSeparatesInheritedValues", scope: "ODF 1.3架空fixtureのページ寸法、本文・空白・tab・リンク、automatic直接書式、画像bytes、表表示文字、notesを照合。外観・保存は対象外。"),
        .init(id: "E25", fixture: "styles.odp", fixtureSHA256: "04257a783591daad3e5ea1d700ad590727eaa22812663ee0c6edb780bf6301b0", test: "odpStylesResolveDirectNamedAutomaticAndMaster", scope: "familyとautomatic scopeを分離しdefault/named parent/master/direct propertyの値と出典を照合。placeholder外観は対象外。"),
        .init(id: "E26", fixture: "libreoffice.odp", fixtureSHA256: "1e84faf264b006b6e9a817858c33a35c8d347815b69c699e95c9cfc9b1cf7857", test: "libreOfficeODPProducerIsReadableWithLocatedWarnings", scope: "LibreOffice 26.2.3.2が架空PPTXから生成した2枚のODF 1.4で本文とnotesを照合。custom geometryはopaqueの表示文字投影。外観は未検証。"),
    ]

    static func features(for format: PresentationFormat) -> [FeatureCapability] {
        switch format {
        case .odp:
            return [
                .init(feature: "DOC-001", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[0]], notes: "指定ODF 1.3 fixtureで基本値を投影。named/master継承を直接値へ埋めない。書込と外観は未提供。"),
                .init(feature: "DOC-009", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[0]], notes: "指定ODF 1.3 fixtureで基本値を投影。named/master継承を直接値へ埋めない。書込と外観は未提供。"),
                .init(feature: "TXT-001", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[0]], notes: "指定ODF 1.3 fixtureで基本値を投影。named/master継承を直接値へ埋めない。書込と外観は未提供。"),
                .init(feature: "TXT-003", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[0]], notes: "指定ODF 1.3 fixtureで基本値を投影。named/master継承を直接値へ埋めない。書込と外観は未提供。"),
                .init(feature: "IMG-001", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[0]], notes: "指定ODF 1.3 fixtureで基本値を投影。named/master継承を直接値へ埋めない。書込と外観は未提供。"),
                .init(feature: "STY-007", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[1]], notes: "default/named/automatic/drawing-page masterのpropertyと出典の限定解決。placeholder・外観・編集は対象外。"),
                .init(feature: "STY-008", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[1]], notes: "default/named/automatic/drawing-page masterのpropertyと出典の限定解決。placeholder・外観・編集は対象外。"),
                .init(feature: "STY-010", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[1]], notes: "default/named/automatic/drawing-page masterのpropertyと出典の限定解決。placeholder・外観・編集は対象外。"),
                .init(feature: "TXT-001", profile: .odf14, operation: .read, status: .partial, evidence: [evidence[2]], notes: "LibreOffice生成の指定fixtureで本文・notesを確認。ODF 1.4全要素への対応を意味しない。"),
                .init(feature: "DOC-009", profile: .odf14, operation: .read, status: .partial, evidence: [evidence[2]], notes: "LibreOffice生成の指定fixtureで本文・notesを確認。ODF 1.4全要素への対応を意味しない。"),
            ]
        default: return []
        }
    }
}
