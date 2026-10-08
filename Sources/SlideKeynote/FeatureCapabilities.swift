// docs/capabilities.jsonから生成。直接編集せずscripts/build-capabilities.pyを使う。
import SlideCore

enum KeynoteFeatureCapabilities {
    private static let evidence: [CapabilityEvidence] = [
        .init(id: "E46", fixture: "native-synthetic.keynote.zip", fixtureSHA256: "a9f0130b4f47a14113c4694ae6a546630f5484e4721f214ab602b533092ad861", test: "nativeKeynoteOrderUnknownsAndAssets", scope: "独立生成した架空IWAの文書順・非表示・位置/回転・文字・画像・notes・未知wire bytesを比較。現行アプリの全機能互換性を含まない。"),
        .init(id: "E60", fixture: "native-advanced.keynote.zip", fixtureSHA256: "4ca769ba86e99a86a8d43bee274f1bb5298b9841a6a08b46e0cec7f09e2231de", test: "keynoteNativeStylesTablesChartsAndBuilds", scope: "独立した架空wireのUTF16 run、段落/文字style、BNC v5表セル、疎なchart grid、transitionとbuild/chunkを比較。式・結合・軸・高度書式・固有効果の全意味/外観は含まない。"),
        .init(id: "E63", fixture: "native-paths.keynote.zip", fixtureSHA256: "fce0144053e33e725ae30d40a3d3548e1f6c705b9671b0586242bf9f77351516", test: "keynoteNativeBezierPathsAndConnectors", scope: "独立した架空TSP.Pathのmove/line/quadratic/cubic/close、naturalSize、flip、Shape/ConnectionLineを比較。点数不正拒否、未知命令のwire保持。parameterized/editable pathと接続UUIDの意味評価は含まない。"),
        .init(id: "R79", fixture: "remaining-native.keynote.zip", fixtureSHA256: "995d14e18e841d09011839535530278d044ec45245cf8f4ad2fc2683e6752aa7", test: "keynoteFormulaMergeAndAxes", scope: "式token/保存済み5、2セル結合、軸min/max/title/grid。現行UFFと旧PreUFF型、親styleの継承を比較。"),
        .init(id: "R80", fixture: "remaining-preuff.keynote.zip", fixtureSHA256: "2993a7e41d15f64bc3209948b3505f5c074b1f36dc095f3e4fb8051ad92c84d6", test: "keynoteFormulaMergeAndAxes", scope: "式token/保存済み5、2セル結合、軸min/max/title/grid。現行UFFと旧PreUFF型、親styleの継承を比較。"),
        .init(id: "R86", fixture: "remaining-native.keynote.zip", fixtureSHA256: "995d14e18e841d09011839535530278d044ec45245cf8f4ad2fc2683e6752aa7", test: "fileBackedSelectionAndChangeDetection", scope: "file-backed選択結果のsnapshotとの一致、atomic置換の検出。cache上限/未選択payloadは別テストで確認。"),
        .init(id: "R87", fixture: "keynote-formula-15.4.key.zip", fixtureSHA256: "a0a9dbc06f3ecbcceedff54e19800d49870ec14bd875024b7b16ceceb5124052", test: "keynoteProducerFormulaAndMergeMatchAppValues", scope: "Keynote 15.4作成物。AppleScriptでC2の式=A2+B2と保存済み5、A1:B1結合を取得してTSCE参照token/結合投影と比較。外観や全式を含まない。"),
        .init(id: "completion-keynote", fixture: "native-synthetic.keynote.zip", fixtureSHA256: "a9f0130b4f47a14113c4694ae6a546630f5484e4721f214ab602b533092ad861", test: "keynoteNestedReferencesSchemasAndInventory", scope: "文書索引とheader参照graphを検査。同テスト内の合成wireでUID/入れ子/未知fieldとschema予算を検査。"),
    ]

