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

## 個別の形式だけリンクする

```swift
import Foundation
import SlideCore
import SlidePPTX

let codecs = CodecSet([.pptx])
let result = try codecs.read(contentsOf: URL(filePath: "input.pptx"))
let output = try codecs.write(result.presentation)
```
