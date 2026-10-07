# 表示用の情報を読む

SwiftSlidesは原本の値と参照を提供する。文字測定、実効継承、ピクセル描画、ぼかし、グラフの描画は呼出側で実行する。読み書きの共通契約は<doc:Reading>を参照。

| 提案 | 判断 | 今回の範囲 |
|---|---|---|
| A 単位付き間隔 | 採用 | points / percentage、明示的0、属性ごとのoverlay、直接値・文字既定、基本保存 |
| B フィールド | 採用 | ID / type / cache / 書式、番号・Gregorian日時の明示評価、基本保存 |
| C 色変換 | 採用、解決は限定 | 基本色と順序付き変換を保持。初期の実効値計算はsRGB / scheme / phClrと透明度系 |
| D master / layout | 採用 | 共通Element、表・画像、参照鎖、文字既定、色map、showMasterSp、背景参照、themeOverride |
| E 自由曲線 | 採用、数値パスを優先 | move / line / quadratic / cubic / close。arc / guide式は保持と診断 |
| F 影 | 採用 | 外側の影の直接値、effectRef、テーマeffect style。合成は呼出側 |
| G チャート | 採用、cacheを優先 | 2D bar / line / pieを中心に系列、疎な点列、cache / literal / formula、軸、タイトル、凡例、元XML |
| H SmartArt | 採用、保存済みdrawingを優先 | 関連パーツとデータ文字、保存済み図形・文字・接続線を共通Elementへ投影 |
| I 高度な機能 | 段階追加を保留 | 追加の色計算、guide評価、円弧評価、内側の影等の合成、追加チャート。自動SmartArt配置・3D・アニメーションは独立した能力として設計が必要 |

C〜Hの新しい投影は読取専用。読取対応からcreate / edit / render対応を推測しない。既存の位置編集は原本の自由曲線・効果XMLを保全する。新しい投影の変更、新規生成、自由曲線のプリセットへの置換は拒否する。

## 間隔とフィールド

`ParagraphStyle.effectiveLineSpacing` / `effectiveSpaceBefore` / `effectiveSpaceAfter`は新しい単位付き属性を優先する。旧Double属性も残るが、読取後の新しい属性を変更せず旧属性だけを変えても優先されない。`overlaying(_:)`は単位ごと上書きする。割合段落余白はレンダラーが測った行高へ適用する。

`TextFieldEvaluator.evaluate(_:context:)`は評価結果と診断を返し、runや原本を更新しない。保存する場合は`TextRun.text`と`TextField.cachedText`を同じ新しい表示値へ変更する。`slideNumber(for:)`は非表示も含む現在の順序と`firstSlideNumber`から番号を求める。未知type、不正ID、特殊暦、無効なタイムゾーンはキャッシュへ戻る。`datetime`は明示されたlocaleのshort date/timeを使う。

日時形式は[Microsoftのfld仕様](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oi29500/209a8afb-4ce6-4ad9-ad6b-f18da263502e)を根拠とする。各OS・localeでのOfficeとの完全一致は未検証。

## 継承元と色

`readLayout(at:)` / `readMaster(at:)`の戻り値は`layout` / `master`と`warnings` / `diagnostics`を持つ。原本または取り込み済みのパーツを対象とする。継承済みElementをslideへ追加しない。プレースホルダーIDはpart pathと組にして照合する。サンプル文字や描画順、showMasterSp、idxの曖昧さの扱いは呼出側で判断する。

`sourceThemes`は通常themeとthemeOverrideを含み、`ThemePart.isOverride`で区別できる。適用するthemeと色mapは呼出側が選ぶ。テーマ定義側の変換を適用してから使用箇所の変換を適用する。system色はfallbackを保持するが、初期Resolverは実効色として代用しない。

`Color.value`は追加のenum case。既存のColorを網羅的にswitchする利用者はこのcaseも処理する必要がある。`ColorResolver`は解決できない基本値・変換を含む場合にcolor=nilと診断を返す。色変換をRGB文字列へ焼き込まない。XMLの順序と透明度のclampは[DrawingML Primer](https://download.microsoft.com/download/e/1/4/e14fb96f-83b8-4a2a-84db-7fa8acbe061a/Office%20Open%20XML%20Part%203%20-%20Primer.pdf)に従う。

## チャートとSmartArt

`Element.kind`はopaqueを維持し、`chart` / `diagram`を任意の追加投影として提供する。`ChartData.points`は疎なindex付き配列で、point欠落を0へ補わない。`ChartPoint.number`がnilなら字句を参照する。cacheのないreferenceでもformulaを保持する。外部データ・埋込workbookは自動取得・再計算しない。高度なラベルや点別書式等はrawXMLと診断を参照する。

`Diagram.elements`は保存済みdrawingのローカル座標。`drawingFrame` / `drawingChildFrame`から親への配置を行う。drawingがない場合はdataTextsと診断だけを使い、自動配置を原本再現とみなさない。Office drawing拡張の根拠は[MS-ODRAWXML](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-odrawxml/06cff208-c6e1-4db7-bb68-665135e5f0de)。

合成fixtureは構文・値・保存境界を検証する。実PowerPoint・Keynote・LibreOfficeでのピクセル一致、フォント測定、全チャート・SmartArtの互換性はこの検証の対象外。
