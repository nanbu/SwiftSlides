// docs/capabilities.jsonから生成。直接編集せずscripts/build-capabilities.pyを使う。
import SlideCore

enum PPTXFeatureCapabilities {
    private static let evidence: [CapabilityEvidence] = [
        .init(id: "E01", fixture: "python-pptx.pptx", fixtureSHA256: "de176a193e19d3670670e36b2f29c6301ad6d444083e61416d3e631985418d40", test: "independentProducerOracle", scope: "python-pptxが生成・再読した期待値と本文、直接フォント、段落、リンクを比較。実効外観は含まない。"),
        .init(id: "E02", fixture: "strict.pptx", fixtureSHA256: "d2faa745a19ec87aa7e906599c6bf07357dd669fc3ca09245acec2156607d941", test: "readContainers", scope: "python-pptx由来fixtureの名前空間をStrictへ置換した資料。2枚の順序と本文を確認。Strict producerや全スキーマの検証ではない。"),
        .init(id: "E03", fixture: "python-pptx.pptx", fixtureSHA256: "de176a193e19d3670670e36b2f29c6301ad6d444083e61416d3e631985418d40", test: "geometryImagesGroupsTablesAndNotes", scope: "図形座標、非結合表のセル本文、画像bytes、グループ、ノートを確認。"),
        .init(id: "E04", fixture: "python-pptx.pptx", fixtureSHA256: "de176a193e19d3670670e36b2f29c6301ad6d444083e61416d3e631985418d40", test: "opaqueChartIsWarnedAndPreserved", scope: "棒チャートのgraphicFrameをopaqueとして読み、元XMLと警告を確認。チャートの意味モデルは作らない。"),
        .init(id: "E05", fixture: "python-pptx.pptx", fixtureSHA256: "de176a193e19d3670670e36b2f29c6301ad6d444083e61416d3e631985418d40", test: "noOpIsByteIdentical", scope: "指定fixtureの未変更保存が入力全bytesと一致することを確認。編集保存の任意依存は検証しない。"),
        .init(id: "E06", fixture: "strict.pptx", fixtureSHA256: "d2faa745a19ec87aa7e906599c6bf07357dd669fc3ca09245acec2156607d941", test: "noOpIsByteIdentical", scope: "指定fixtureの未変更保存が入力全bytesと一致することを確認。編集保存の任意依存は検証しない。"),
        .init(id: "E07", fixture: "macro.pptm", fixtureSHA256: "4ad887cd5337aa89f666766bc6bf69c834c2d0ebb153960b92a5c4d56c52846c", test: "noOpIsByteIdentical", scope: "指定fixtureの未変更保存が入力全bytesと一致することを確認。編集保存の任意依存は検証しない。"),
        .init(id: "E08", fixture: "unknown.pptx", fixtureSHA256: "742580bb39cc77a600330c3628ff08b067a1fdfec6d24e7551faf69567addbbe", test: "noOpIsByteIdentical", scope: "指定fixtureの未変更保存が入力全bytesと一致することを確認。編集保存の任意依存は検証しない。"),
        .init(id: "E09", fixture: "unknown.pptx", fixtureSHA256: "742580bb39cc77a600330c3628ff08b067a1fdfec6d24e7551faf69567addbbe", test: "editTextPreservesOtherPartsAndNamespaces", scope: "本文1箇所を書き換え、無関係の圧縮済パーツ、未知拡張XML、namespaceを保持。書換え警告とstrict拒否を確認。"),
        .init(id: "E10", fixture: "strict.pptx", fixtureSHA256: "d2faa745a19ec87aa7e906599c6bf07357dd669fc3ca09245acec2156607d941", test: "strictNamespaceEdit", scope: "既存要素のy座標変更と本文保持を再読で確認。Strictでの新規スライド追加は含まない。"),
        .init(id: "E11", fixture: "python-pptx.pptx", fixtureSHA256: "de176a193e19d3670670e36b2f29c6301ad6d444083e61416d3e631985418d40", test: "frameEditPreservesRichTextAndChart", scope: "既知テキスト図形のx座標だけを変更し、rich textと別スライドのチャートXMLを保持。"),
        .init(id: "E12", fixture: "macro.pptm", fixtureSHA256: "4ad887cd5337aa89f666766bc6bf69c834c2d0ebb153960b92a5c4d56c52846c", test: "macrosPreserved", scope: "metadata編集後に架空の非実行VBA bytesが一致することと、PPTXへの暗黙変換拒否を確認。実マクロ動作は未検証。"),
        .init(id: "E13", fixture: "python-pptx.pptx", fixtureSHA256: "de176a193e19d3670670e36b2f29c6301ad6d444083e61416d3e631985418d40", test: "editedImageRetainsPackage", scope: "既存画像を架空PNG bytesと代替文へ差し替え、保存後の代替文を再読で確認。"),
        .init(id: "E14", fixture: "python-pptx.pptx", fixtureSHA256: "de176a193e19d3670670e36b2f29c6301ad6d444083e61416d3e631985418d40", test: "signedPackageOnlyNoOpAllowed", scope: "fixtureに架空署名パーツを追加し、未変更全bytes一致を確認。暗号署名のvalidityは未検証。"),
        .init(id: "E15", fixture: "python-pptx.pptx", fixtureSHA256: "de176a193e19d3670670e36b2f29c6301ad6d444083e61416d3e631985418d40", test: "signedPackageOnlyNoOpAllowed", scope: "fixtureに架空署名パーツを追加し、metadata編集保存の拒否を確認。"),
        .init(id: "E16", fixture: "python-pptx.pptx", fixtureSHA256: "de176a193e19d3670670e36b2f29c6301ad6d444083e61416d3e631985418d40", test: "opaqueMutationAndThemeMutationRefused", scope: "チャートopaque要素の位置変更と既存テーマの変更をそれぞれ拒否することを確認。"),
        .init(id: "E17", fixture: "fixture.png", fixtureSHA256: "b2570ba9eea72bc56a277aca4f7dce333a815bcf68c1407683576579a93e88f9", test: "createRichPresentation", scope: "新規文字・図形・画像・非結合表・ノートを生成してSwiftSlidesで再読。画像入力は架空の1pixel PNG。実アプリ検証の証拠ではない。"),
        .init(id: "E18", fixture: "python-pptx.pptx", fixtureSHA256: "de176a193e19d3670670e36b2f29c6301ad6d444083e61416d3e631985418d40", test: "inventoryListsLocatedReferencesAndIdentities", scope: "fixtureにtimingと架空の未知参照を追加し、位置・原本identity・既知/未知を確認。全形式の依存解釈ではない。"),
        .init(id: "E19", fixture: "python-pptx.pptx", fixtureSHA256: "de176a193e19d3670670e36b2f29c6301ad6d444083e61416d3e631985418d40", test: "savePlanCopiesOriginalAndLocatesPatch", scope: "未変更計画のbyte一致とcopy actions、既存要素の位置変更のpatch計画・再読を検査。出力Dataを計画時に生成する。"),
        .init(id: "E20", fixture: "python-pptx.pptx", fixtureSHA256: "de176a193e19d3670670e36b2f29c6301ad6d444083e61416d3e631985418d40", test: "duplicatePreservesNotesChartAssetsAndLocalReferences", scope: "notes/chart/embedded Workbookを独立partへ複製し、画像共有、原本圧縮payload保持、独立notes編集を確認。チャートの新規生成・再計算ではない。"),
        .init(id: "E21", fixture: "python-pptx.pptx", fixtureSHA256: "de176a193e19d3670670e36b2f29c6301ad6d444083e61416d3e631985418d40", test: "importRebasesMasterAssetsAndRequiresSlideLinkMapping", scope: "fixtureのrun linkを別slideへ変更し、新規文書へimport。明示対応表、layout/master/assetsの移植、notes、保存計画とstale拒否を確認。"),
        .init(id: "E22", fixture: "strict.pptx", fixtureSHA256: "d2faa745a19ec87aa7e906599c6bf07357dd669fc3ca09245acec2156607d941", test: "cloneRefusesUnknownConflictingMastersAndProfiles", scope: "名前空間をStrictへ変更したfixture内の1枚複製を再読。Strict producerやStrict新規生成の証拠ではない。"),
        .init(id: "E23", fixture: "macro.pptm", fixtureSHA256: "4ad887cd5337aa89f666766bc6bf69c834c2d0ebb153960b92a5c4d56c52846c", test: "macroDuplicatePreservesVBAAndCloneCancellationIsAtomic", scope: "架空VBAを持つPPTMの同文書内複製と元VBA圧縮payload保持。マクロの実行・別資料取り込みは行わない。"),
    ]

