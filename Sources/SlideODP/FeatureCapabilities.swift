// docs/capabilities.jsonから生成。直接編集せずscripts/build-capabilities.pyを使う。
import SlideCore

enum ODPFeatureCapabilities {
    private static let evidence: [CapabilityEvidence] = [
        .init(id: "E24", fixture: "styles.odp", fixtureSHA256: "04257a783591daad3e5ea1d700ad590727eaa22812663ee0c6edb780bf6301b0", test: "odpBasicReadPreservesOriginalAndSeparatesInheritedValues", scope: "ODF 1.3架空fixtureのページ寸法、本文・空白・tab・リンク、automatic直接書式、画像bytes、表表示文字、notesを照合。外観・保存は対象外。"),
        .init(id: "E25", fixture: "styles.odp", fixtureSHA256: "04257a783591daad3e5ea1d700ad590727eaa22812663ee0c6edb780bf6301b0", test: "odpStylesResolveDirectNamedAutomaticAndMaster", scope: "familyとautomatic scopeを分離しdefault/named parent/master/direct propertyの値と出典を照合。placeholder外観は対象外。"),
        .init(id: "E26", fixture: "libreoffice.odp", fixtureSHA256: "1e84faf264b006b6e9a817858c33a35c8d347815b69c699e95c9cfc9b1cf7857", test: "libreOfficeODPProducerIsReadableWithLocatedWarnings", scope: "LibreOffice 26.2.3.2が架空PPTXから生成した2枚のODF 1.4で本文とnotesを照合。custom geometryはopaqueの表示文字投影。外観は未検証。"),
        .init(id: "E43", fixture: "styles.odp", fixtureSHA256: "04257a783591daad3e5ea1d700ad590727eaa22812663ee0c6edb780bf6301b0", test: "odpTypedCellsKeepLexicalValuesAndFormulaSeparateFromText", scope: "架空ODF 1.3にfloat/boolean/式を追加し、字句値と表示文字を分離。数値解釈不可をnilで示す。再計算なし。"),
        .init(id: "E50", fixture: "styles.odp", fixtureSHA256: "04257a783591daad3e5ea1d700ad590727eaa22812663ee0c6edb780bf6301b0", test: "odpTimingMediaAnnotationsAndCustomGeometryAreReadable", scope: "架空のSMIL時間構造・audio URI・annotation・enhanced geometryを追加し値と原本構造を比較。再生/geometry評価なし。"),
        .init(id: "E62", fixture: "styles.odp", fixtureSHA256: "04257a783591daad3e5ea1d700ad590727eaa22812663ee0c6edb780bf6301b0", test: "odpEmbeddedChartLocalTableAndSparseRanges", scope: "架空埋込chartのlocal-tableと単純A1 range、series名・categories・数値cache・疎なindex・axis構造を確認。外部table rangeは未解決診断。高度書式/全chart型/計算/外観は含まない。"),
        .init(id: "odp-enhanced-geometry", fixture: "semantic-reading.odp", fixtureSHA256: "0ab37c1e02d9814c4f729cb2cc583abc98c2f99347c7d323319343d41a23dae7", test: "odpEnhancedGeometryOperandsAndCommands", scope: "ODF 1.3合成fixtureの16命令・数値/modifier/guide・viewBox・text area・鏡像・handle原本。未知/破損/予算は別回帰検査。guide評価・3D・実アプリは未検証。"),
        .init(id: "odp-mathml", fixture: "semantic-reading.odp", fixtureSHA256: "0ab37c1e02d9814c4f729cb2cc583abc98c2f99347c7d323319343d41a23dae7", test: "odpMathMLStructureSourcesAndInlineOrder", scope: "ODF 1.3合成fixtureのMathML token・分数/根号/添字/上下限/行列・annotation保持、内部object・inline・preview。Content MathML/計算/描画・実アプリは未検証。"),
        .init(id: "R75", fixture: "semantic-reading.odp", fixtureSHA256: "0ab37c1e02d9814c4f729cb2cc583abc98c2f99347c7d323319343d41a23dae7", test: "odpSemanticReadingAcrossDeclaredVersions", scope: "versionごとの数式/path読取。1.4は新handle-position-x/yへ変更して比較。公式RNGの独立検査はverification.mdに記録。"),
        .init(id: "R76", fixture: "semantic-reading.odp", fixtureSHA256: "0ab37c1e02d9814c4f729cb2cc583abc98c2f99347c7d323319343d41a23dae7", test: "odpSemanticReadingAcrossDeclaredVersions", scope: "versionごとの数式/path読取。1.4は新handle-position-x/yへ変更して比較。公式RNGの独立検査はverification.mdに記録。"),
        .init(id: "R77", fixture: "semantic-reading.odp", fixtureSHA256: "0ab37c1e02d9814c4f729cb2cc583abc98c2f99347c7d323319343d41a23dae7", test: "odpSemanticReadingAcrossDeclaredVersions", scope: "versionごとの数式/path読取。1.4は新handle-position-x/yへ変更して比較。公式RNGの独立検査はverification.mdに記録。"),
        .init(id: "R78", fixture: "semantic-reading.odp", fixtureSHA256: "0ab37c1e02d9814c4f729cb2cc583abc98c2f99347c7d323319343d41a23dae7", test: "odfSpatialSceneAndExtrusion", scope: "dr3d scene/cube/light・vector・matrixとenhanced extrusion flag。"),
        .init(id: "R85", fixture: "semantic-reading.odp", fixtureSHA256: "0ab37c1e02d9814c4f729cb2cc583abc98c2f99347c7d323319343d41a23dae7", test: "fileBackedSelectionAndChangeDetection", scope: "file-backed選択結果のsnapshotとの一致、atomic置換の検出。cache上限/未選択payloadは別テストで確認。"),
        .init(id: "completion-content-mathml", fixture: "semantic-reading.odp", fixtureSHA256: "0ab37c1e02d9814c4f729cb2cc583abc98c2f99347c7d323319343d41a23dae7", test: "contentMathMLBindingsAndNumericComponents", scope: "内部数式を合成Content MathMLへ置換し、apply/bind・有理数の成分・内容辞書と束縛変数を検査。"),
        .init(id: "completion-transform", fixture: "semantic-reading.odp", fixtureSHA256: "0ab37c1e02d9814c4f729cb2cc583abc98c2f99347c7d323319343d41a23dae7", test: "odfTransformOrderAnglesAndTextPath", scope: "custom-shapeへtransform/text-pathを追加し、2D変形順・degree/grad/radianとモデル値を検査。"),
        .init(id: "completion-engine", fixture: "semantic-reading.odp", fixtureSHA256: "0ab37c1e02d9814c4f729cb2cc583abc98c2f99347c7d323319343d41a23dae7", test: "customODPEngineRequiresExplicitProvider", scope: "独自engineを明示追加し、既定opaqueと登録providerの解析結果を検査。"),
        .init(id: "completion-flat", fixture: "completion-flat.fodp", fixtureSHA256: "e8f82ce54899ddbbb5b0402afb1300bf258335e800b3896bae54b0470a032ee3", test: "flatODPAndDifferentPageSizes", scope: "単体office:document、異なる2ページ寸法、原本bytesとsizeOverrideを検査。"),
    ]

