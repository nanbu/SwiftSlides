# SwiftSlides

提案書・分析資料をSwiftで作成し、PowerPointファイルを読み書きするMITライブラリ。
テキスト、図形、線、フォント、レイアウトを同じ価値モデルで扱います。

**開発中・未リリース。** API互換性は未保証。PowerPointの全仕様への完全対応を意味しません。
Swift 6.4+（Swift 6言語モード）、macOS 14+、iOS 17+。Foundation/FoundationXMLとシステムzlib、外部Swift依存なし。

[APIリファレンス](https://nanbu.github.io/SwiftSlides/) · [作例](docs/cookbook.md) · [仕様](docs/implementation-spec.md) · [形式設計](docs/format-design.md) · [検証](docs/verification.md)

設計資料: [形式調査](docs/format-research.md) · [機能台帳](docs/feature-catalog.md) · [API将来設計](docs/api-design.md) · [実装計画](docs/implementation-roadmap.md) · [APIの共通規約とSwiftSheets比較](docs/api-consistency.md)。原本の参照inventory、保存計画、スライドの明示的な複製・取り込みを提供します。選択readerとODP読取専用codecを提供します。Keynoteは限定試作の段階です。機能別の現行能力とfixtureの証拠は[詳細能力台帳](docs/capabilities.json)に記録しています。Keynoteの実アプリ確認は検証時点の最新版だけを対象にします。

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
.package(url: "https://github.com/nanbu/SwiftSlides.git", branch: "main")
// target dependency:
.product(name: "SwiftSlides", package: "SwiftSlides")
```

必要な形式だけリンクするなら、`SlideCore`と`SlidePPTX`で`CodecSet([.pptx, .pptm])`、`SlideCore`と`SlideODP`で`CodecSet([.odp])`を使えます。ODPは保存を拒否する読取専用codecです。
全モデルはSendableの値型。同期APIとasync/awaitの入口を提供し、非同期の実処理は`@concurrent`で呼出元Actorから移します。

## 読み取りと保存

```swift
let presentation = try Presentation(contentsOf: URL(filePath: "input.pptx"))
print(presentation.plainText)
print(presentation.readWarnings)
let summary = try Presentation.inspect(contentsOf: URL(filePath: "input.pptx"))
print(summary.slideCount, summary.size)

var edited = presentation
edited.slides[0].elements[0].frame?.x = 60
let output = try edited.encoded(options: WriteOptions(strict: true))
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
| master/layout継承・色変換 | 参照と原本を保持 | 保持 | 実効外観は未計算 |
| Chart/SmartArt/OLE/動画 | opaque/警告 | 未変更部分を保持 | 新規作成・動作解釈なし |
| アニメーション・遷移・拡張XML | 原本/警告 | 未変更部分を保持 | タイミングのモデルなし |
| PPTM・マクロ | 保持/警告 | 既存形式で保持 | 実行・新規VBA作成なし |
| Strict/ZIP64/変則パーツ名 | 対応 | Strict編集・ZIP32保存 | Strict新規slide生成は拒否、原本複製可 |
| 署名付きパッケージ | 未検証として警告 | 未変更保存のみ | 編集は拒否 |
| 旧PPT・暗号化 | 拒否 | 未対応 | OLEの種別詳細判定なし |
| ODP読取専用 | ODF 1.3/1.4の基本値・原本保持 | 新規・編集・変換を拒否 | SlideODP、1.2は未検証、未知要素は診断 |
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
| Keynote | 公開codec未提供、wire限定試作 | 試作のみ・同長文字1field | 15.4で再包装・局所編集・再保存を確認 |
<!-- contract:end -->

未対応要素には警告を付け、元パッケージを保持します。PPTX/PPTMの未変更保存は原本bytesそのまま。
編集保存は変更ノードのXMLを再直列化し、未変更パーツは圧縮済payloadを転写します。ZIPヘッダーは正規化されます。
文字段落や表の再構成では未対応書式を引き継げない場合があるため、必ず保存警告を返します。strictは警告付き保存を拒否します。
未知要素の変更、既存テーマ・レイアウト変更、参照先のあるスライド削除などは安全性のため拒否します。
変換、レンダリング、旧PPT、暗号解除、フォント埋め込みは提供しません。

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