    static func features(for format: PresentationFormat) -> [FeatureCapability] {
        switch format {
        case .pptm:
            return [
                .init(feature: "IO-008", profile: .ooxmlTransitional, operation: .preserve, status: .supported, evidence: [evidence[6]], notes: "未変更保存に限って全bytes一致。編集保存の可否は別に検査する。"),
                .init(feature: "SEC-005", profile: .ooxmlTransitional, operation: .edit, status: .preserveOnly, evidence: [evidence[11]], notes: "metadata変更時に元VBA bytesを保持。実マクロの解釈・実行・新規生成・除去は提供しない。"),
                .init(feature: "SEC-005", profile: .ooxmlTransitional, operation: .preserve, status: .partial, evidence: [evidence[6]], notes: "架空VBAパーツを未変更で全bytes保持。実マクロの動作を証明しない。"),
                .init(feature: "DOC-004", profile: .ooxmlTransitional, operation: .edit, status: .partial, evidence: [evidence[22]], notes: "同文書内の複製とVBA原本保持。別資料へのマクロ移植は拒否。"),
            ]
        case .pptx:
            return [
                .init(feature: "TXT-001", profile: .ooxmlTransitional, operation: .read, status: .partial, evidence: [evidence[0]], notes: "Unicode本文の直接値。高度な文字制御は未検証。"),
                .init(feature: "TXT-003", profile: .ooxmlTransitional, operation: .read, status: .partial, evidence: [evidence[0]], notes: "直接font family/sizeと一部書式。継承フォント・言語全体は未解決。"),
                .init(feature: "TXT-008", profile: .ooxmlTransitional, operation: .read, status: .partial, evidence: [evidence[0]], notes: "直接指定の段落alignment。全indent/margin条件は未検証。"),
                .init(feature: "PKG-004", profile: .ooxmlTransitional, operation: .read, status: .partial, evidence: [evidence[0]], notes: "Transitional fixtureの読取。全schema互換性の保証ではない。"),
                .init(feature: "PKG-004", profile: .ooxmlStrict, operation: .read, status: .partial, evidence: [evidence[1]], notes: "名前空間変種の基本本文読取。未検証のStrict機能は含まない。"),
                .init(feature: "IMG-001", profile: .ooxmlTransitional, operation: .read, status: .partial, evidence: [evidence[2]], notes: "埋込PNGの参照と必要時bytes展開。全画像形式の描画は未検証。"),
                .init(feature: "TBL-001", profile: .ooxmlTransitional, operation: .read, status: .partial, evidence: [evidence[2]], notes: "非結合表のセル読取。高度なtable styleは未解決。"),
                .init(feature: "OBJ-011", profile: .ooxmlTransitional, operation: .read, status: .partial, evidence: [evidence[3]], notes: "チャートをopaque要素として位置・元XML・警告付きで読取。意味は未解釈。"),
                .init(feature: "CHT-001", profile: .ooxmlTransitional, operation: .read, status: .preserveOnly, evidence: [evidence[3]], notes: "棒チャートfixtureの元XMLを保持。series/axes等の意味は読まない。"),
                .init(feature: "IO-008", profile: .ooxmlTransitional, operation: .preserve, status: .supported, evidence: [evidence[4]], notes: "未変更保存に限って全bytes一致。編集保存の可否は別に検査する。"),
                .init(feature: "IO-008", profile: .ooxmlStrict, operation: .preserve, status: .supported, evidence: [evidence[5]], notes: "未変更保存に限って全bytes一致。編集保存の可否は別に検査する。"),
                .init(feature: "CHT-001", profile: .ooxmlTransitional, operation: .preserve, status: .partial, evidence: [evidence[4]], notes: "棒チャートを含むfixtureの未変更全bytes保持。編集・変換・再生は含まない。"),
                .init(feature: "OBJ-009", profile: .ooxmlTransitional, operation: .preserve, status: .partial, evidence: [evidence[7]], notes: "架空拡張XMLとopaque binaryを含む未変更資料の全bytes保持。"),
                .init(feature: "TXT-002", profile: .ooxmlTransitional, operation: .edit, status: .partial, evidence: [evidence[8]], notes: "文字段落を再構成する本文差替え。未対応書式の書換え警告を返しstrict保存は拒否する。"),
                .init(feature: "OBJ-009", profile: .ooxmlTransitional, operation: .edit, status: .partial, evidence: [evidence[8]], notes: "本文の局所編集時に無関係の拡張を保全。未知参照の任意編集を許可しない。"),
                .init(feature: "PKG-004", profile: .ooxmlStrict, operation: .edit, status: .partial, evidence: [evidence[9]], notes: "既存要素の位置変更のみを確認。Strict新規生成・スライド追加は提供しない。"),
                .init(feature: "CHT-001", profile: .ooxmlTransitional, operation: .edit, status: .preserveOnly, evidence: [evidence[10]], notes: "別スライドの既知要素を位置変更してもチャートXMLを保持。チャートそのものの編集ではない。"),
                .init(feature: "IMG-001", profile: .ooxmlTransitional, operation: .edit, status: .partial, evidence: [evidence[12]], notes: "既存PNG画像の差替えと代替文を確認。crop/effectの変更は含まない。"),
                .init(feature: "SEC-006", profile: .ooxmlTransitional, operation: .preserve, status: .partial, evidence: [evidence[13]], notes: "署名パーツを含む未変更資料のbytes保持のみ。署名の暗号検証は提供しない。"),
                .init(feature: "SEC-006", profile: .ooxmlTransitional, operation: .edit, status: .unsupported, evidence: [evidence[14]], notes: "署名パーツがある資料の編集保存を拒否する。"),
                .init(feature: "OBJ-011", profile: .ooxmlTransitional, operation: .edit, status: .unsupported, evidence: [evidence[15]], notes: "元opaque要素の変更保存は拒否する。"),
                .init(feature: "TXT-001", profile: .ooxmlTransitional, operation: .create, status: .partial, evidence: [evidence[16]], notes: "新規PPTXの基本直接値を生成。対応する限定モデルの自己再読を検証し、高度機能は含まない。"),
                .init(feature: "IMG-001", profile: .ooxmlTransitional, operation: .create, status: .partial, evidence: [evidence[16]], notes: "新規PPTXの基本直接値を生成。対応する限定モデルの自己再読を検証し、高度機能は含まない。"),
                .init(feature: "TBL-001", profile: .ooxmlTransitional, operation: .create, status: .partial, evidence: [evidence[16]], notes: "新規PPTXの基本直接値を生成。対応する限定モデルの自己再読を検証し、高度機能は含まない。"),
                .init(feature: "MTA-008", profile: .ooxmlTransitional, operation: .inspect, status: .partial, evidence: [evidence[17]], notes: "原本XML/relationshipの参照と未知scopeを列挙。非XML内部・モデル変更後のgraphは未解釈。"),
                .init(feature: "IO-009", profile: .ooxmlTransitional, operation: .edit, status: .partial, evidence: [evidence[18]], notes: "現行writerを使う事前エンコード計画。source/model/options変更を拒否。遅延file監視・全理由の収集は未実装。"),
                .init(feature: "DOC-004", profile: .ooxmlTransitional, operation: .edit, status: .partial, evidence: [evidence[19], evidence[20]], notes: "同寸法・同profileで原本を複製・取り込み。未知参照、競合notes master、独自table styleの別資料取り込みは拒否。"),
                .init(feature: "DOC-004", profile: .ooxmlStrict, operation: .edit, status: .partial, evidence: [evidence[21]], notes: "同じStrict原本内の複製のみ確認。異profileの取り込みとStrict新規生成は未対応。"),
            ]
        default: return []
        }
    }
}
