# ``SwiftSlides``

提案書・分析資料を、形式中立のSendable値モデルで作成し、PowerPointファイルを読み書きします。

## Overview

開発中・API互換性は未保証。PPTX/PPTMの読み取りと保存、図形・線・フォント・文字書式・表・レイアウトを提供します。
ODPとKeynoteは将来コーデックの設計のみ。描画、継承した実効外観、文字計測は提供しません。
詳しい境界は[対応表](https://github.com/nanbu/SwiftSlides#対応範囲)を参照してください。

```swift
import Foundation
import SwiftSlides
var slide = Slide()
slide.addText("提案資料", frame: Rect(x: 40, y: 30, width: 800, height: 60),
    style: TextStyle(font: Font(size: 30), bold: true))
let presentation = Presentation(slides: [slide])
try presentation.write(to: URL(filePath: "proposal.pptx"))
```

## Topics

### 読み取りと保存

- ``Presentation``
- ``PresentationSummary``
- ``PresentationFormat``
- ``ReadOptions``
- ``WriteOptions``
- ``ReadResult``
- ``WriteResult``
- ``SlideWarning``
- ``SlideError``
- ``PackageLimits``
- ``PackagePart``
- ``Metadata``

### スライド・図形・線・レイアウト

- ``Slide``
- ``Element``
- ``ShapeGeometry``
- ``Fill``
- ``Color``
- ``Stroke``
- ``Arrowhead``
- ``Image``
- ``Placeholder``
- ``Rect``
- ``Size``
- ``Insets``
- ``Layout``

### 文字とフォント

- ``TextBody``
- ``Paragraph``
- ``TextRun``
- ``TextStyle``
- ``Font``
- ``ParagraphStyle``
- ``TextAlignment``
- ``VerticalAlignment``
- ``Bullet``
- ``Link``
- ``Theme``
- ``ThemePart``

### 表

- ``Table``
- ``TableCell``

### コーデックとガイド

- ``PresentationCodec``
- ``Codec``
- ``CodecSet``
- ``PPTXCodec``
- <doc:Reading>
- <doc:Cookbook>