    static func features(for format: PresentationFormat) -> [FeatureCapability] {
        switch format {
        case .odp:
            return [
                .init(feature: "DOC-001", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[0], evidence[16]], notes: "単体office:document、異なる2ページ寸法、原本bytesとsizeOverrideを検査。 未知extension/版は原本と診断。描画・保存・再計算は追加しない。"),
                .init(feature: "DOC-009", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[0]], notes: "指定ODF 1.3 fixtureで基本値を投影。named/master継承を直接値へ埋めない。書込と外観は未提供。"),
                .init(feature: "TXT-001", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[0]], notes: "指定ODF 1.3 fixtureで基本値を投影。named/master継承を直接値へ埋めない。書込と外観は未提供。"),
                .init(feature: "TXT-003", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[0]], notes: "指定ODF 1.3 fixtureで基本値を投影。named/master継承を直接値へ埋めない。書込と外観は未提供。"),
                .init(feature: "IMG-001", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[0]], notes: "指定ODF 1.3 fixtureで基本値を投影。named/master継承を直接値へ埋めない。書込と外観は未提供。"),
                .init(feature: "STY-007", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[1]], notes: "default/named/automatic/drawing-page masterのpropertyと出典の限定解決。placeholder・外観・編集は対象外。"),
                .init(feature: "STY-008", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[1]], notes: "default/named/automatic/drawing-page masterのpropertyと出典の限定解決。placeholder・外観・編集は対象外。"),
                .init(feature: "STY-010", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[1]], notes: "default/named/automatic/drawing-page masterのpropertyと出典の限定解決。placeholder・外観・編集は対象外。"),
                .init(feature: "TXT-001", profile: .odf14, operation: .read, status: .partial, evidence: [evidence[2]], notes: "LibreOffice生成の指定fixtureで本文・notesを確認。ODF 1.4全要素への対応を意味しない。"),
                .init(feature: "DOC-009", profile: .odf14, operation: .read, status: .partial, evidence: [evidence[2]], notes: "LibreOffice生成の指定fixtureで本文・notesを確認。ODF 1.4全要素への対応を意味しない。"),
                .init(feature: "TBL-002", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[3]], notes: "value-type/字句キャッシュ/通貨/原本formulaを表示文字と別に読む。書式・式の評価なし。"),
                .init(feature: "TBL-010", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[3]], notes: "value-type/字句キャッシュ/通貨/原本formulaを表示文字と別に読む。書式・式の評価なし。"),
                .init(feature: "ANI-005", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[4]], notes: "時間語彙/対象/文字コメント/メディア参照を読取。高度geometryはSourceXML構造と原本descriptorで取得し意味未解釈。"),
                .init(feature: "MED-001", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[4]], notes: "時間語彙/対象/文字コメント/メディア参照を読取。高度geometryはSourceXML構造と原本descriptorで取得し意味未解釈。"),
                .init(feature: "REV-001", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[4]], notes: "時間語彙/対象/文字コメント/メディア参照を読取。高度geometryはSourceXML構造と原本descriptorで取得し意味未解釈。"),
                .init(feature: "GEO-004", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[4], evidence[6], evidence[9], evidence[14], evidence[15]], notes: "独自engineを明示追加し、既定opaqueと登録providerの解析結果を検査。 未知extension/版は原本と診断。描画・保存・再計算は追加しない。"),
                .init(feature: "CHT-004", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[5]], notes: "埋込ODF chartのlocal-tableと単純A1 range・title/legendの字句・原本書式。外部range・高度属性は原本と未解決診断。描画/再計算は行わない。"),
                .init(feature: "CHT-007", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[5]], notes: "埋込ODF chartのlocal-tableと単純A1 range・title/legendの字句・原本書式。外部range・高度属性は原本と未解決診断。描画/再計算は行わない。"),
                .init(feature: "OBJ-005", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[7], evidence[9], evidence[13]], notes: "内部数式を合成Content MathMLへ置換し、apply/bind・有理数の成分・内容辞書と束縛変数を検査。 未知extension/版は原本と診断。描画・保存・再計算は追加しない。"),
                .init(feature: "PKG-007", profile: .odf12, operation: .read, status: .partial, evidence: [evidence[8]], notes: "確認済みMathML/path/modifier/guide subset。GeometryEvaluatorで算術・関数・条件・参照・handle/text areaを独自座標で評価。演算/深さ予算、未知式は拒否。全ODF機能・描画なし。"),
                .init(feature: "GEO-004", profile: .odf12, operation: .read, status: .partial, evidence: [evidence[8]], notes: "確認済みMathML/path/modifier/guide subset。GeometryEvaluatorで算術・関数・条件・参照・handle/text areaを独自座標で評価。演算/深さ予算、未知式は拒否。全ODF機能・描画なし。"),
                .init(feature: "OBJ-005", profile: .odf12, operation: .read, status: .partial, evidence: [evidence[8]], notes: "確認済みMathML/path/modifier/guide subset。GeometryEvaluatorで算術・関数・条件・参照・handle/text areaを独自座標で評価。演算/深さ予算、未知式は拒否。全ODF機能・描画なし。"),
                .init(feature: "PKG-007", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[9], evidence[16]], notes: "単体office:document、異なる2ページ寸法、原本bytesとsizeOverrideを検査。 未知extension/版は原本と診断。描画・保存・再計算は追加しない。"),
                .init(feature: "PKG-007", profile: .odf14, operation: .read, status: .partial, evidence: [evidence[10]], notes: "確認済みMathML/path/modifier/guide subset。GeometryEvaluatorで算術・関数・条件・参照・handle/text areaを独自座標で評価。演算/深さ予算、未知式は拒否。全ODF機能・描画なし。"),
                .init(feature: "GEO-004", profile: .odf14, operation: .read, status: .partial, evidence: [evidence[10]], notes: "確認済みMathML/path/modifier/guide subset。GeometryEvaluatorで算術・関数・条件・参照・handle/text areaを独自座標で評価。演算/深さ予算、未知式は拒否。全ODF機能・描画なし。"),
                .init(feature: "OBJ-005", profile: .odf14, operation: .read, status: .partial, evidence: [evidence[10]], notes: "確認済みMathML/path/modifier/guide subset。GeometryEvaluatorで算術・関数・条件・参照・handle/text areaを独自座標で評価。演算/深さ予算、未知式は拒否。全ODF機能・描画なし。"),
                .init(feature: "GEO-012", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[11]], notes: "dr3d scene/object・camera/light vector・12値matrix・style継承とextrusion属性。未知transformや属性は原本。描画なし。"),
                .init(feature: "IO-003", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[12]], notes: "ZIP/Keynote directoryの不変入力、ODP XML/Keynote IWA位置索引、圧縮+展開cacheの合計予算と文書内並行読取。途中変更は拒否。モデル/一時領域/RSSは別。"),
                .init(feature: "IO-011", profile: .odf13, operation: .read, status: .partial, evidence: [evidence[12]], notes: "ZIP/Keynote directoryの不変入力、ODP XML/Keynote IWA位置索引、圧縮+展開cacheの合計予算と文書内並行読取。途中変更は拒否。モデル/一時領域/RSSは別。"),
            ]
        default: return []
        }
    }
}
