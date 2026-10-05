# プレゼンテーション形式の調査

調査基準日: 2026-10-03。将来設計の根拠をまとめた文書。実装状態は[現行仕様](implementation-spec.md)と[対応台帳](support.json)、将来機能は[機能台帳](feature-catalog.md)で管理する。

## 結論と範囲

SwiftSlidesは、形式中立の編集モデルと、元形式の情報を保持するストアを併用する。PPTXとODPは公開仕様に基づいて実装できる。Keynoteは公開された機能説明と解析実装を根拠に、検証したアプリ・文書バージョンを限定して対応する。「全バージョン・全機能の完全互換」は本調査から保証できない。

対象はPowerPoint、LibreOffice Impress、Keynoteが保存するプレゼンテーション文書と、その中に永続化される機能。PDF・画像・動画の出力も計画に含める。共同編集サービス、AI生成、リモコン、クラウド権限管理などはアプリのサービス機能として分ける。ファイルに関連情報が存在すれば保持するが、サービスそのものの再実装は文書コーデックの責務にしない。

機能台帳は実装タスクとして扱える粒度の分類である。XMLの全属性、全列挙値、Protobufの全フィールドを列挙し終えたスキーマ台帳ではない。漏れの閉じ方は後述する。特にKeynoteの将来の拡張を有限のリストで完全に覆うとは宣言しない。

## 「完全再現」の受入条件

| 評価軸 | 達成の意味 | 検証方法 |
|---|---|---|
| 原本一致 | 未変更保存で入力と出力の全バイトが一致 | SHA-256と全バイト比較。ZIP再圧縮とは区別 |
| 保持 | 編集で触れないパーツ・フィールド・参照を保全 | パーツの展開内容、未知フィールド、依存参照を比較 |
| 意味 | 読取→編集→保存後も値・継承・ID・式・順序が同等 | 独立パーサーと実アプリで再読。既定値と省略の違いも検査 |
| 外観 | フォント・配置・折返し・効果が許容差内 | 同一フォント・OS・アプリ版でPDF/画像比較 |
| 動作 | トリガー・順序・時間・メディア再生が同等 | 再生記録、イベント列、アプリでの操作確認 |
| 変換 | 対象形式で表現できる意味を維持し、差を説明 | 変換前後の比較と損失計画。画像化は編集可能性を失う |

未知の要素を保存できることと、その意味を読み取り編集できることは別の能力。アプリが修復要求なしで開くことだけでも完全再現の証明にはならない。独立パーサーも扱える機能が限定されるため、単独の判定基準にはしない。

## PowerPoint

### 形式の系統

| 形式 | 構造・意味 | 計画上の扱い |
|---|---|---|
| `.pptx` | OOXMLの通常プレゼンテーション。Strict/Transitionalを区別 | 最初の中核。両プロファイルの読取・保持・生成を別々に検証 |
| `.pptm` | マクロを含み得るOOXML | VBAを保持。実行は別領域。マクロ削除は明示的な変換 |
| `.potx` / `.potm` | OOXMLテンプレート | document kindとcontent typeを正しく保存 |
| `.ppsx` / `.ppsm` | OOXMLスライドショー | 起動種別を維持。通常プレゼンテーションと拡張子だけで扱い分けない |
| `.ppt` / `.pot` / `.pps` | 97–2003系バイナリ文書 | CFBとMS-PPTの別コーデック。OOXMLのパーサーでは読めない |
| `.thmx` | Officeテーマ | テーマの入出力として別途対応 |
| PDF / XPS / 画像 / 動画 / RTF | 配布・描画・アウトライン用途 | 入出力能力と編集文書の忠実度を別表示 |

