# 読み取りと保存の契約

## Overview

`Presentation(contentsOf:)`/`data:`は共通モデルと`readWarnings`を返します。
`Presentation.read`は`ReadResult`、`inspect`は本文モデルを構築せずに寸法・枚数・metadata・partsを返します。
画像は`asset(at:)`で必要時に展開してCRCを検査します。外部参照は取得しません。

モデルの寸法はポイント、角度は度。グループ内はローカル座標です。
Font/Color/Strokeは直接指定または生のテーマ参照。sourceThemesには原本テーマ定義を投影します。
レイアウト・マスターの直接値はreadLayout / readMasterで取得でき、継承の自動適用は行いません。ColorValueは順序付き変換を保持し、ColorResolverは透明度系だけを初期解決します。

`encoded`/`write`は保存bytesと警告、`data`はbytesだけを返します。
PPTX/PPTMの未変更保存は原本bytes。編集保存は変更XMLを再直列化し、未変更パーツの圧縮済payloadを転写します。
文字段落や表の再構成は未対応書式を落とす場合があるため警告し、strictは警告のある変更を拒否します。
PPTMの形式変更、既存テーマ・layout変更、opaque要素編集、署名付き文書の編集は拒否します。

ZIPとXMLの上限は解析量の上限で、プロセスメモリ予算ではありません。
inspectと未変更パーツ転写は全CRC検証ではありません。展開するパーツでCRCを検査します。
Swift 6.4 / Swift 6言語モード。同期codec契約に加え、read / inspect / data / encoded / write / assetのasync overloadを提供します。実処理は`@concurrent`で呼出元Actorから移り、Task localとキャンセルを引き継ぎます。FoundationのファイルI/O自体は同期です。

`readAll(contentsOf:options:maxConcurrentReads:)`はTaskGroupで同時数を制限し、入力順に返します。失敗・親キャンセルで残りをキャンセルし、終了を待ってthrowします。同時数は全体メモリ上限ではありません。
キャンセルは展開・圧縮chunk、XML callback、スライド・要素境界で確認します。URL保存は一時fileへの分割書込境界とatomic確定直前に確認し、最後の確認後は成功し得ます。同名overloadの追加により、async文脈では既存呼出しにもawaitが必要になる場合があります。

`CodecSet.capabilities(for:)`の未宣言能力はunverified、未登録形式はnoCodecです。`preservationSummary`は原本bytes・パーツ数・現在のopaque要素数・読取時警告を展開なしで返します。詳細依存や変換可否の証明ではありません。

`capabilities.capability(for:operation:profile:)`は機能ID・操作・プロファイルが一致する宣言とfixtureの証拠を返します。StrictとTransitionalは別々に照会し、未掲載はunverifiedです。証拠は回帰テストの定義への参照で、実アプリ互換性の保証ではありません。

`ReadResult.diagnostics`と`WriteResult.diagnostics`はwarningsの構造化投影です。安定コード、read/write段階、処理内容、判明した機能IDと位置、件数を返します。位置のsourceElementはXML名等であり、モデルelementIDとは別です。元のwarningsとstrict保存の規則も維持しています。


## ODPと選択reader

ODPは読取専用で、基本文字・図形・画像・表・ノートを投影し原本を保持します。named/masterの継承書式はモデルへ埋めず、SlideODPの書式索引で限定解決します。保存・変換は未提供です。

SlideReaderはsnapshotと不変索引を共有し、要求したスライドをSlideReadResultとして返します。PPTXは本文を選択解析します。ODPは索引作成時のXML全走査が必要です。AsyncSequenceはnext()ごとに1枚読み、先読みはしません。元URLの変更監視とfile-backed ZIPは未提供です。


## ID編集と文書単位の検査

editSlide(id:_:) / editElement(id:_:) / editText(_:)は仮の値を編集し、クロージャーの正常終了時だけ反映します。要素検索はgroup内も含みます。対象不在・重複ID・対象ID変更は拒否します。保存可否はwriterで別途検査します。

transaction(options:_:)は複数の編集をwriterで検査し、成功時だけ反映してWriteResultを返します。strictの既定はtrue、ファイル保存は行いません。事前エンコードの時間とメモリが必要です。write/save/transactionの戻り値は警告を確認するか、明示的に`_ =`で破棄します。

Data入口のread/inspectとSlideReaderは明示formatを受けます。CodecSet.formats / contains / codec(for:)で登録を照会し、CodecSet.slideReaderのasync入口では索引構築も呼出元Actorから移します。SlideReader.assetとSavePlanを使うencodedにもasync overloadがあります。

URL保存は明示形式→元形式→PPTXで選び、拡張子によって変換しません。認識できる拡張子が出力形式と違う場合はoutputFormatMismatchで拒否し、保存先を変更しません。


## 表示用の直接値

TextSpacingはpointsとpercentage（100%=1）を区別します。ParagraphStyleのeffectiveLineSpacing / effectiveSpaceBefore / effectiveSpaceAfterは新しい単位付き属性を旧Double属性より優先します。overlaying(_:)は指定属性だけを単位ごと上書きし、0を未指定へ変えません。TextBody.listStyle、Presentation.defaultTextStyle、masterのtextStylesは継承前の直接値です。

TextRun.fieldはID/type/cacheとfield内の段落書式を保持します。TextFieldEvaluatorは明示された日時・locale・timeZone・slideNumberから評価し、未知typeや特殊暦はキャッシュと診断を返します。評価は原本を変更しません。保存する更新ではrun.textとfield.cachedTextを合わせます。firstSlideNumberとslideNumber(for:)は非表示も含む現在の文書順を使います。

Color.value、Element.customGeometry / effects / chart / diagramは原本の追加投影です。未対応の色変換・guide・arc・高度な効果は保持と診断を優先します。chartの点列は疎なindex付きで、欠落値を0へ変えません。diagramは保存済みdrawingとデータ文字を返し、自動配置しません。chartとdiagramのkindはopaqueを維持します。

新しい投影を変更した保存と新規生成は拒否します。自由曲線や影を持つ既存要素の位置編集では原本XMLを維持します。master/layout読取には同期・async入口があり、原本と取り込み済みパーツを読みます。element IDはpart pathと組にして識別します。描画順・showMasterSp・色map・themeOverrideの適用と文字測定は呼出側の責務です。
