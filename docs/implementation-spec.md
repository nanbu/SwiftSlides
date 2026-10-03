# SwiftSlides 実装仕様

この仕様はAPIと対応境界の正典。初期開発版、API互換性は未保証。

## 構成と共通モデル

Swift 6.2、Foundation/FoundationXMLとシステムzlib。外部Swift依存なし。
SlideCore: Sendableの値型Presentation/Slide/Element/TextBody/Paragraph/TextRun/Table/Image/Geometry、コーデック契約、ZIP/XML。
SlidePPTX: ECMA-376 / ISO 29500 PresentationML。SwiftSlides:再公開と便利な入口。
寸法はポイント(1 pt = 12,700 EMU)、角度は度。配列はファイル順・描画順。
共通モデルは形式固有のXML名を公開APIの主語にしない。テーマ色・未解決のスタイルは参照として保持し、解決済み外観と混同しない。
ODPはSlideODP、KeynoteはSlideKeynoteとして将来追加。どちらも今回コーデックなし。

## 読み取り

Presentation(data:)/contentsOf、read、inspect。CodecSetで個別リンクも同じ操作。
OPCのroot relationshipからmainPart、スライドrelationshipから順序を解決。固定パスを仮定しない。
PPTX/PPTM、Transitional/Strict、stored/deflated ZIPとZIP64の読み取り。
スライド寸法、名前、表示フラグ、図形/コネクタ/グループ/画像/表、直接指定の文字と段落書式、内部・外部リンク、ノート、メタデータをモデル化。
グループ内座標は親ローカル座標。グループのchildFrameも保持。継承レイアウトとテーマは原本パーツとして保持、外観計算はしない。
画像は内部参照とサイズ・代替文。画像バイトはasset(at:)で必要時にCRC検証・展開。
Chart/SmartArt/OLE/動画/数式/アニメーション/遷移/拡張XMLは未解釈として原本に保持、警告。
未知の図形はopaque要素、元XMLとパーツは保全。
ノート省略指定時は警告、保存時は原本ノートを維持。
OLEコンテナ(旧PPTまたは暗号化Office)、暗号ZIP、壊れたXML、欠落relationship、重複ID、制限超過はthrow。
ODPはmimetypeによる検出のみ。Keynoteはenumと設計を提供、IWAの型判定前にKeynoteとして推測しない。

## 保存

新規PPTX:theme/master/layoutとその参照、presentation、slide、notes、media、content types、metadataを出力。
保存APIはdata(as:options:) / write(to:as:options:) とWriteResult(data,warnings)。URL書き込みはatomic。
既存PPTX/PPTM:元ZIPをバックアップとして所有。未変更保存は原本Dataを返す。
編集保存:不変パーツの展開内容をそのまま保持し、変更ノードをパッチ。既存図形ID・参照・未対応プロパティを維持。
文字編集は文字本体を置換するため、未対応の文字領域書式を含む場合は警告。strict保存は警告のある書き換えを拒否。
スライド追加・削除・並べ替え、要素追加・削除・並べ替えを提供。既存スライドのコピーは二重のidentityを拒否、明示的な新規Slideを使う。
削除したスライドの未参照パーツは残す。リンク等で削除対象を参照する既存XMLは検出して危険な編集を拒否。
図形種類変更、既存グループ構造など安全にパッチできない変更はthrow。失敗を警告だけに変えない。
PPTMのマクロは保持し警告、実行しない。PPTM→PPTXの暗黙変換は拒否。署名済みパッケージは未変更保存のみ許可。
新規modelの不正値(非有限寸法、負のサイズ、重複ID、空画像形式、不正色、非矩形表など)は保存前にthrow。
圧縮保存はDEFLATE、ZIP32のサイズ上限を検査。読める範囲と書ける範囲の違いは明示する。

## 安全性と検証

既定:10,000 ZIP entries、合計512MiB展開、1 part128MiB、XML深さ128、2,000,000 nodes。
上限は宣言サイズ/解析量の制約でありプロセスメモリ保証ではない。DTD/ENTITYを拒否、外部参照は取得しない。
inspectはmain XML/metadataを読むが、全アセットCRC検証を保証しない。保存時に必要な全パーツを展開検証。
独立したpython-pptxによる読み取り・書き込み照合、LibreOfficeで再保存、XML/ZIP破損negative tests、Strictと変則パスfixture、原本パーツ比較、並行読取、個別リンクテスト。
PowerPoint実アプリとiOS実行は実際に検証するまで未検証と明記。

## 一次資料

- [Microsoft: PresentationML structure](https://learn.microsoft.com/en-us/office/open-xml/presentation/structure-of-a-presentationml-document)
- [ECMA-376](https://ecma-international.org/publications-and-standards/standards/ecma-376/)
- [ODF 1.4](https://docs.oasis-open.org/office/OpenDocument/v1.4/)

## PowerPoint互換性の回帰条件

- 新規ノートはスライド画像・本文・スライド番号のプレースホルダーを持ち、ノートmasterを一つ共有する。optional notesMasterIdLstは新規生成しない。既存のリストは保持する。
- DrawingMLのa:tにはxml:spaceを付けない。前後の空白は文字内容として保持する。Paragraph.endTextStyleでendParaRPrを読み書きする。
- 図形書式を変更してもspPrのスキーマ順を維持する。アニメーション・コネクタの参照先要素を削除する編集は拒否する。新規結合表は拒否する。