Microsoftの形式一覧は通常文書、テンプレート、マクロ、ショー、Strict、テーマ、各種出力を区別している。旧バイナリ文書の仕様はMS-PPTに分かれる。[S04](https://learn.microsoft.com/en-us/office/compatibility/office-file-format-reference)、[S05](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-ppt/6be79dde-33c1-4c1b-8ccc-4b2301c08662)

### OOXMLを読むために必要な層

ECMA-376はPart 1のマークアップ、Part 2のOPC、Part 3の互換拡張、Part 4のTransitional機能からなる。各Partの版日は異なり、規格ページの「2021年第5版」を全Part共通の更新日と見なさない。[S01](https://ecma-international.org/publications-and-standards/standards/ecma-376/)

実装はZIP→content types/relationships→PresentationML→DrawingML→Office拡張の順で分ける。スライド、レイアウト、マスター、ノート、配布資料は別パーツに分かれるため、スライドXMLだけを読んでも文書を再現できない。[S02](https://learn.microsoft.com/en-us/office/open-xml/presentation/structure-of-a-presentationml-document)

Office固有の拡張はMS-PPTXなどのOpen Specificationsで追跡する。たとえばMorphはMS-PPTXの拡張で、物体・単語・文字の対応付けに違いがある。汎用の「フェード遷移」に置き換えるだけでは元の動作を維持できない。[S03](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-pptx/efd8bb2d-d888-4e2e-af25-cad476730c9f)、[S03-PDF §2.6](https://officeprotocoldocs-f5hpbjgea6b8gneq.b02.azurefd.net/files/MS-PPTX/%5BMS-PPTX%5D.pdf)

暗号化Office文書にはCFB内の暗号情報とパッケージを処理する層が必要。旧PPTにも別の暗号化規則がある。コンテナ先頭がOLEであることだけでは旧PPTと暗号化OOXMLを区別できない。[S06](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-offcrypto/11dfbc00-031a-44bc-a836-e7b9872438fd)、[S05-暗号](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-ppt/b0963334-4408-4621-879a-ef9c54551fd8)

### 実装上の論点

以下は上記構造から導くSwiftSlidesの設計要件。

- relationshipは固定ファイル名から推測せず、相対URI・外部URI・target mode・循環・欠損を扱う。
- shape ID、slide ID、relationship ID、creation IDを混同しない。コピーでは依存グラフごとIDを振り直す。
- テーマ色・色変換・フォント・背景・プレースホルダー・段落既定値の継承を解決する。省略を黒やゼロに置換しない。
- `mc:AlternateContent`の選択と元の全分岐保持を分ける。知らない拡張を削除しない。
- SmartArt、チャートの埋込Workbook、OLE、メディア、フォント、コメント等のサブグラフを保持する。
- 編集範囲を最小化する。親ノードの作り直しでタイミング参照や拡張を書き落とさない。

## LibreOffice Impress / OpenDocument

### 形式と仕様

中心は`.odp`、テンプレートは`.otp`、単一XML表現は`.fodp`。LibreOfficeのフィルター一覧には旧`.sxi` / `.sti`も存在する。フィルター一覧への掲載だけでは、読取と保存の両方向や完全忠実度を保証しない。[S09](https://help.libreoffice.org/latest/en-US/text/shared/guide/convertfilters.html)

本調査ではODF 1.4 OASIS Standardを新しい仕様の参照点とする。既存資料向けに1.0–1.3とExtendedを別プロファイルとして試験する。ODF 1.4のPart 2はパッケージ、署名、暗号、メタデータを規定し、`mimetype`の配置と非圧縮などの条件を持つ。[S07](https://docs.oasis-open.org/office/OpenDocument/v1.4/os/part2-packages/OpenDocument-v1.4-os-part2-packages.html)

Part 3には描画、文字、表、チャート、フォーム、アニメーション、プレゼンテーション、スタイルの語彙がある。内容は`content.xml`だけで完結せず、名前付きスタイル・自動スタイル・マスター等を解決する必要がある。[S08](https://docs.oasis-open.org/office/OpenDocument/v1.4/OpenDocument-v1.4-part3-schema.pdf)

LibreOfficeの読書き実装にはODF標準の名前空間以外のマッピングもある。Extendedを標準版と混同せず、`loext:`等の情報を保持・診断する。[S10](https://raw.githubusercontent.com/LibreOffice/core/master/xmloff/source/draw/sdpropls.cxx)

### 設計要件

- ZIP版とFlat XML版の読書きを分離し、単位文字列を数値と元表現の両方で保持する。
- `styles.xml`、`content.xml`、`meta.xml`、`settings.xml`、manifest、画像・埋込オブジェクトを関連付ける。
- page layout、master page、drawing page style、presentation style、text styleの継承を別系統で扱う。
- リスト、空白の繰返し、タブ、改行、ruby、縦書き、表の繰返し行/列・結合セルを展開予算つきで処理する。
- enhanced geometry、接続点、transform、レイヤー、SMIL系の時間構造を形式固有情報と共通モデルに分ける。
- 埋込チャート・Calc・数式・OLE等を独立した文書として保全する。未知オブジェクトを空の図形に変えない。
- 単一の大きな`content.xml`をスライドごとに安全に読む。PPTX同様の「1枚1パーツ」と仮定しない。

## Apple Keynote

### 公開情報と解析情報を分ける

実装・実アプリ確認の対象は検証時点の最新版Keynoteだけとする。確認した版・OS・registryを記録し、旧版確認を公開の必須条件にしない。以下の世代差の調査は入力判定と安全な拒否のために残し、旧版対応を約束するものではない。

AppleはKeynoteの機能・書き出し・単一ファイルとパッケージの扱いを説明している。本調査でAppleが公開する完全な`.key`書込みスキーマ・全内部フィールド仕様は確認できなかった。非公開であること自体を数学的に証明した、という意味ではない。[S11](https://support.apple.com/guide/keynote/welcome/mac)、[S12](https://support.apple.com/en-il/119883)、[S13](https://support.apple.com/en-gb/105050)

iWork '13の解析資料は、Data/Metadata/Index、IWA、Snappyによる圧縮、ProtobufのArchiveInfo/MessageInfo、オブジェクト参照を説明している。型IDの対応はKeynote・Numbers・Pagesで異なる。これはAppleの規範仕様ではなく、解析者による一次観察であり、現在の全バージョンの保証に使えない。[S14](https://raw.githubusercontent.com/obriensp/iWorkFileFormat/master/Docs/index.md)

keynote-parserはアプリから抽出した型定義を使用し、Keynoteの更新で解析不能になる可能性を明記している。実装を参照する場合はライセンス・版・抽出物の由来を記録する。自動でアプリバイナリを改変したり型定義を抽出したりする工程は今回実施していない。[S15](https://github.com/psobot/keynote-parser)

### 必要な機能と固有差分

Keynoteにはレイアウト、図形、メディア、縦書き、数式、表・チャート、ビルド、ノート等がある。特に表の数式、インタラクティブチャート、Magic Moveは共通の静的図形だけでは表せない。[S11](https://support.apple.com/guide/keynote/welcome/mac)、[S16](https://support.apple.com/en-euro/guide/keynote/tanfb0588a84/mac)、[S17](https://support.apple.com/en-euro/guide/keynote/tan1a8924264/mac)、[S18](https://support.apple.com/en-euro/guide/keynote/tanff5ae749e/mac)

数式入力はLaTeX/MathML、録画はナレーションと再生記録を含む。原式・見た目・時間構造を分けて保持する設計が必要。[S19](https://support.apple.com/en-au/guide/keynote/tan72a69d01f/mac)、[S20](https://support.apple.com/guide/keynote/record-presentations-tan81813d552/mac)

Keynoteコーデックの調査対象は、現行IWA系`.key`と`.kth`、旧XML系文書、ZIP・ディレクトリ・Index.zipを含む世代差、暗号化。各形態の対応可否は実サンプルで確定する。プレビュー画像や拡張子だけでKeynoteと判定しない。

設計では次を必須とする。

- 文書・スライド・drawable・style・text storage・table・chartのグラフを型IDと世代ごとに索引化。
- 未知Protobufフィールドはwire表現を保持し、未知オブジェクト・未知参照は変更可能範囲を制限。
- 圧縮とメッセージ長、object/data references、メディアのメタデータを編集時に整合させる。
- 未検証世代は検査結果に記録し、安全性を判断できなければ編集保存を拒否。
- 原本編集を先に対応。ゼロからの`.key`生成は、必要な既定オブジェクト群が実アプリで検証できてから追加。

## SwiftSheetsから参考にするもの

ローカルコードの参照時点: SwiftSheets `d153773`。公開リンクは参照位置を示す。ローカルコミットが公開リモートに存在するかは検証していない。

| 参照API/実装 | SwiftSlidesへの反映 | そのまま移さないもの |
|---|---|---|
| [Facade](https://github.com/nanbu/SwiftSheets/blob/main/Sources/SwiftSheets/Facade.swift): Workbookのread/inspect/write/convert | Presentationに同じ入口と結果型 | 拡張子による保存先形式決定を追加するなら移行契約を設ける |
| [CodecSet](https://github.com/nanbu/SwiftSheets/blob/main/Sources/SheetCore/Codec/CodecSet.swift): 部分リンク | SlideCoreと必要な形式だけリンク | SwiftSlidesの公開PresentationCodecを急に非公開にしない |
| [PreservationSummary](https://github.com/nanbu/SwiftSheets/blob/main/Sources/SheetCore/Codec/PreservationSummary.swift) | 保持物の概要と変換前検査 | 件数ゼロを「損失なし」の証明としない |
| [Workbook/Sheets](https://github.com/nanbu/SwiftSheets/blob/main/Sources/SheetCore/Model/Workbook.swift): 値型Collectionと_modify | 添字編集のCOWコストを測定し抑える | スライド名は一意とは限らず、名前での自動追加を採用しない |
| StreamingReader / StreamingWriter | 1枚単位の読取、追記保存、原子的確定 | 行列単位、セル式前提、無制限の非同期バッファを移植しない |
| IWA.swift / Snappy.swift / Protobuf.swift / NumbersObjectStore.swift | 低層コーデックと遅延オブジェクト索引の検討 | Numbers用型ID・モデル・破損時fallbackをKeynoteに流用しない |
| SheetDecrypt / SheetEncryptの分離 | 暗号処理をオプション製品に分離 | SheetCoreへの依存をSlideCoreへ持ち込まない |

再利用候補は責務の分離とアルゴリズム。コピーペーストや共通ライブラリ抽出を今回の前提にしない。低層IWAには展開上限、整数overflow、未知フィールド、壊れたSnappyの明確な失敗を追加検証する。

## 機能の漏れを閉じる方法

機能台帳に加えて、実装開始時に次の詳細台帳を生成する。

| 元情報 | 列挙する単位 | 各項目に必須の記録 |
|---|---|---|
| OOXML XSD・Office拡張・MS-PPT | QName/型/属性/列挙値/record type | 規格版、親型、台帳ID、read/write/edit/preserveの状態、fixture、負例 |
| ODF RNG・プロパティ表・LibreOffice拡張 | 要素/属性/値/スタイルfamily | ODF版、Extendedの区別、台帳ID、fixture、適用対象 |
| Keynote型定義・実サンプル | type ID/field number/wire type/参照 | アプリ版、抽出物の由来、未知型の割合、未検証範囲、fixture |

規格全体からプレゼンテーションで到達可能な型を辿り、未分類ゼロを目指す。対象外は理由を記録する。未知要素・未知フィールド検出から台帳へ追加する。共通APIで編集する項目と原本保持だけの項目を混同しない。

「完全」の表示は、対象バージョン・機能集合・評価軸ごとに証拠が揃ってから行う。Keynoteの未知世代は常に別の未検証範囲として残す。

## 一次資料の索引

上記S01–S20は規範仕様、提供者資料、解析実装を区別して引用した。ECMA/OASISの規範スキーマと本文を優先し、Microsoft/LibreOffice/Appleの機能説明を実アプリ検証の補助に用いる。解析資料は実現性の根拠に限定する。仕様の全文や抽出スキーマをこのリポジトリへ転載しない。

追加実装で必要になる関連仕様: MS-OI29500（Officeの規格実装差）、MS-ODRAW（旧描画）、MS-CFB（Compound File）、MS-OVBA（VBA）、MS-OFFCRYPTO（暗号）、DrawingMLチャート・Office拡張、OpenFormula、SMIL関連語彙。ここでは個別規則を網羅したと主張せず、着手時に版を固定して詳細台帳へ登録する。