    static func features(for format: PresentationFormat) -> [FeatureCapability] {
        switch format {
        case .keynote:
            return [
                .init(feature: "DOC-001", profile: .keynoteIWA, operation: .read, status: .partial, evidence: [evidence[0]], notes: "確認済みtype/fieldの投影と全wire索引。式/結合/chart軸の確認済みsubsetを追加。未知object・高度属性・固有buildは原本と診断。保存なし。"),
                .init(feature: "DOC-002", profile: .keynoteIWA, operation: .read, status: .partial, evidence: [evidence[0]], notes: "確認済みtype/fieldの投影と全wire索引。式/結合/chart軸の確認済みsubsetを追加。未知object・高度属性・固有buildは原本と診断。保存なし。"),
                .init(feature: "DOC-009", profile: .keynoteIWA, operation: .read, status: .partial, evidence: [evidence[0]], notes: "確認済みtype/fieldの投影と全wire索引。式/結合/chart軸の確認済みsubsetを追加。未知object・高度属性・固有buildは原本と診断。保存なし。"),
                .init(feature: "GEO-001", profile: .keynoteIWA, operation: .read, status: .partial, evidence: [evidence[0]], notes: "確認済みtype/fieldの投影と全wire索引。式/結合/chart軸の確認済みsubsetを追加。未知object・高度属性・固有buildは原本と診断。保存なし。"),
                .init(feature: "TXT-001", profile: .keynoteIWA, operation: .read, status: .partial, evidence: [evidence[0]], notes: "確認済みtype/fieldの投影と全wire索引。式/結合/chart軸の確認済みsubsetを追加。未知object・高度属性・固有buildは原本と診断。保存なし。"),
                .init(feature: "PKG-001", profile: .keynoteIWA, operation: .read, status: .partial, evidence: [evidence[0], evidence[7]], notes: "文書索引とheader参照graphを検査。同テスト内の合成wireでUID/入れ子/未知fieldとschema予算を検査。 未知extension/版は原本と診断。描画・保存・再計算は追加しない。"),
                .init(feature: "TBL-001", profile: .keynoteIWA, operation: .read, status: .partial, evidence: [evidence[1]], notes: "確認した文字run/style、v5セル値、chart grid、build/transitionだけ。未知型・高度属性はwire索引に保持し、描画・再生・式再計算は未対応。"),
                .init(feature: "TBL-002", profile: .keynoteIWA, operation: .read, status: .partial, evidence: [evidence[1]], notes: "確認した文字run/style、v5セル値、chart grid、build/transitionだけ。未知型・高度属性はwire索引に保持し、描画・再生・式再計算は未対応。"),
                .init(feature: "CHT-004", profile: .keynoteIWA, operation: .read, status: .partial, evidence: [evidence[1]], notes: "確認した文字run/style、v5セル値、chart grid、build/transitionだけ。未知型・高度属性はwire索引に保持し、描画・再生・式再計算は未対応。"),
                .init(feature: "ANI-001", profile: .keynoteIWA, operation: .read, status: .partial, evidence: [evidence[1]], notes: "確認した文字run/style、v5セル値、chart grid、build/transitionだけ。未知型・高度属性はwire索引に保持し、描画・再生・式再計算は未対応。"),
                .init(feature: "ANI-002", profile: .keynoteIWA, operation: .read, status: .partial, evidence: [evidence[1]], notes: "確認した文字run/style、v5セル値、chart grid、build/transitionだけ。未知型・高度属性はwire索引に保持し、描画・再生・式再計算は未対応。"),
                .init(feature: "ANI-004", profile: .keynoteIWA, operation: .read, status: .partial, evidence: [evidence[1]], notes: "確認した文字run/style、v5セル値、chart grid、build/transitionだけ。未知型・高度属性はwire索引に保持し、描画・再生・式再計算は未対応。"),
                .init(feature: "STY-007", profile: .keynoteIWA, operation: .read, status: .partial, evidence: [evidence[1]], notes: "確認した文字run/style、v5セル値、chart grid、build/transitionだけ。未知型・高度属性はwire索引に保持し、描画・再生・式再計算は未対応。"),
                .init(feature: "TXT-002", profile: .keynoteIWA, operation: .read, status: .partial, evidence: [evidence[1]], notes: "確認した文字run/style、v5セル値、chart grid、build/transitionだけ。未知型・高度属性はwire索引に保持し、描画・再生・式再計算は未対応。"),
                .init(feature: "GEO-004", profile: .keynoteIWA, operation: .read, status: .partial, evidence: [evidence[2]], notes: "確認した数値Bezier命令を原座標領域のまま投影。未知/parameterized/editable pathはwire索引と診断に保持する。"),
                .init(feature: "TBL-003", profile: .keynoteIWA, operation: .read, status: .partial, evidence: [evidence[3], evidence[4], evidence[6]], notes: "BNC v5 formula ID・TSCE tokenとcache、merge map/tract、UFF/PreUFF chart軸属性とstyle親参照。未知token/書式はwire索引。式再計算・描画なし。"),
                .init(feature: "TBL-010", profile: .keynoteIWA, operation: .read, status: .partial, evidence: [evidence[3], evidence[4], evidence[6], evidence[7]], notes: "文書索引とheader参照graphを検査。同テスト内の合成wireでUID/入れ子/未知fieldとschema予算を検査。 未知extension/版は原本と診断。描画・保存・再計算は追加しない。"),
                .init(feature: "CHT-006", profile: .keynoteIWA, operation: .read, status: .partial, evidence: [evidence[3], evidence[4]], notes: "BNC v5 formula ID・TSCE tokenとcache、merge map/tract、UFF/PreUFF chart軸属性とstyle親参照。未知token/書式はwire索引。式再計算・描画なし。"),
                .init(feature: "CHT-007", profile: .keynoteIWA, operation: .read, status: .partial, evidence: [evidence[3], evidence[4]], notes: "BNC v5 formula ID・TSCE tokenとcache、merge map/tract、UFF/PreUFF chart軸属性とstyle親参照。未知token/書式はwire索引。式再計算・描画なし。"),
                .init(feature: "IO-003", profile: .keynoteIWA, operation: .read, status: .partial, evidence: [evidence[5]], notes: "ZIP/Keynote directoryの不変入力、ODP XML/Keynote IWA位置索引、圧縮+展開cacheの合計予算と文書内並行読取。途中変更は拒否。モデル/一時領域/RSSは別。"),
                .init(feature: "IO-011", profile: .keynoteIWA, operation: .read, status: .partial, evidence: [evidence[5]], notes: "ZIP/Keynote directoryの不変入力、ODP XML/Keynote IWA位置索引、圧縮+展開cacheの合計予算と文書内並行読取。途中変更は拒否。モデル/一時領域/RSSは別。"),
            ]
        default: return []
        }
    }
}
