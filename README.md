# SwiftSlides

提案書・分析資料をSwiftで作成し、PowerPointファイルを読み書きするMITライブラリ。
テキスト、図形、線、フォント、レイアウトを同じ価値モデルで扱います。

**0.1.0** — 開発中。 API互換性は未保証。PowerPointの全仕様への完全対応を意味しません。
Swift 6.4+（Swift 6言語モード）、macOS 14+、iOS 17+。Foundation/FoundationXMLとシステムzlib、外部Swift依存なし。

[APIリファレンス](https://nanbu.github.io/SwiftSlides/) · [復号APIのガイド](Sources/SlideDecrypt/SlideDecrypt.docc/SlideDecrypt.md) · [作例](docs/cookbook.md) · [仕様](docs/implementation-spec.md) · [形式設計](docs/format-design.md) · [検証](docs/verification.md)

設計資料: [形式調査](docs/format-research.md) · [機能台帳](docs/feature-catalog.md) · [API将来設計](docs/api-design.md) · [実装計画](docs/implementation-roadmap.md) · [APIの共通規約とSwiftSheets比較](docs/api-consistency.md)。原本の参照inventory、保存計画、スライドの明示的な複製・取り込みを提供します。選択readerとODP・Keynoteの読取専用codec、独立製品SlideDecryptの復号入口を提供します。機能別の現行能力とfixtureの証拠は[詳細能力台帳](docs/capabilities.json)に記録しています。Keynoteの実アプリ確認は検証時点の最新版だけを対象にします。

```swift
import Foundation
import SwiftSlides

var presentation = Presentation()
var slide = Slide(name: "提案の概要")
slide.addText("収益性を高める3つの施策",
    frame: Rect(x: 40, y: 30, width: 880, height: 60),
    style: TextStyle(font: Font(size: 30, eastAsianFamily: "Yu Gothic"), bold: true))
let columns = try Layout.grid(
    in: Rect(x: 40, y: 150, width: 880, height: 240), rows: 1, columns: 3, gap: 24)
for (index, title) in ["顧客価値", "業務効率", "成長投資"].enumerated() {
    slide.addShape(.roundedRectangle, frame: columns[index],
        fill: .solid(.theme("lt2")), stroke: Stroke(color: .blue, width: 1.5),
        text: TextBody(title, style: TextStyle(font: Font(size: 20)), alignment: .center,
            verticalAlignment: .center))
}
presentation.slides.append(slide)
let result = try presentation.write(to: URL(filePath: "proposal.pptx"))
print(result.warnings)
```

## インストール

タグ公開前はmainを参照し、再現性のためPackage.resolvedのrevisionを固定します。

```swift
.package(url: "https://github.com/nanbu/SwiftSlides.git", from: "0.1.0")
// target dependency:
.product(name: "SwiftSlides", package: "SwiftSlides")
```

必要な形式だけリンクするなら、`SlideCore`と`SlidePPTX`で`CodecSet([.pptx, .pptm])`、`SlideCore`と`SlideODP`で`CodecSet([.odp])`を使えます。ODPとKeynoteは保存を拒否する読取専用codecです。Keynoteだけなら`SlideCore`と`SlideKeynote`で`CodecSet([.keynote])`を使います。暗号文書は`SlideDecrypt`を追加して`Presentation(data: bytes, password: password)`で開きます。通常の`SwiftSlides`は復号製品をリンクしません。
モデルはSendableで、値型と不変の共有storageを使います。同期APIとasync/awaitの入口を提供し、非同期の実処理は`@concurrent`で呼出元Actorから移します。

## 読み取りと保存

```swift
let presentation = try Presentation(contentsOf: URL(filePath: "input.pptx"))
print(presentation.plainText)
print(presentation.readWarnings)
let summary = try Presentation.inspect(contentsOf: URL(filePath: "input.pptx"))
print(summary.slideCount, summary.size)

var edited = presentation
edited.slides[0].elements[0].frame?.x = 60
let output = try edited.write(options: WriteOptions(strict: true))
print(output.warnings)
```

`Presentation.read`は文書と読み取り警告、`encoded`/`write`はbytesと保存警告を返します。各結果の`diagnostics`には判明した機能ID・位置・処理内容・件数を投影します。
`write`/`save`/`transaction`の結果は警告を確認するか、`_ =`で意図的に破棄します。保存形式と認識できる拡張子が違う場合は、出力先を変更せず拒否します。
`data`はbytesだけが必要なときの便利な入口です。変更で警告が必要な処理には`encoded`または`write`を使います。
寸法はポイント、角度は度。図形配列は描画順、グループ内部の座標は親ローカルです。
Font・色・線は直接指定またはテーマ参照。master/layout継承や色変換の実効値、文字計測、描画を計算しません。

## 非同期処理と一括読取

```swift
let result = try await Presentation.read(contentsOf: URL(filePath: "input.pptx"))
var edited = result.presentation
edited.metadata.title = "更新版"
let saved = try await edited.write(to: URL(filePath: "output.pptx"))
print(saved.warnings, result.preservationSummary)

let files = [URL(filePath: "first.pptx"), URL(filePath: "second.pptm")]
let results = try await Presentation.readAll(contentsOf: files, maxConcurrentReads: 2)
let capabilities = try CodecSet.all.capabilities(for: .pptx)
print(results.count, capabilities[.edit])
```

Taskのキャンセルを解析・展開・圧縮の境界で確認します。一括読取は構造化TaskGroupを使い、結果を入力順に返します。失敗時は子Taskをキャンセルして終了を待ちます。同時数の上限は結果全体のメモリ予算ではありません。
FoundationのファイルI/O自体は同期です。URL保存は一時fileへの分割書込境界とatomic確定直前にキャンセルを確認し、最後の確認後は保存が成功し得ます。同名overloadの追加により、async文脈の既存呼出しには`await`が必要になる場合があります。詳しくは[並行処理の契約](docs/implementation-spec.md#swift並行処理と能力照会)を参照してください。

## 対応範囲

<!-- contract:start -->
| 機能 | 読み取り | 保存/生成 | 境界 |
|---|---|---|---|
| 寸法・スライド順・非表示 | 対応 | 対応 | Size / Slide |
| テキスト・段落・リンク | 対応 | 対応 | TextBody / Paragraph / TextRun / Link |
| フォント・文字書式 | 直接指定を読取 | 対応 | Font / TextStyle |
| 図形・線・矢印・破線 | プリセット/直接指定 | 対応 | Element / ShapeGeometry / Fill / Stroke |
| グループ・ローカル座標 | 対応 | 対応 | children / childFrame |
| 配置・整列・均等配置 | 座標を読取 | 生成時の座標計算 | Rect / Insets / Layout |
| 画像・代替文 | 必要時にbytesを展開 | 対応 | Image / asset(at:) |
| 表 | 結合情報も読取 | 非結合表の生成/編集 | Table / TableCell |
| ノート・メタデータ | 対応 | 対応 | notes / Metadata |
| テーマ・script別フォント | sourceThemesで定義読取 | 新規Themeのみ | ThemePart / Theme / Font |
| master/layoutの型付き読取 | 直接要素・表・参照鎖・文字既定 | 原本を保持・投影変更を拒否 | readLayout / readMaster、継承の自動適用なし |
| Chart/SmartArt/OLE | chart cache・保存済みdiagram、OLEはopaque | 原本を保持・投影変更を拒否 | Element.chart / diagram、描画・再計算なし |
| アニメーション・遷移・拡張XML | 効果・時刻・timing木・拡張XML | 原本を保持・投影変更を拒否 | Slide.transition / timing / nativeFeatures、再生なし |
| PPTM・マクロ | 保持/警告 | 既存形式で保持 | 実行・新規VBA作成なし |
| Strict/ZIP64/変則パーツ名 | 対応 | Strict編集・ZIP32保存 | Strict新規slide生成は拒否、原本複製可 |
| 署名付きパッケージ | 未検証として警告 | 未変更保存のみ | 編集は拒否 |
| ODP読取専用 | ODF 1.2/1.3/1.4・Flat ODPの基本値・原本保持 | 新規・編集・変換を拒否 | SlideODP、未知要素は診断、実アプリ確認範囲は検証記録参照 |
| async/await・協調キャンセル | 対応 | atomic確定直前まで確認 | @concurrent / CancellationError |
| 上限付き一括読取 | 入力順・TaskGroup | 対象外 | 同時文書数の上限、全体RSS予算ではない |
| 機能別能力・保持概要 | profile・操作別、fixture証拠付き | SavePlanで別途判定 | FeatureCapability / PreservationSummary |
| 構造化診断 | 判明した機能・位置・件数 | 書換え診断と既存strict規則 | SlideDiagnostic / warnings互換 |
| 原本の参照inventory | timing・connector・link・未知参照の位置 | 危険な削除を拒否 | XML/relationship、非XML内部は未解釈 |
| 保存計画・変更検知 | source/model/options fingerprint | 事前エンコード・stale拒否・atomic保存 | 全診断の網羅・遅延file監視なし |
| スライド複製・取り込み | notes/chart/workbook/assets/linksを保持 | 同寸法・同profile、明示リンク対応表 | 未知参照・競合notes masterを拒否 |
| ODP書式索引 | named/automatic/master/directと出典 | 未提供 | family・scope分離、実効外観は未計算 |
| 選択reader | PPTX本文の選択解析・ODPページ索引 | 部分文書の保存APIなし | memory snapshot、全CRC・file監視なし |
| atomic file target | 出力Dataを64KiBずつ書込 | 失敗・cancel・ENOSPCで元保存先を保持 | エンコード済Data、StreamingWriterは未提供 |
| IDを指定する編集 | group内もID検索 | 正常終了時だけ反映・ID変更を拒否 | 全書式・保存可否はwriterで検査 |
| 文書単位のtransaction | モデルと原本を値として保持 | writer検査後に反映・strict既定 | 事前エンコードの時間とDataメモリが必要 |
| 保存形式・拡張子の一致 | 内容で形式判定 | 認識できる拡張子との不一致を拒否 | 拡張子から暗黙変換しない |
| Keynote | ネイティブIWAの基本値・全wire索引 | 読取専用、保存を拒否 | SlideKeynote、確認済みtype/fieldのみ投影、未知objectは診断 |
| 単位付き行間・段落余白 | points/percentage・明示的0・直接既定 | 基本生成・編集 | TextSpacing、文字測定・実効継承なし |
| フィールド保持と明示評価 | ID/type/cache/書式・初期番号 | 基本保存・run/cache一致が必要 | TextFieldEvaluator、Gregorian日時・番号 |
| 順序付き色変換 | 基本値と変換、透明度系の解決 | 原本保持・新しい色の書換えを拒否 | ColorValue / ColorResolver、他の変換は診断 |
| 自由曲線・外側の影 | Bezier/close・数値座標・影・effectRef | 原本保持・投影変更を拒否 | CustomGeometry / ElementEffects、式・合成は未提供 |
| gradient/pattern/image fill | 直接値・参照・原本XML | 原本を保持・投影変更を拒否 | Fill追加case、継承・描画の自動適用なし |
| 画像crop | 上下左右の倍率・負値 | 原本を保持・投影変更を拒否 | Image.crop / ImageCrop |
| セルの個別辺・対角罫線 | 各辺と明示noFill | 同じ行列の局所編集で保持 | TableCell.bordersは読取専用、borderは左辺互換 |
| 音声・動画参照 | 内部/外部参照・content type | 原本を保持・投影変更を拒否 | Element.media、取得・再生・デコードなし |
| コメント | 従来コメント・新thread/reply・作者・位置 | 原本を保持・投影変更を拒否 | Slide.comments / commentThreads、anchor/taskはSourceXMLで保持 |
| ODPセルの型付き値・式 | 型・字句キャッシュ・通貨・原本式 | 未提供 | TableCell.value / formula、再計算なし |
| PPTX表の展開予算 | 文書/選択slideのmaxTableCells | 対象外 | source master/layoutは読取呼出ごとの予算 |
| PPTX継承style | placeholder・theme matrix・フォントと出典 | 読取結果のみ、原本に適用しない | resolveElement、曖昧/未知参照は診断 |
| ChartML追加データ | scatter/bubble・多段カテゴリ・書式構造 | 原本保持・投影変更を拒否 | 疎なindexとlevelを保持、再計算/描画なし |
| ODP高度構造 | 時間木・media・annotation・原本geometry | 未提供 | 時間木・media・annotationを読取、3D等は原本構造と診断 |
| 原本XMLの構造読取 | 全保持XMLのnamespace・属性・mixed content | 原本の変更APIなし | readSourceXML、構造取得と意味解釈を区別 |
| OOXML Agile復号 | AES128/192/256、SHA1/256/512 | 再暗号化なし、通常保存は平文 | SlideDecrypt、password/サイズ/HMAC検査 |
| OOXML Standard復号 | AES128/192/256 ECB、SHA1 | 再暗号化なし、通常保存は平文 | 固定50,000回KDF、RC4/IRMは拒否 |
| ODF AES復号 | AES-CBC/PBKDF2、checksum検査 | 再暗号化なし、ODP保存なし | SlideDecrypt、Blowfishは未対応 |
| Keynote復号 | iwpv2 v2/f1、PBKDF2SHA1/AES128 | 再暗号化なし、Keynote保存なし | 末尾20bytes未解釈、現行15.4の架空文書で検証 |
| Keynoteの文字書式・表・chart・build | UTF16 run/style・v5セル・疎なgrid・build/chunk・transition | 読取専用、保存を拒否 | 式token/結合/軸の確認済みsubset、未知属性はwire索引 |
| ODP埋込chart | local-table/range・疎なseries・軸/全XML構造 | 読取専用、保存を拒否 | 単純A1範囲、外部データ・計算・描画なし |
| PPTX数式構造 | OMMLの型・引数境界・段落内順序 | 原本保持・文字領域の再構成を拒否 | TextRun.equation、計算/線形式化/描画なし |
| PPTX図形の3D属性 | 直接camera/light・押出し・bevel・色 | 原本保持・投影変更/新規生成を拒否 | Element.scene3D / shape3D、直接値と明示継承、描画なし |
| ODP MathML数式 | 内部object・inline・token/引数順・annotation原本 | 未提供 | Element.equation / TextRun.equation、計算/描画なし |
| ODP高度図形 | 16命令・viewBox・modifier/guide・text area | 未提供 | EnhancedGeometryとGeometryEvaluator、独自座標評価、未知pathは未解決 |
| 追加文字外観とDrawingML効果 | 間隔・baseline・caps・strike・underline・効果tree | 未提供 | TextAppearance/DrawingEffect、未知属性は原本 |
| ODP立体図形 | scene/cube/light・vector/matrix・extrusion属性 | 未提供 | SpatialGeometry.evaluated、3D変形・cube/ellipsoid・断面と原本、描画なし |
| 埋込・外部workbook | 保存済み値・式・shared strings・疎なA1範囲 | 未提供 | 呼出側bytes供給、cacheと別値、再計算なし |
| Keynote式・結合・chart軸 | TSCE token/cache・merge・UFF/PreUFF軸 | 未提供 | 確認済みUID/handle/入れ子、schema拡張、原本と診断、再計算なし |
| file-backed reader | ZIP/Keynote directory・位置索引・LRU・変更検出 | 未提供 | 圧縮/展開索引の合計cache予算、モデル/一時領域とRSSは別 |
| 旧PPT | CFB/live persist・スライド順・寸法・本文 | 未提供 | SlideLegacy、旧暗号/形状意味の全解釈なし |
| 旧Keynote XML・SXI | 基本寸法/順序/本文・XML原本 | 未提供 | SlideLegacy、Keynote2/plain/gzipと旧office XML |
| DrawingML式・円弧評価 | 標準17演算・組込変数・調整値・楕円弧 | 未提供 | GeometryEvaluator、宣言順・計算予算・非有限拒否 |
| Workbook複合参照 | 名前scope・union/intersection・3D・共有式 | 未提供 | 保存値のみ、再計算・旧XLSなし |
| Content MathML | apply/bind・演算子・変数・数値成分 | 未提供 | EquationNode、未知辞書/拡張と原本保持 |
| ODP変形・text-path | 順序付き2D行列・角度単位・配置属性 | 未提供 | 文字計測なし、独自engineは明示provider |
| glTF/GLB資源 | 場面/mesh/accessor・sparse・PBR・skin/animation | 未提供 | 外部bufferはprovider、必須extensionは診断、再生なし |
| Keynote複合参照・schema | UID/handle/入れ子・型付き属性・参照inventory | 未提供 | 未知bytesを推測せず、明示schemaだけで拡張 |
| 文書内並列読取・directory | 選択順・同時数上限・不変索引・変更拒否 | 未提供 | readSlidesとfileBackedURL、返却結果は呼出側所有 |
| Flat ODP・ページ別寸法 | office:document・binary-data・sizeOverride | 未提供 | 原本flat.xmlを取得可能、保存は拒否 |
| chart立体表示・軸詳細 | 3D view・壁/床・刻み・交点・反転 | 未提供 | ChartView3D/ChartSurface/ChartAxisScale、描画なし |
<!-- contract:end -->

未対応要素には警告を付け、元パッケージを保持します。PPTX/PPTMの未変更保存は原本bytesそのまま。
編集保存は変更ノードのXMLを再直列化し、未変更パーツは圧縮済payloadを転写します。ZIPヘッダーは正規化されます。
文字段落や表の再構成では未対応書式を引き継げない場合があるため、必ず保存警告を返します。strictは警告付き保存を拒否します。
未知要素の変更、既存テーマ・レイアウト変更、参照先のあるスライド削除などは安全性のため拒否します。
変換、レンダリング、再暗号化、フォント埋め込みは提供しません。復号したsnapshotのPPTX保存は平文になります。Keynoteの式/結合/chart軸、ODPの高度geometry/MathML/3D、追加文字外観に確認済みsubsetを提供します。未知属性・複合型は原本と診断に残します。全機能の意味解釈完了とは表示しません。

## 検証と安全性

架空のpython-pptx由来fixtureと独立した期待値、壊れたZIP/XML/参照の負例、圧縮済bytes保全を検査します。
macOSのテスト・release build、python-pptxの相互検証、LibreOffice再保存、PowerPoint実アプリで修復なしの作例表示を検証しました。
CIでmacOS/Linuxを検査。iOS実行・全種類のPowerPointファイルとの互換性は未検証です。

既定上限:10,000 ZIP entries、合計512MiB展開、1 part128MiB、XML深さ128、2,000,000 nodes。
上限はプロセスメモリ保証ではありません。DTD/ENTITYを拒否し、外部URLは取得せず、VBAを実行しません。
`inspect`および未変更パーツの転写は全パーツのCRC検証ではありません。読む/編集するパーツとassetは展開時にCRC検証します。

```sh
swift test
swift build -c release
python3 scripts/check-contract.py
python3 scripts/check-public-content.py --history
scripts/build-docs.sh
swift run swiftslides sample proposal.pptx
```

性能の測定条件と時間・メモリは[性能資料](docs/performance.md)を参照してください。

## ライセンス

MIT。SwiftDocumentsのMITなZIP/OPC実装を利用し、[NOTICE](NOTICE)に帰属を残しています。
図形・文字・レイアウト・テーマの実装は公開形式仕様を参照した独自実装です。
フォントファイルや購入した商用アセットを含みません。架空fixtureのpython-pptx由来パーツにはMITの帰属・許諾を同梱しています。

表示用の直接値と責務の範囲は[表示用API](docs/display-values.md)を参照してください。

読取専用の旧形式は`SlideCore`＋`SlideLegacy`で`CodecSet([.ppt, .keynoteLegacy, .sxi])`を使います。`CodecSet.all`にも登録されています。全旧形式の書式・暗号には対応せず、未知構造を原本に保持します。

## 読取APIの追加範囲

DrawingMLのguide/円弧、Workbookの名前付き・複合参照と共有数式、Content MathML、ODPの2D/3D変形・text-path・Flat ODP、glTF/GLB、Keynoteの複合式・セル書式・parameterized/editable path・build詳細を追加しました。未知extensionやKeynote世代は原本と診断に残します。数式再計算・描画・保存エンジンの追加はありません。

```swift
let reader = try SlideReader(
    fileBackedURL: URL(filePath: "input.key"), codecs: .all,
    cacheBudget: ReaderCacheBudget(totalBytes: 8 << 20))
let selected = try await reader.readSlides(
    selection: .ids([reader.slideDescriptors[0].id]), maxConcurrentReads: 2)
print(selected[0].slide.plainText, reader.cacheStatistics as Any)
```

ODPはXML内のページ位置、KeynoteはIWA内のobject位置を索引に持ち、本文を選択時に解析します。キャッシュの合計byte上限は保持する圧縮bytesと展開索引に適用します。返却モデル・asset・解析途中の領域は別で、RSS上限を保証するAPIではありません。時間とpeak RSSの測定条件は[検証記録](docs/verification.md)に記載しています。
