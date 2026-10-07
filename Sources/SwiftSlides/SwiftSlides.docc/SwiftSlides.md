# ``SwiftSlides``

提案書・分析資料を、形式中立のSendable値モデルで作成し、PowerPointファイルを読み書きします。

## Overview

開発中・API互換性は未保証。PPTX/PPTMの読み取りと保存、図形・線・フォント・文字書式・表・レイアウトを提供します。
Swift 6.4のasync/await・`@concurrent`・構造化TaskGroupによる非同期I/O、一括読取、協調キャンセルを提供します。
ODPは読取専用codecと限定書式索引を提供し、Keynoteはwire試作のみで公開codecは未提供。描画、継承した実効外観、文字計測は提供しません。
詳しい境界は[対応表](https://github.com/nanbu/SwiftSlides#対応範囲)を参照してください。

```swift
import Foundation
import SwiftSlides
var slide = Slide()
slide.addText("提案資料", frame: Rect(x: 40, y: 30, width: 800, height: 60),
    style: TextStyle(font: Font(size: 30), bold: true))
let presentation = Presentation(slides: [slide])
let result = try presentation.write(to: URL(filePath: "proposal.pptx"))
print(result.warnings)
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
- ``PreservationSummary``
- ``PackageGraph``
- ``PackageReference``
- ``ReferenceLocation``
- ``SourceIdentity``
- ``SavePlan``
- ``SavePartAction``
- ``SlideImportOptions``

### スライド・図形・線・レイアウト

- ``Slide``
- ``Element``
- ``CustomGeometry``
- ``GeometryPath``
- ``PathCommand``
- ``GeometryPoint``
- ``GeometryGuide``
- ``ElementEffects``
- ``VisualEffect``
- ``OuterShadow``
- ``StyleReference``
- ``SlideLayoutPart``
- ``SlideMasterPart``
- ``SlideLayoutReadResult``
- ``SlideMasterReadResult``
- ``Chart``
- ``ChartGroup``
- ``ChartSeries``
- ``ChartData``
- ``ChartPoint``
- ``ChartAxis``
- ``Diagram``
- ``PartReference``
- ``ShapeGeometry``
- ``Fill``
- ``Color``
- ``ColorValue``
- ``ColorBase``
- ``ColorTransform``
- ``ColorResolver``
- ``ColorResolution``
- ``ResolvedColor``
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
- ``TextSpacing``
- ``TextListStyle``
- ``TextStyleLevel``
- ``TextField``
- ``TextFieldContext``
- ``TextFieldEvaluator``
- ``TextFieldEvaluation``
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
- ``PreservationInspectingCodec``
- ``SlideImportingCodec``
- ``Codec``
- ``CodecSet``
- ``PPTXCodec``
- ``CodecCapabilities``
- ``CapabilityOperation``
- ``CapabilityStatus``
- ``FeatureID``
- ``CapabilityProfile``
- ``FeatureCapability``
- ``CapabilityEvidence``
- ``SlideDiagnostic``
- ``DiagnosticCode``
- ``DiagnosticLocation``
- ``DiagnosticStage``
- ``DiagnosticSeverity``
- ``DiagnosticAction``
- <doc:Reading>
- <doc:Cookbook>

### 表示用の情報

- <doc:display-values>
