# API全体レビューに伴う移行

SwiftSlidesは未リリースで、API互換性は未保証。SwiftSheets 1.0の公開範囲と命名規則に揃えた変更を以下に記す。

| 従来 | 現行 |
|---|---|
| `ReadOptions(includeNotes:)` / `.includeNotes` | `includesNotes:` / `.includesNotes` |
| `Slide.showMasterShapes` / `SlideLayoutPart.showMasterShapes` | `showsMasterShapes` |
| `GradientFill` / `PictureFill` / `OuterShadow` の `rotateWithShape` | `rotatesWithShape` |
| `SlideTransition.advanceOnClick` | `advancesOnClick` |
| `TextBody.wrap` / `wrap:` | `wrapsText` / `wrapsText:` |
| `Element.flipHorizontal` / `flipVertical` | `isFlippedHorizontally` / `isFlippedVertically` |
| `PPTXCodec()`等の組込実装型 | `CodecSet([.pptx])`等の選択値 |
| `ODPCodec().styleIndex(data)` | `ODPStyleIndex(data: data)` |

Boolはプロパティとinitializerラベルを同時に変更した。CodableモデルのJSONキーとファイル形式の属性名は従来のまま。`false`と未指定の`nil`を区別する。

保存は`let result = try presentation.write(as: .pptx)`、計画済みなら`write(using: plan)`、URLへは`write(to: url, using: plan)`を使う。`result.warnings`を確認する。旧`encoded` / `data` / `save`は削除した。bytesのみ必要なら結果の`.data`を取り出す。

URLのread / inspect / slideReaderにも`format:`を追加した。省略時の動作は内容判定のまま。従来の呼出しはコンパイルできるが、メソッド全体を関数値として参照していた場合は追加引数に合わせる。password付き入口、file-backed reader、`readAll`も同じ指定を受ける。

`ReadOptions`のindexedCacheBytes・odfTransformAngleUnit・geometryProviderもinitializerで渡せる。`SlideReader(fileBackedURL:cacheBudget:)`と`codecs.fileSlideReader(contentsOf:cacheBudget:)`は合計予算を圧縮bytesと展開索引へ半分ずつ割り当てる。これはプロセス全体のメモリ上限ではない。

第三者codecのprotocolは公開のまま。`PresentationSlideSource`はsummary件数とdescriptor数を一致させ、descriptor.indexを0からの配列位置に揃え、空・重複IDを使わない。不正な実装はreaderを開く時点でthrowする。

## 0.1.0の公開前整理

- `data(as:options:)`は`write(as:options:).data`へ、`encoded`と`save`は`write`へ移行する。同期・非同期とも旧別名は削除した。
- `inspect(..., limits: limits)`は`inspect(..., options: .init(limits: limits))`へ。公開PresentationCodecの実装もInspectOptionsを受け取る。
- `SlideError.noCodec(format)`は`noCodec(for: format)`、`unsupportedEncryption(detail)`は`unsupportedEncryption(detail: detail)`へ。
- WriteResultのdataとwarningsはlet。加工した結果は新しいWriteResultで構築する。編集対象のPresentationは引き続き値型で変更できる。

planWriteはPowerPointの必須手順ではない。保存前にパーツ差分と警告を確認し、確認済みbytesを保存したい場合だけ使用する。
通常保存はwriteのみでよい。計画作成でエンコード・fingerprint計算が発生し、保持中は出力Dataがメモリに残る。
