# 作例

## ビジネス資料の作例

```sh
swift run swiftslides sample proposal.pptx
```

2枚の架空の提案資料を生成します。施策の3列レイアウト、図形、矢印、書式付きテキスト、表、ノートを含みます。
作例の正典は[`Sources/SwiftSlidesCLI/main.swift`](https://github.com/nanbu/SwiftSlides/blob/main/Sources/SwiftSlidesCLI/main.swift)です。

## 矢印付きの線

```swift
var slide = Slide()
slide.addLine(from: (100, 180), to: (360, 180),
    stroke: Stroke(color: .blue, width: 2, dash: .dash, endArrow: .triangle))
```

線にラベルを置くときは別のテキストボックスを追加します。

## 日本語と欧文のフォント

```swift
let style = TextStyle(
    font: Font(family: "Aptos", size: 20, eastAsianFamily: "Yu Gothic"),
    bold: true, color: .theme("accent1"))
var theme = Theme()
theme.bodyFont.supplementalFamilies["Jpan"] = "Yu Gothic"
var presentation = Presentation(theme: theme)
var slide = Slide()
slide.addText("事業戦略 / Strategy", frame: Rect(x: 40, y: 40, width: 600, height: 80), style: style)
presentation.slides.append(slide)
```

フォントは名前で指定し、閲覧環境のインストール状況で代替されます。
東アジア用の指定と、テーマのscript別指定(Jpanなど)は別です。フォントファイルは埋め込みません。

## リッチな段落

```swift
let paragraph = Paragraph(
    runs: [TextRun("推奨", style: TextStyle(bold: true)), TextRun("：90日間の実証")],
    style: ParagraphStyle(spaceAfter: 8, lineSpacing: 1.2))
let body = TextBody(paragraphs: [paragraph], insets: Insets(12), verticalAlignment: .center)
```

## 整列と均等配置

```swift
var elements = [
    Element(frame: Rect(x: 0, y: 0, width: 120, height: 60)),
    Element(frame: Rect(x: 0, y: 0, width: 180, height: 60))
]
let bounds = Rect(x: 40, y: 160, width: 880, height: 160)
Layout.align(&elements, to: .verticalCenter, in: bounds)
try Layout.distribute(&elements, along: .horizontal, in: bounds)
```

Layoutは座標計算です。文字計測やページへの自動流し込みは行いません。

## 読み取りと一部編集

```swift
let input = URL(filePath: "input.pptx")
var presentation = try Presentation(contentsOf: input)
presentation.slides[0].elements[0].frame?.x = 60
let result = try presentation.write(to: URL(filePath: "output.pptx"), options: WriteOptions(strict: true))
print(result.warnings)
```

未対応要素は原本で保持されます。文字段落や表を書き換える際の警告も検査してください。

## async/awaitとTaskによる読み取り・保存

```swift
func updateTitle(input: URL, output: URL) async throws -> WriteResult {
    var result = try await Presentation.read(contentsOf: input)
    result.presentation.metadata.title = "更新版"
    return try await result.presentation.write(to: output, options: .init(strict: true))
}

let operation = Task {
    try await updateTitle(input: URL(filePath: "input.pptx"),
                          output: URL(filePath: "output.pptx"))
}
let saved = try await operation.value
print(saved.warnings)
```

UI側はoperationを保持し、不要になったら`operation.cancel()`を呼べます。キャンセルは協調的です。URL保存は分割書込境界とatomic確定直前に確認し、最後の確認後は成功し得ます。読み取り・エンコードの実処理は`@concurrent`でMainActorから移します。同期initializerと同期APIも利用できます。

## 上限付き一括読取と対応能力

```swift
let urls = [URL(filePath: "first.pptx"), URL(filePath: "second.pptm")]
let results = try await Presentation.readAll(contentsOf: urls,
    options: .init(includeNotes: false), maxConcurrentReads: 2)
for result in results {
    print(result.presentation.plainText, result.preservationSummary.warningCounts)
}
let capabilities = try CodecSet.all.capabilities(for: .pptx)
print(capabilities[.edit], capabilities[.render]) // partial / unsupported
```

結果順は入力順。同時数は正の整数で、ファイルごとのPackageLimitsを適用します。結果全体を保持するため巨大資料のstreaming用途には使いません。能力概要は個別文書の保存可否を保証しません。

## 機能・プロファイル別の能力と診断

```swift
let capabilities = try CodecSet.all.capabilities(for: .pptx)
let font = capabilities.capability(for: "TXT-003", operation: .read,
    profile: .ooxmlTransitional)
print(font.status, font.notes)
for evidence in font.evidence {
    print(evidence.fixture, evidence.fixtureSHA256, evidence.test, evidence.scope)
}

let result = try Presentation.read(contentsOf: URL(filePath: "input.pptx"))
for diagnostic in result.diagnostics {
    print(diagnostic.code.rawValue, diagnostic.stage, diagnostic.action,
          diagnostic.feature?.rawValue as Any, diagnostic.location, diagnostic.count)
}
```

機能IDは機能台帳と共通です。未掲載の機能・操作・プロファイルはunverifiedとし、別の証拠を転用しません。fixtureの証拠は回帰テストの定義で、実アプリ互換性を証明するものではありません。診断はwarningsと同じ件数を保持し、判明した位置だけを返します。保存結果にも`diagnostics`があります。

## 個別の形式だけリンクする

```swift
import Foundation
import SlideCore
import SlidePPTX

let codecs = CodecSet([.pptx])
let result = try codecs.read(contentsOf: URL(filePath: "input.pptx"))
let output = try codecs.write(result.presentation)
```


## 原本の参照と保存計画

```swift
var deck = try Presentation(contentsOf: URL(filePath: "input.pptx"))
let inventory = try deck.inspectPreservation()
for reference in inventory.references {
    print(reference.kind, reference.knowledge, reference.sourcePart, reference.location)
}
deck.slides[0].elements[0].frame?.x = 60
let plan = try deck.planWrite(options: .init(strict: true))
print(plan.actions, plan.diagnostics, plan.changedExpandedBytes)
if plan.canSave {
    let saved = try deck.save(to: URL(filePath: "output.pptx"), using: plan)
    print(saved.warnings)
}
```

inventoryは原本のXML/relationshipを検査します。保存計画は現在モデルを事前エンコードします。計画後にモデル・原本snapshot・optionsを変更するとstalePlanで拒否するので再計画してください。元URLの外部変更を監視する契約ではありません。canSaveは実アプリ互換性や全CRC確認の証明ではありません。

## 明示的な複製と別資料からの取り込み

```swift
var deck = try Presentation(contentsOf: URL(filePath: "template.pptx"))
let copiedID = try deck.duplicateSlide(id: deck.slides[0].id)
print(copiedID)

let source = try Presentation(contentsOf: URL(filePath: "source.pptx"))
var imported = Presentation(size: source.size)
try imported.importSlide(id: source.slides[0].id, from: source)
let saved = try imported.write(to: URL(filePath: "imported.pptx"))
print(saved.warnings)
```

元のslide値をそのままappendすると重複IDとして拒否されます。明示複製ではnotes/chartと埋込Workbookを独立partへ複製し、同原本の画像・layout/master/themeを共有します。取り込みは同寸法・同OOXMLプロファイルのPPTXに限定します。自己リンクは自動的に新しいslideへ向け、別slideリンクには`SlideImportOptions(slideLinks: [sourceID: destinationID])`を指定してください。未知参照・独自table style・異なるnotes masterの併存・マクロの別文書取り込みは拒否します。

## ODP読取専用と書式索引

```swift
import SlideCore
import SlideODP

let codecs = CodecSet([.odp])
let data = try Data(contentsOf: input)
let result = try codecs.read(data)
let index = try ODPCodec().styleIndex(data)
let style = try index.resolve(name: "NamedStyle", family: "graphic")
print(style.properties, style.origins, style.unresolved)
```

ODPのモデルはautomatic style自身の直接propertyを投影し、named parent/master継承は索引から別に照会します。未解決styleと未知要素は診断を確認してください。ODP保存・PPTXへの暗黙変換は拒否します。

## 一枚ずつ読む

```swift
let reader = try await CodecSet.all.slideReader(contentsOf: input)
let first = try await reader.slide(id: reader.slideDescriptors[0].id)
print(first.slide.plainText)

for try await item in try reader.slides(selection: .all) {
    print(item.slide.id, item.slide.plainText, item.diagnostics)
}
```

PPTXは要求した本文だけ解析します。ODPは開くときに単一XMLを走査しページと書式索引を保持します。未ロードのスライドを削除扱いにしないよう、readerの結果は部分Presentationにしません。

## エンコード済Dataをatomic保存する

```swift
let encoded = try presentation.encoded()
try FileTarget(output).write(encoded.data)
```

通常のURL保存とSavePlan保存もFileTargetを使用します。64KiBずつ一時fileへ書き、確定前の失敗・キャンセルでは保存先を保持します。エンコード済Dataのメモリは必要で、StreamingWriterは未提供です。


## IDを指定した編集と取り消し

```swift
var deck = try Presentation(contentsOf: URL(filePath: "input.pptx"))
let slideID = deck.slides[0].id
let elementID = deck.slides[0].elements[0].id
try deck.editSlide(id: slideID) { slide in
    try slide.editElement(id: elementID) { element in
        element.frame?.x = 60
    }
}
```

グループのchildrenもIDで検索します。対象不在・重複ID・対象のID変更・クロージャーの失敗では変更を反映しません。shapeに既存の文字がある場合は`element.editText { body in ... }`でTextBodyを編集できます。モデルの編集だけでは元形式の保存可否は保証しません。

## 複数の編集を検査してから確定する

```swift
let checked = try deck.transaction { candidate in
    candidate.metadata.title = "更新版"
    try candidate.editSlide(id: slideID) { slide in
        try slide.editElement(id: elementID) { $0.frame?.y = 45 }
    }
}
print(checked.warnings)
try FileTarget(URL(filePath: "output.pptx")).write(checked.data)
```

transactionは現在の元形式のwriterを使い、成功時だけdeckへ反映します。既定のstrict=trueは警告のある書き換えも拒否します。失敗時は文書と原本を維持し、ファイル保存はしません。警告を許容する場合は`options: .init(strict: false)`を明示し、返されたwarningsを確認します。事前エンコードが必要な同期APIです。

## 形式指定・登録照会・非同期の計画エンコード

```swift
let codecs = CodecSet([.pptx, .pptm])
print(codecs.formats, codecs.contains(.odp))
let selected = try codecs.codec(for: .pptx)
print(selected.format)
let opened = try await codecs.read(bytes, format: .pptx)
let summary = try await codecs.inspect(bytes, format: .pptx)
let reader = try await codecs.slideReader(bytes, format: .pptx)
let plan = try await codecs.planWrite(opened.presentation)
let encoded = try await codecs.encoded(opened.presentation, using: plan)
print(summary.slideCount, reader.slideDescriptors, encoded.warnings)
```

umbrellaのread/inspectにも同じ`format:`があります。同期コードではcodecsを省略した`SlideReader(data: bytes)` / `SlideReader(contentsOf: input)`も利用できます。readは内容判定、writeは明示形式→元形式→PPTXで選び、認識できる保存先拡張子との不一致を拒否します。


## 単位付き間隔とフィールドの評価

```swift
let paragraph = ParagraphStyle(lineSpacingValue: .points(18),
                               spaceBeforeValue: .percentage(0.5))
let direct = ParagraphStyle(lineSpacingValue: .percentage(1.2))
let resolvedSpacing = paragraph.overlaying(direct).effectiveLineSpacing
// resolvedSpacingはpercentage(1.2)。割合の測定・配置はレンダラーが行う。
let field = TextField(id: "{11111111-1111-1111-1111-111111111111}",
                      type: "slidenum", cachedText: "1")
let context = TextFieldContext(slideNumber: 2, date: Date(timeIntervalSince1970: 0),
                              localeIdentifier: "en_US_POSIX", timeZoneIdentifier: "UTC")
let evaluated = TextFieldEvaluator.evaluate(field, context: context)
// evaluated.textとdiagnosticsを使う。モデル・原本は変更しない。
```

## 継承元と色変換の読取

```swift
let layoutPath = presentation.slides[0].layoutPath!
let layout = try presentation.readLayout(at: layoutPath)
let master = try presentation.readMaster(at: layout.layout.masterPath!)
// layout/masterのelementsは直接値。サンプル文字をslideへ自動追加しない。
let color = Color.value(ColorValue(base: .scheme("accent1"), transforms: [
    ColorTransform(name: "alpha", value: "50000")
]))
let resolution = ColorResolver.resolve(color, theme: presentation.sourceThemes[0].colors)
// 未解決時はcolor=nilと診断。theme/colorMap/phClrは呼出側で選ぶ。
```

Element.customGeometry / effects / chart / diagramは読取投影です。書換え・新規生成と描画は限定契約の対象外です。単位付き間隔とfieldの基本保存は可能ですが、field更新時はrun.textとfield.cachedTextを一致させます。詳しい境界は[表示用API](display-values.md)を参照してください。
