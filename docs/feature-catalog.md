# 読み書き再現の機能台帳

将来設計。`feature-catalog.json`から生成。直接編集せず、`python3 scripts/build-feature-catalog.py`を実行する。整合検査は`--check`。

19分類・217機能。基準日: 2026-10-03。現行SwiftSlides参照: `193495f`。

[形式調査](format-research.md) · [API設計](api-design.md) · [実装計画](implementation-roadmap.md) · [実装済み対応表](support.json)

## 台帳の読み方

これは完全再現のための作業分類であり、全スキーマ属性の列挙完了や互換性保証ではない。分類ごとの形式欄は調査・実装で扱う表現と探索先であり、全機能が3形式に存在するという主張ではない。形式固有の項目は共通モデルへ丸めず、固有モデルまたは原本として保持する。Keynoteの内部フィールドは実サンプルと型registryで確定する。

各行は原則として次の5方向で分解して実装・検証する。実装時には形式・プロファイルごとの状態とfixtureを追加する。

| 方向 | 共通の受入条件 |
|---|---|
| 読取 | 値・省略・参照・順序を区別。未知情報は位置つき診断と原本保持。破損を空データに変えない |
| 新規生成 | 対象形式に存在する機能だけを有効な構造で出力。存在しない機能はnotApplicable/unsupported |
| 編集保存 | 変更対象と必要な依存だけを更新。参照・未知情報・署名への影響を検査 |
| 原本保持 | 未変更保存は全バイト一致。部分編集は対象外パーツと未知フィールドを保全 |
| 形式変換 | 表現可能な意味を移す。外観・動作・編集可能性の差を計画に出し、許可のない損失を拒否 |

現行欄はPPTX/PPTMのコード調査による概要。行の全受入条件の達成や、新しい実アプリ検証を意味しない。ODPはmimetype検出のみで読書きコーデックなし、Keynoteもコーデックなし。両形式の各行の実装状態はすべて未実装。原本保持中心でも任意編集を許可する意味ではなく、影響が安全と判断できる範囲だけ保存できる。

| 現行欄 | 意味 |
|---|---|
| 基本範囲あり | 基本のread/write/editがあるが行の全条件は未達 |
| 部分対応 | 読取と生成・編集で境界が異なる |
| 原本保持中心 | 未解釈または未対応部分を原本で保持。編集モデルは不十分 |
| 未実装 | 専用のAPI/処理なし |
| 拒否 | 現行では明示的に失敗する |
| 対象外 | PPTX固有の実装状態としては該当しない |

工程は主なモデル・初回対応を入れる順番。P2はODP読取、P3はODP生成・編集、P6はKeynote、P7は旧形式・暗号、P8は描画・再生。共通機能の工程表示だけで全形式の同時完成を意味しない。

## PKG コンテナと形式

拡張子だけで判定せず、プロファイルと原本構造を維持する。

| 形式 | 表現・探索先 |
|---|---|
| PPTX/PPTM | ZIP/OPC、content types、relationships、Strict/Transitional、CFB旧形式 |
| ODP | ZIP/manifest/mimetype、Flat XML、ODF版とExtended |
| Keynote | 単一ファイル/パッケージ、Index/Index.zip、IWA、旧XML（世代別実測） |

根拠・探索資料: [S01](https://ecma-international.org/publications-and-standards/standards/ecma-376/)、[S04](https://learn.microsoft.com/en-us/office/compatibility/office-file-format-reference)、[S05](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-ppt/6be79dde-33c1-4c1b-8ccc-4b2301c08662)、[S07](https://docs.oasis-open.org/office/OpenDocument/v1.4/os/part2-packages/OpenDocument-v1.4-os-part2-packages.html)、[S09](https://help.libreoffice.org/latest/en-US/text/shared/guide/convertfilters.html)、[S12](https://support.apple.com/en-il/119883)、[S14](https://raw.githubusercontent.com/obriensp/iWorkFileFormat/master/Docs/index.md)、[S15](https://github.com/psobot/keynote-parser)。内部表現候補は規範仕様と解析資料を区別して検証する。

| ID | 機能 | API/モデル案 | 工程 | 現行PPTX | 固有の受入条件 |
|---|---|---|---|---|---|
| PKG-001 | 内容に基づく形式判定 | FormatProfile | P1 | 部分対応 | ODP・Keynote・暗号Office・旧PPTを根拠つきで区別 |
| PKG-002 | ZIP stored/DEFLATE/ZIP64/descriptor | PackageArchive | P1 | 部分対応 | 読める範囲と出力上限、CRC、サイズ差を検査 |
| PKG-003 | OPC content typesとrelationship | PackageGraph | P1 | 基本範囲あり | パーツ移動・相対URI・外部target・欠損に対応 |
| PKG-004 | StrictとTransitionalのプロファイル | FormatDialect | P3 | 部分対応 | Strictへの追加・新規出力もスキーマ検証 |
| PKG-005 | テンプレートとスライドショー形式 | DocumentKind | P3 | 未実装 | POTX/POTM/PPSX/PPSMのkindとcontent typeを保持 |
| PKG-006 | ODF manifestとmimetype配置 | ODPPackage | P2 | 対象外 | MIME・manifest・格納順・非圧縮条件を検査 |
| PKG-007 | ODF世代とExtendedの識別 | FormatDialect | P2 | 対象外 | 1.0–1.4と拡張語彙を区別し対応を報告 |
| PKG-008 | Flat XML presentation | ODPFlatXML | P3 | 対象外 | 外部・埋込binary dataと単位を再読で照合 |
| PKG-009 | Keynote ZIP/ディレクトリ/入れ子 | KeynoteContainer | P6 | 対象外 | 実測した世代の外側・Index形態を独立試験 |
| PKG-010 | IWA framingとSnappy | IWAStore | P6 | 対象外 | chunk長・展開量・切断・不正圧縮を検査 |
| PKG-011 | Protobuf未知fieldとtype registry | KeynoteRegistry | P6 | 対象外 | 世代ごとの型ID、wire値、未知fieldを保持 |
| PKG-012 | 旧Keynote XML/テーマ形式 | KeynoteLegacy | P7 | 対象外 | 対象世代の実例で読取・書戻し可否を確定 |
| PKG-013 | 旧PPT/POT/PPSのCFBとrecords | LegacyPPTCodec | P7 | 拒否 | persist directoryとOfficeArt参照を正しく追跡 |
| PKG-014 | 旧Impress SXI/STI系 | LegacyImpressCodec | P7 | 対象外 | ODFとの違いと対象版を確定し未知構造を保持 |

## DOC 文書とスライド構造

文書全体の順序、参照、複製と編集を扱う。

| 形式 | 表現・探索先 |
|---|---|
| PPTX/PPTM | presentation、sldIdLst、slide、section/custom showの拡張 |
| ODP | office:presentation、draw:page、presentation:show/settings |
| Keynote | 文書・slide collection・slide参照の型候補（registry確認） |

根拠・探索資料: [S01](https://ecma-international.org/publications-and-standards/standards/ecma-376/)、[S02](https://learn.microsoft.com/en-us/office/open-xml/presentation/structure-of-a-presentationml-document)、[S03](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-pptx/efd8bb2d-d888-4e2e-af25-cad476730c9f)、[S08](https://docs.oasis-open.org/office/OpenDocument/v1.4/OpenDocument-v1.4-part3-schema.pdf)、[S11](https://support.apple.com/guide/keynote/welcome/mac)、[S15](https://github.com/psobot/keynote-parser)。内部表現候補は規範仕様と解析資料を区別して検証する。

| ID | 機能 | API/モデル案 | 工程 | 現行PPTX | 固有の受入条件 |
|---|---|---|---|---|---|
| DOC-001 | スライド寸法・比率・向き | Size/Canvas | P1 | 基本範囲あり | 原単位と丸め、未知サイズ値を保持 |
| DOC-002 | スライド順序・名前・表示状態 | Slides/SlideID | P1 | 基本範囲あり | 同名・非表示・並替後の参照を維持 |
| DOC-003 | 追加・削除・並べ替え | SlideEditing | P1 | 部分対応 | 既知参照を更新、未知参照への危険編集を拒否 |
| DOC-004 | スライド複製・別資料からの取込 | ImportPlan | P1 | 拒否 | ID・layout・notes・asset・内部リンクを再接続 |
| DOC-005 | セクション・グループ構造 | Section | P3 | 原本保持中心 | 所属・順序・空グループとUI意味を保持 |
| DOC-006 | カスタムスライドショー | CustomShow | P5 | 原本保持中心 | 重複登場・欠損参照・範囲を検査 |
| DOC-007 | 背景の直接指定と継承 | Background | P3 | 部分対応 | master背景と明示noneを区別 |
| DOC-008 | ヘッダー・フッター・日付・番号 | HeaderFooter/Field | P3 | 原本保持中心 | 表示フラグ・更新規則・配置を分離 |
| DOC-009 | ノート本文とノートページ | NotesPage | P3 | 部分対応 | 図形・画像・rich text・共有masterを保持 |
| DOC-010 | 配布資料ページ・master | HandoutMaster | P3 | 原本保持中心 | 印刷配置・ページ寸法・参照を維持 |
| DOC-011 | テンプレートからの文書作成 | Template | P3 | 未実装 | placeholderと共有資源を正しく実体化 |
| DOC-012 | 文書表示設定・編集状態 | ViewSettings | P3 | 原本保持中心 | zoom・guide・選択等を意味変更なしで保持 |

## STY テーマ・レイアウト・継承

直接指定と実効外観を分離する。

| 形式 | 表現・探索先 |
|---|---|
| PPTX/PPTM | theme、master/layout、placeholder、clrMap、style matrix |
| ODP | default/named/automatic styles、page layout、master page、style family |
| Keynote | テーマ・レイアウト・stylesheetのオブジェクト候補（版別確認） |

根拠・探索資料: [S01](https://ecma-international.org/publications-and-standards/standards/ecma-376/)、[S02](https://learn.microsoft.com/en-us/office/open-xml/presentation/structure-of-a-presentationml-document)、[S08](https://docs.oasis-open.org/office/OpenDocument/v1.4/OpenDocument-v1.4-part3-schema.pdf)、[S10](https://raw.githubusercontent.com/LibreOffice/core/master/xmloff/source/draw/sdpropls.cxx)、[S11](https://support.apple.com/guide/keynote/welcome/mac)、[S14](https://raw.githubusercontent.com/obriensp/iWorkFileFormat/master/Docs/index.md)。内部表現候補は規範仕様と解析資料を区別して検証する。

| ID | 機能 | API/モデル案 | 工程 | 現行PPTX | 固有の受入条件 |
|---|---|---|---|---|---|
| STY-001 | マスター・レイアウトの読取と編集 | Master/Layout | P3 | 原本保持中心 | 所有・参照・共有・削除影響を検査 |
| STY-002 | プレースホルダー種類・index | Placeholder | P3 | 部分対応 | master/layoutの照合と未指定値を保持 |
| STY-003 | プレースホルダー継承と実効値 | StyleResolver | P3 | 未実装 | 位置・文字・背景の継承出典を返す |
| STY-004 | テーマ色schemeと色map | ThemeColors | P3 | 部分対応 | accent・hlink・scheme overrideを順序どおり解決 |
| STY-005 | テーマフォント・言語script | ThemeFonts | P3 | 部分対応 | Latin/EA/CS/supplementalの参照を維持 |
| STY-006 | テーマfill/line/effect matrix | ThemeStyles | P3 | 原本保持中心 | style referenceと直接overrideを区別 |
| STY-007 | 名前付き文字・段落・図形styles | StyleSheet | P3 | 原本保持中心 | family・parent・cycle・defaultを検査 |
| STY-008 | 自動styleと共有styleの管理 | StyleIndex | P3 | 未実装 | 名前衝突を解消し未編集styleを保持 |
| STY-009 | 背景・表styleの継承 | StyleResolver | P4 | 部分対応 | 各regionとheader/banding規則を反映 |
| STY-010 | style解決と出典情報 | ResolvedStyle | P3 | 未実装 | 未解決をnil/黒/ゼロで隠さない |
| STY-011 | styleの実体化・テーマ変更 | MaterializeStyle | P3 | 拒否 | 影響範囲と外観差を計画に出す |
| STY-012 | テーマの独立入出力 | ThemeDocument | P3 | 未実装 | THMX/KTH等の有効profileを検証 |

## GEO 図形・座標・接続

論理的な形、座標変換と参照を扱う。

| 形式 | 表現・探索先 |
|---|---|
| PPTX/PPTM | sp/cxnSp/grpSp、xfrm、prstGeom/custGeom、geometry guides |
| ODP | draw shapes/group/connector、svg paths、enhanced geometry、transform |
| Keynote | drawable・geometry・shape/path候補（型とfieldを実測） |

根拠・探索資料: [S01](https://ecma-international.org/publications-and-standards/standards/ecma-376/)、[S08](https://docs.oasis-open.org/office/OpenDocument/v1.4/OpenDocument-v1.4-part3-schema.pdf)、[S10](https://raw.githubusercontent.com/LibreOffice/core/master/xmloff/source/draw/sdpropls.cxx)、[S11](https://support.apple.com/guide/keynote/welcome/mac)、[S15](https://github.com/psobot/keynote-parser)。内部表現候補は規範仕様と解析資料を区別して検証する。

| ID | 機能 | API/モデル案 | 工程 | 現行PPTX | 固有の受入条件 |
|---|---|---|---|---|---|
| GEO-001 | frame・回転・反転 | Rect/Transform2D | P1 | 基本範囲あり | 元の単位と変換順を保持 |
| GEO-002 | nested groupとchild coordinate space | Group | P3 | 部分対応 | 入れ子変換・group再構成・外観を照合 |
| GEO-003 | プリセット図形とadjustments | ShapeGeometry | P3 | 部分対応 | 全列挙値と調整式を詳細台帳で追う |
| GEO-004 | カスタムgeometry・path・guides | PathGeometry | P3 | 原本保持中心 | arc/Bezier/closeと数式、未知命令を保持 |
| GEO-005 | connection pointsとconnector参照 | Connector | P3 | 部分対応 | endpoint ID/接続siteを移動・複製で更新 |
| GEO-006 | 図形結合・分割・boolean geometry | GeometryOperations | P8 | 未実装 | 元pathと編集可能性を保持し精度を測定 |
| GEO-007 | 描画順・前後移動 | Elements | P1 | 基本範囲あり | opaqueを含む順序とIDを維持 |
| GEO-008 | レイヤー・オブジェクトlock | Layer/Locks | P3 | 原本保持中心 | 編集禁止属性と表示可否を維持 |
| GEO-009 | 整列・分布・grid配置 | Layout | P1 | 基本範囲あり | 変換座標とgap、負の領域を検査 |
| GEO-010 | clip・mask・複雑なshape outline | ClipPath | P3 | 原本保持中心 | clipと形本体を混同しない |
| GEO-011 | ガイド・グリッド・snap設定 | Guides | P3 | 原本保持中心 | 編集補助情報を描画内容と分離 |
| GEO-012 | 3D scene・camera・light・bevel | Scene3D | P5 | 原本保持中心 | 2Dにflattenするとき外観差を診断 |

## PNT 色・塗り・線・効果

元の色表現と解決済み外観を区別する。

| 形式 | 表現・探索先 |
|---|---|
| PPTX/PPTM | DrawingML color/fill/line/effect/scene properties |
| ODP | style graphic properties、gradient/hatch/fill-image、opacity |
| Keynote | style/effectのオブジェクト候補（対応可否は版別確認） |

根拠・探索資料: [S01](https://ecma-international.org/publications-and-standards/standards/ecma-376/)、[S08](https://docs.oasis-open.org/office/OpenDocument/v1.4/OpenDocument-v1.4-part3-schema.pdf)、[S10](https://raw.githubusercontent.com/LibreOffice/core/master/xmloff/source/draw/sdpropls.cxx)、[S11](https://support.apple.com/guide/keynote/welcome/mac)。内部表現候補は規範仕様と解析資料を区別して検証する。

| ID | 機能 | API/モデル案 | 工程 | 現行PPTX | 固有の受入条件 |
|---|---|---|---|---|---|
| PNT-001 | RGB/alpha/theme/system色 | Color | P3 | 部分対応 | fallbackと色参照、透明度を保持 |
| PNT-002 | 色変換の順序・色空間 | ColorTransform | P3 | 原本保持中心 | tint/shade/luminance等の順序を保持 |
| PNT-003 | solid/noneと背景fill参照 | Fill | P3 | 基本範囲あり | none・継承・未指定を区別 |
| PNT-004 | linear/path gradientとstops | Gradient | P3 | 原本保持中心 | 位置・角度・複数stop・alphaを照合 |
| PNT-005 | pattern/hatch fill | PatternFill | P3 | 原本保持中心 | パターン種と前景背景色を保持 |
| PNT-006 | image fill/tile/stretch | ImageFill | P3 | 原本保持中心 | asset参照・scale・tile originを保持 |
| PNT-007 | 線幅・dash・cap・join・compound | Stroke | P3 | 部分対応 | 全属性と列挙値、単位を詳細台帳へ |
| PNT-008 | 矢印の種類・長さ・幅 | Arrowhead | P3 | 部分対応 | 両端の形とdimensionを保持 |
| PNT-009 | shadow/glow/soft edge | Effects | P5 | 原本保持中心 | effect順・blur・方向・距離を照合 |
| PNT-010 | reflectionと透明度 | Reflection | P5 | 原本保持中心 | fade範囲・scale・offsetを保持 |
| PNT-011 | effect DAG・blend・filter | EffectGraph | P5 | 原本保持中心 | 共有参照と未知effectを保持 |

## TXT 文字・段落・テキスト領域

テキスト抽出と書式付き編集・文字計測を分ける。

| 形式 | 表現・探索先 |
|---|---|
| PPTX/PPTM | DrawingML txBody/r/p/fld/bodyPr/lstStyle、text style hierarchy |
| ODP | text:p/span/list/ruby/fields、style paragraph/text properties |
| Keynote | TSWP系text storage/style候補。機能はAppleガイド、内部対応は実測 |

根拠・探索資料: [S01](https://ecma-international.org/publications-and-standards/standards/ecma-376/)、[S08](https://docs.oasis-open.org/office/OpenDocument/v1.4/OpenDocument-v1.4-part3-schema.pdf)、[S11](https://support.apple.com/guide/keynote/welcome/mac)、[S19](https://support.apple.com/en-au/guide/keynote/tan72a69d01f/mac)、[S15](https://github.com/psobot/keynote-parser)。内部表現候補は規範仕様と解析資料を区別して検証する。

| ID | 機能 | API/モデル案 | 工程 | 現行PPTX | 固有の受入条件 |
|---|---|---|---|---|---|
| TXT-001 | Unicode本文・空白・改行・tab | TextBody/Inline | P1 | 部分対応 | 段落break・soft break・tabを区別 |
| TXT-002 | rich text runsと範囲編集 | TextRun/TextRange | P3 | 部分対応 | 外側のrun/link/fieldとgrapheme境界を保全 |
| TXT-003 | font family/size/script/language | Font | P3 | 基本範囲あり | 各scriptの指定・参照・未指定を維持 |
| TXT-004 | bold/italic/strike/caps | TextStyle | P3 | 部分対応 | 各種strike/capsをboolへ丸めない |
| TXT-005 | underline種・色・線 | Underline | P3 | 部分対応 | double等の種類と独立書式を保持 |
| TXT-006 | character spacing/kerning/baseline | CharacterStyle | P3 | 原本保持中心 | tracking・上付下付の単位を維持 |
| TXT-007 | 文字fill・outline・shadow | TextEffects | P5 | 原本保持中心 | glyphの効果とshapeの効果を区別 |
| TXT-008 | 段落alignment/indent/margins | ParagraphStyle | P3 | 基本範囲あり | RTL・分散・負indentと省略を保持 |
| TXT-009 | 行間・段落前後の単位 | LineSpacing | P3 | 部分対応 | 倍率とpoint指定を区別 |
| TXT-010 | 箇条書き・番号・restart・階層 | ListStyle | P3 | 部分対応 | start/restart/levelと複数段落の意味を保持 |
| TXT-011 | 画像bullet・bullet書式 | BulletStyle | P3 | 原本保持中心 | 画像/文字font/size/colorを維持 |
| TXT-012 | tab stops・leader | TabStops | P3 | 原本保持中心 | 位置・種類・leaderとdefault tabを保持 |
| TXT-013 | 段落既定runとend style | Paragraph | P3 | 基本範囲あり | 空段落・終端・既定書式を区別 |
| TXT-014 | TextBody余白・縦位置・wrap | TextBoxStyle | P3 | 基本範囲あり | 単位・継承・明示値を再読で照合 |
| TXT-015 | 縦書き・RTL・文字回転 | WritingMode | P3 | 原本保持中心 | CJK縦書きとbidi順を検証 |
| TXT-016 | CJK禁則・句読点・ruby | Typography/Ruby | P3 | 原本保持中心 | 元指定の存在と対象形式との差を診断 |
| TXT-017 | columns・column gap・linked text | TextFlow | P5 | 原本保持中心 | 機能の存在を形式別に確認しflowを維持 |
| TXT-018 | autofit・font scaling・overflow | TextFit | P8 | 原本保持中心 | 不足環境はunknown、計測結果と元値を分離 |
| TXT-019 | text warp・WordArt相当 | TextWarp | P5 | 原本保持中心 | warp geometryと編集文字を維持 |
| TXT-020 | 日付・slide番号等のfields | Field | P3 | 部分対応 | 原式・表示cache・更新規則を保持 |
| TXT-021 | inline図形・数式・アンカー | InlineObject | P5 | 原本保持中心 | anchor/rangeと表示対象を再接続 |
| TXT-022 | 検索・置換・本文抽出のscope | TextSearch | P1 | 部分対応 | 本文・notes・表の位置を正確に返す |

## IMG 画像・ベクトル・フォント

画像バイトの保持と見た目の処理を分ける。

| 形式 | 表現・探索先 |
|---|---|
| PPTX/PPTM | blip、media parts、SVG等の拡張、font parts |
| ODP | draw:image、binary-data、xlink、font-face |
| Keynote | Data資源、image/media info候補（digest等は実測） |

根拠・探索資料: [S01](https://ecma-international.org/publications-and-standards/standards/ecma-376/)、[S03](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-pptx/efd8bb2d-d888-4e2e-af25-cad476730c9f)、[S08](https://docs.oasis-open.org/office/OpenDocument/v1.4/OpenDocument-v1.4-part3-schema.pdf)、[S11](https://support.apple.com/guide/keynote/welcome/mac)、[S14](https://raw.githubusercontent.com/obriensp/iWorkFileFormat/master/Docs/index.md)。内部表現候補は規範仕様と解析資料を区別して検証する。

| ID | 機能 | API/モデル案 | 工程 | 現行PPTX | 固有の受入条件 |
|---|---|---|---|---|---|
| IMG-001 | 埋込画像・media type・遅延bytes | Asset/Image | P1 | 基本範囲あり | CRC検査と参照、サイズを維持 |
| IMG-002 | 外部画像URIと埋込切替 | AssetSource | P3 | 部分対応 | 既定でnetwork取得せずリンクを保持 |
| IMG-003 | crop・source rectangle | ImageCrop | P3 | 原本保持中心 | 負cropと範囲・縦横比を照合 |
| IMG-004 | mask・shape crop・clip | ImageMask | P3 | 原本保持中心 | 元maskと画像を分離して維持 |
| IMG-005 | brightness/contrast/duotone等 | ImageEffects | P5 | 原本保持中心 | 非破壊パラメータと元画像を保持 |
| IMG-006 | SVGとfallback・EMF/WMF等 | VectorAsset | P5 | 原本保持中心 | 元assetを保持し描画不能を診断 |
| IMG-007 | HEIC/GIF/TIFF等の資源保持 | Asset | P3 | 部分対応 | decode能力とbyte保持を別表示 |
| IMG-008 | 画像解像度・圧縮・縮小 | AssetOptimization | P8 | 未実装 | 明示操作でのみ再圧縮、時間/RSS/品質を測定 |
| IMG-009 | 埋込fontと使用制約flags | EmbeddedFont | P5 | 原本保持中心 | font bytes/face mapping/制約を維持 |
| IMG-010 | 資源重複排除・共有参照 | AssetStore | P1 | 部分対応 | 既存identityを変えず新規資源のみ共有 |
| IMG-011 | thumbnail/preview/poster | PreviewCache | P3 | 原本保持中心 | 編集で古くなるcacheを適切に更新/診断 |

## TBL 表・セル・式

PowerPoint表、ODF表と埋込Calc、Keynoteの表を同じ能力と見なさない。

| 形式 | 表現・探索先 |
|---|---|
| PPTX/PPTM | DrawingML table、table style、grid/merge。セル数式は別問題 |
| ODP | table要素と埋込spreadsheet、OpenFormulaは該当文書で別調査 |
| Keynote | TST系table候補。式と条件書式はApple機能資料で確認 |

根拠・探索資料: [S01](https://ecma-international.org/publications-and-standards/standards/ecma-376/)、[S08](https://docs.oasis-open.org/office/OpenDocument/v1.4/OpenDocument-v1.4-part3-schema.pdf)、[S11](https://support.apple.com/guide/keynote/welcome/mac)、[S16](https://support.apple.com/en-euro/guide/keynote/tanfb0588a84/mac)。内部表現候補は規範仕様と解析資料を区別して検証する。

| ID | 機能 | API/モデル案 | 工程 | 現行PPTX | 固有の受入条件 |
|---|---|---|---|---|---|
| TBL-001 | 行列gridと寸法 | Table | P4 | 基本範囲あり | 空grid・非矩形・単位・最大cell予算を検査 |
| TBL-002 | rich textセルとtyped value | TableCell/CellValue | P4 | 部分対応 | 値・表示text・cacheを区別 |
| TBL-003 | merge/span/covered cells | MergeRegion | P4 | 部分対応 | 有効領域・continuation・編集後の再結合を照合 |
| TBL-004 | セルごとの四辺border・diagonal | CellBorders | P4 | 部分対応 | 隣接辺の優先順位を形式別に確定 |
| TBL-005 | cell fill/insets/vertical alignment | CellStyle | P4 | 部分対応 | run書式とcell領域書式を分離 |
| TBL-006 | header/footer/banded rows/columns | TableStyle | P4 | 原本保持中心 | style領域とdirect overrideの優先順位を保持 |
| TBL-007 | table名・title・caption・lock | TableMetadata | P4 | 部分対応 | nameと参照identityを区別 |
| TBL-008 | 繰返し行列・hidden・header region | TableGrid | P4 | 未実装 | 対応する形式だけ展開し総cell予算を守る |
| TBL-009 | 日付・通貨・数値format | NumberFormat | P4 | 未実装 | 表現できない形式では表示と損失を診断 |
| TBL-010 | 式・参照・cached value | TableFormula | P4 | 未実装 | 方言と再計算能力を明記し元式を保持 |
| TBL-011 | 条件書式・ルール | ConditionalStyle | P4 | 未実装 | targetと評価順、未対応expressionを保持 |
| TBL-012 | 行列追加・削除・sort | TableEditing | P4 | 未実装 | merge・式・リンク参照の更新を検査 |

## CHT チャートとデータ

表示cache、編集用データ、外部/埋込データを区別する。

| 形式 | 表現・探索先 |
|---|---|
| PPTX/PPTM | chart parts、DrawingML chart、Office chart extensions、embedded workbook |
| ODP | chart document/series/axis、local table/外部source |
| Keynote | TSCh系chart候補、2D/3D/interactiveはApple機能資料 |

根拠・探索資料: [S01](https://ecma-international.org/publications-and-standards/standards/ecma-376/)、[S03](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-pptx/efd8bb2d-d888-4e2e-af25-cad476730c9f)、[S08](https://docs.oasis-open.org/office/OpenDocument/v1.4/OpenDocument-v1.4-part3-schema.pdf)、[S17](https://support.apple.com/en-euro/guide/keynote/tan1a8924264/mac)。内部表現候補は規範仕様と解析資料を区別して検証する。

| ID | 機能 | API/モデル案 | 工程 | 現行PPTX | 固有の受入条件 |
|---|---|---|---|---|---|
| CHT-001 | column/bar/line/area/pie/doughnut | ChartKind | P4 | 原本保持中心 | 全kind・stacking・series書式を詳細台帳で追う |
| CHT-002 | scatter/bubble/radar/stock/surface | ChartKind | P4 | 原本保持中心 | x/y/sizeと欠損・scaleを維持 |
| CHT-003 | 新しいchart typesと組合せchart | ExtendedChart | P5 | 原本保持中心 | histogram等の拡張schemaと対象版を別検証 |
| CHT-004 | series/category/pointとcache | ChartData | P4 | 原本保持中心 | index・欠損・空・値型・表示cacheを区別 |
| CHT-005 | 埋込Workbook/外部データsource | ChartDataSource | P4 | 原本保持中心 | workbook・URI・参照式を整合させる |
| CHT-006 | axes・log/date scale・secondary | ChartAxis | P4 | 原本保持中心 | cross・bounds・unitと自動値を区別 |
| CHT-007 | legend/title/data labels | ChartLabels | P4 | 原本保持中心 | rich text・位置・format・point overrideを維持 |
| CHT-008 | trendline/error bars/markers | ChartStatistics | P4 | 原本保持中心 | 計算指定と元系列への参照を保持 |
| CHT-009 | chart layout/style/color schemes | ChartStyle | P4 | 原本保持中心 | auto/manual・theme参照・style partsを照合 |
| CHT-010 | 3D chartのcamera/light/depth | Chart3D | P5 | 原本保持中心 | 2D fallbackの外観差を診断 |
| CHT-011 | interactive chartとデータsets | InteractiveChart | P6 | 対象外 | controls・sets・Magic Chartの動作を版別に試験 |
| CHT-012 | 表/SwiftSheetsとのデータ交換 | ChartDataAdapter | P4 | 未実装 | 式/cache/date epoch/number formatの差を診断 |

## OBJ 高度なオブジェクトと拡張

共通モデルに入らないものを安全に保持し段階的に編集モデルへ移す。

| 形式 | 表現・探索先 |
|---|---|
| PPTX/PPTM | SmartArt dgm、OLE/ActiveX、OMML、ink、3D/extension parts |
| ODP | embedded object、MathML、forms、draw enhanced geometry/3D |
| Keynote | equation/drawing/3D/gallery等の候補（内部型は実測） |

根拠・探索資料: [S01](https://ecma-international.org/publications-and-standards/standards/ecma-376/)、[S03](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-pptx/efd8bb2d-d888-4e2e-af25-cad476730c9f)、[S08](https://docs.oasis-open.org/office/OpenDocument/v1.4/OpenDocument-v1.4-part3-schema.pdf)、[S11](https://support.apple.com/guide/keynote/welcome/mac)、[S19](https://support.apple.com/en-au/guide/keynote/tan72a69d01f/mac)、[S15](https://github.com/psobot/keynote-parser)。内部表現候補は規範仕様と解析資料を区別して検証する。

| ID | 機能 | API/モデル案 | 工程 | 現行PPTX | 固有の受入条件 |
|---|---|---|---|---|---|
| OBJ-001 | SmartArt/diagramデータとlayout | Diagram | P5 | 原本保持中心 | data/layout/style/colors/描画cacheの依存を保全 |
| OBJ-002 | diagramの再配置・編集 | DiagramLayout | P8 | 未実装 | 実アプリ同等性が未確認なら外観差を診断 |
| OBJ-003 | OLE埋込/linked document | EmbeddedObject | P5 | 原本保持中心 | 元binaryとpreview、関係を維持 |
| OBJ-004 | ActiveX/form control | Control | P7 | 原本保持中心 | プロパティ・資源を保持し実行しない |
| OBJ-005 | OMML/MathML/LaTeX数式 | Equation | P5 | 原本保持中心 | 原式と表示資源、各方言を分離 |
| OBJ-006 | ink/手描きstroke | Ink | P5 | 原本保持中心 | pressure/time/pathと元resourceを保持 |
| OBJ-007 | 3D model資源と配置 | Model3D | P5 | 原本保持中心 | model format・poster・cameraを別に保持 |
| OBJ-008 | 画像gallery・interactive object | Gallery | P6 | 対象外 | item順・control・buildと変換差を試験 |
| OBJ-009 | custom XML/任意extension | OpaquePart | P1 | 原本保持中心 | 未編集bytesと依存参照を保全 |
| OBJ-010 | AlternateContentの選択と保持 | AlternateContent | P1 | 原本保持中心 | active branchだけで全分岐を上書きしない |
| OBJ-011 | opaque objectの位置・説明 | OpaqueElement | P1 | 部分対応 | 空の既知shapeに偽装せずidentityを保持 |

## MED 音声・動画・録画

パッケージ保持、再生指定、実際の再生を分ける。

| 形式 | 表現・探索先 |
|---|---|
| PPTX/PPTM | audio/video/media parts、timing、poster、trim、Office拡張 |
| ODP | draw:plugin/media参照、presentation音声とanimation cues |
| Keynote | media・soundtrack・recording候補（Apple資料と実測） |

根拠・探索資料: [S01](https://ecma-international.org/publications-and-standards/standards/ecma-376/)、[S03](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-pptx/efd8bb2d-d888-4e2e-af25-cad476730c9f)、[S08](https://docs.oasis-open.org/office/OpenDocument/v1.4/OpenDocument-v1.4-part3-schema.pdf)、[S11](https://support.apple.com/guide/keynote/welcome/mac)、[S20](https://support.apple.com/guide/keynote/record-presentations-tan81813d552/mac)、[S14](https://raw.githubusercontent.com/obriensp/iWorkFileFormat/master/Docs/index.md)。内部表現候補は規範仕様と解析資料を区別して検証する。

| ID | 機能 | API/モデル案 | 工程 | 現行PPTX | 固有の受入条件 |
|---|---|---|---|---|---|
| MED-001 | 埋込/linked audio・video | Media | P5 | 原本保持中心 | binary・URI・media type・関係を維持 |
| MED-002 | poster・thumbnail・preview | MediaPoster | P5 | 原本保持中心 | 表示画像と本体参照を分離 |
| MED-003 | trim・volume・mute・loop | MediaPlayback | P5 | 原本保持中心 | 時間単位と再生範囲を再読で照合 |
| MED-004 | start trigger・クリック動作 | MediaCue | P5 | 原本保持中心 | timelineとmediaの参照を一致 |
| MED-005 | bookmark/cue points | MediaBookmark | P5 | 原本保持中心 | cue削除やtrim時の影響を診断 |
| MED-006 | soundtrack・複数枚の継続再生 | Soundtrack | P5 | 原本保持中心 | スライドlocal/globalの適用範囲を区別 |
| MED-007 | ナレーション・録画・rehearsal | Recording | P5 | 原本保持中心 | audioとイベント時刻の同期を保持 |
| MED-008 | live video/online videoのdescriptor | LiveMedia | P6 | 未実装 | ファイル内設定のみ保持しservice再現と区別 |
| MED-009 | subtitle/captions等の資源 | Captions | P5 | 原本保持中心 | 対応形式と版を確定し元text/URIを保持 |
| MED-010 | transcode・codec対応 | MediaConverter | P8 | 未実装 | 明示操作だけ変換し品質・時間/RSSを測定 |

## ANI 遷移・アニメーション・時間

単なるeffect名の対応では動作を再現できない。

| 形式 | 表現・探索先 |
|---|---|
| PPTX/PPTM | p:transition/p:timing、sequence/parallel、Office拡張Morph |
| ODP | anim/SMIL語彙、presentation transition properties |
| Keynote | build in/action/out・transition・Magic Move（内部型は実測） |

根拠・探索資料: [S01](https://ecma-international.org/publications-and-standards/standards/ecma-376/)、[S03](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-pptx/efd8bb2d-d888-4e2e-af25-cad476730c9f)、[S08](https://docs.oasis-open.org/office/OpenDocument/v1.4/OpenDocument-v1.4-part3-schema.pdf)、[S18](https://support.apple.com/en-euro/guide/keynote/tanff5ae749e/mac)、[S17](https://support.apple.com/en-euro/guide/keynote/tan1a8924264/mac)。内部表現候補は規範仕様と解析資料を区別して検証する。

| ID | 機能 | API/モデル案 | 工程 | 現行PPTX | 固有の受入条件 |
|---|---|---|---|---|---|
| ANI-001 | slide transitionの種類・方向 | Transition | P5 | 原本保持中心 | 全effect enumと未知拡張を台帳へ |
| ANI-002 | transition durationとadvance | TransitionTiming | P5 | 原本保持中心 | クリック/自動・delay・soundを保持 |
| ANI-003 | Morph/Magic Moveのobject対応 | ObjectMatching | P6 | 原本保持中心 | slide跨ぎidentityと文字対応を版別に検証 |
| ANI-004 | build in/out/emphasis/action | Animation | P5 | 原本保持中心 | 入退場とaction、未知effectを区別 |
| ANI-005 | sequence/parallelとtrigger graph | Timeline | P5 | 原本保持中心 | click/with/after・条件・参照を維持 |
| ANI-006 | keyframes・motion path・transform | KeyframeTrack | P5 | 原本保持中心 | 座標系・easing・value型・pathを照合 |
| ANI-007 | repeat/reverse/acceleration/fill | TimingProperties | P5 | 原本保持中心 | 無限repeatと終了状態を保持 |
| ANI-008 | paragraph/word/character builds | TextBuild | P5 | 原本保持中心 | target rangeと順序をtext編集時に検査 |
| ANI-009 | chart/diagram/group builds | ObjectBuild | P5 | 原本保持中心 | series/point/childへの参照を維持 |
| ANI-010 | interactive triggers・bookmark同期 | EventTrigger | P5 | 原本保持中心 | target削除・media trimの影響を診断 |
| ANI-011 | effect presetsと固有パラメータ | EffectDescriptor | P5 | 原本保持中心 | 共通化できない指定をopaqueで保持 |
| ANI-012 | タイムライン評価と再生検証 | TimelineEvaluator | P8 | 未実装 | イベント列・時間・画像を実アプリと比較 |

## SHW 発表・操作・印刷設定

ファイル内の指定をモデル化し、アプリのUIや外部機器と分ける。

| 形式 | 表現・探索先 |
|---|---|
| PPTX/PPTM | showPr/custom show、hyperlink actions、print/notes/handout/view settings |
| ODP | presentation settings、events、print style |
| Keynote | presentation navigation/recording/notes設定候補（版別確認） |

根拠・探索資料: [S01](https://ecma-international.org/publications-and-standards/standards/ecma-376/)、[S08](https://docs.oasis-open.org/office/OpenDocument/v1.4/OpenDocument-v1.4-part3-schema.pdf)、[S11](https://support.apple.com/guide/keynote/welcome/mac)、[S20](https://support.apple.com/guide/keynote/record-presentations-tan81813d552/mac)。内部表現候補は規範仕様と解析資料を区別して検証する。

| ID | 機能 | API/モデル案 | 工程 | 現行PPTX | 固有の受入条件 |
|---|---|---|---|---|---|
| SHW-001 | external/internal hyperlink | Link | P1 | 基本範囲あり | 外部URIとSlideIDを区別し編集で参照維持 |
| SHW-002 | shape・hover・クリックactions | Interaction | P5 | 部分対応 | URI/slide/command/macro actionを区別 |
| SHW-003 | kiosk・self-playing・loop設定 | ShowSettings | P5 | 原本保持中心 | 再生modeとnavigation制約を保持 |
| SHW-004 | show範囲・custom show選択 | ShowSelection | P5 | 原本保持中心 | 全体/範囲/列挙の違いを維持 |
| SHW-005 | laser/pen・記録された注釈 | PresentationAnnotation | P5 | 原本保持中心 | ファイルに保存される内容だけを保全 |
| SHW-006 | presenter notes・表示設定 | PresenterSettings | P5 | 部分対応 | notes内容と端末依存UI設定を区別 |
| SHW-007 | print page・handout・notes layout | PrintSettings | P3 | 原本保持中心 | scale・color・range・page configを保持 |
| SHW-008 | PDF/画像の選択範囲 | RenderSelection | P8 | 未実装 | hidden/notes/build時点を明示 |
| SHW-009 | 動画・GIF・HTML配布 | ExportOptions | P8 | 未実装 | 再生範囲とeditability損失を報告 |

## REV コメント・アクセシビリティ

著者情報・議論と読み上げ情報を保持する。

| 形式 | 表現・探索先 |
|---|---|
| PPTX/PPTM | comments/authors/threaded comment拡張、cNvPr等のdescription |
| ODP | office annotation、author/date、draw description/title |
| Keynote | annotation storage・accessibility descriptor候補（版別確認） |

根拠・探索資料: [S01](https://ecma-international.org/publications-and-standards/standards/ecma-376/)、[S03](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-pptx/efd8bb2d-d888-4e2e-af25-cad476730c9f)、[S08](https://docs.oasis-open.org/office/OpenDocument/v1.4/OpenDocument-v1.4-part3-schema.pdf)、[S11](https://support.apple.com/guide/keynote/welcome/mac)、[S14](https://raw.githubusercontent.com/obriensp/iWorkFileFormat/master/Docs/index.md)。内部表現候補は規範仕様と解析資料を区別して検証する。

| ID | 機能 | API/モデル案 | 工程 | 現行PPTX | 固有の受入条件 |
|---|---|---|---|---|---|
| REV-001 | コメント本文・著者・日時・位置 | Comment | P5 | 原本保持中心 | ID・time zone・anchorを保持 |
| REV-002 | 返信thread・解決状態・mentions | CommentThread | P5 | 原本保持中心 | 形式/版ごとの支援範囲を分ける |
| REV-003 | 変更履歴・共同編集関連metadata | RevisionMetadata | P7 | 原本保持中心 | 存在する情報を保持しserver機能と区別 |
| REV-004 | 代替文・title・decorative flag | Accessibility | P3 | 部分対応 | 画像以外の対象と未指定を維持 |
| REV-005 | 読み上げ順・言語・見出し | ReadingOrder | P5 | 原本保持中心 | 描画順と読み順を同一視しない |
| REV-006 | table header・chart/equation説明 | AccessibleContent | P5 | 未実装 | 構造情報と説明文を分離 |
| REV-007 | アクセシビリティ検査 | AccessibilityAudit | P8 | 未実装 | 判定可能/不明と修正箇所を返す |
| REV-008 | 個人情報を除く共有用出力 | MetadataPolicy | P7 | 未実装 | 明示対象だけ除去し結果に診断を残す |

## MTA 文書プロパティと整合性

主内容以外のメタデータも意味のある文書情報として扱う。

| 形式 | 表現・探索先 |
|---|---|
| PPTX/PPTM | docProps core/app/custom、thumbnail、signature/customXML |
| ODP | meta.xml、settings.xml、RDF、manifest metadata |
| Keynote | Metadata/plist、document identifier、version history候補 |

根拠・探索資料: [S01](https://ecma-international.org/publications-and-standards/standards/ecma-376/)、[S07](https://docs.oasis-open.org/office/OpenDocument/v1.4/os/part2-packages/OpenDocument-v1.4-os-part2-packages.html)、[S08](https://docs.oasis-open.org/office/OpenDocument/v1.4/OpenDocument-v1.4-part3-schema.pdf)、[S14](https://raw.githubusercontent.com/obriensp/iWorkFileFormat/master/Docs/index.md)。内部表現候補は規範仕様と解析資料を区別して検証する。

| ID | 機能 | API/モデル案 | 工程 | 現行PPTX | 固有の受入条件 |
|---|---|---|---|---|---|
| MTA-001 | 標準properties・作成更新日時 | Metadata | P3 | 部分対応 | 型・timezone・lastModifiedBy・revisionを保持 |
| MTA-002 | custom properties・型付き値 | CustomProperty | P3 | 原本保持中心 | date/int/bool/stringと未知型を保持 |
| MTA-003 | producer名・版・document version | SourceInfo | P1 | 原本保持中心 | 検証済みproducer/profileと区別 |
| MTA-004 | 文書ID・creation ID・UUID | SourceIdentity | P1 | 部分対応 | 複製時に必要なIDだけ再生成 |
| MTA-005 | RDF・リンクされたmetadata | MetadataGraph | P7 | 原本保持中心 | 語彙とsubject参照を保全 |
| MTA-006 | サムネイル等のcache整合 | CachePolicy | P3 | 原本保持中心 | 主内容編集後の陳腐化を扱う |
| MTA-007 | スキーマ順・namespace・既定値 | NativePatch | P1 | 部分対応 | 同名local名を異namespaceと混同しない |
| MTA-008 | 未知部分の依存inventory | PreservationInventory | P1 | 部分対応 | 所属・参照・未知参照の有無を記録 |

## SEC 保護・署名・入力制限

安全な失敗と原本の保護も完全な読書きの一部。

| 形式 | 表現・探索先 |
|---|---|
| PPTX/PPTM | CFB/Office暗号・VBA・OPC signature・保護metadata |
| ODP | manifest暗号・document signatures・script libraries |
| Keynote | password暗号とgeneration識別（解析資料と実測が必要） |

根拠・探索資料: [S01](https://ecma-international.org/publications-and-standards/standards/ecma-376/)、[S05](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-ppt/6be79dde-33c1-4c1b-8ccc-4b2301c08662)、[S06](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-offcrypto/11dfbc00-031a-44bc-a836-e7b9872438fd)、[S07](https://docs.oasis-open.org/office/OpenDocument/v1.4/os/part2-packages/OpenDocument-v1.4-os-part2-packages.html)、[S08](https://docs.oasis-open.org/office/OpenDocument/v1.4/OpenDocument-v1.4-part3-schema.pdf)、[S14](https://raw.githubusercontent.com/obriensp/iWorkFileFormat/master/Docs/index.md)。内部表現候補は規範仕様と解析資料を区別して検証する。

| ID | 機能 | API/モデル案 | 工程 | 現行PPTX | 固有の受入条件 |
|---|---|---|---|---|---|
| SEC-001 | OOXML password復号/暗号化 | SlideDecrypt/Encrypt | P7 | 拒否 | 暗号方式・wrong password・破損を区別 |
| SEC-002 | ODF password復号/暗号化 | ODPEncryption | P7 | 対象外 | manifest方式・暗号metadata・checksumを検証 |
| SEC-003 | Keynote password文書 | KeynoteEncryption | P7 | 対象外 | 対象世代を限定して復号/再暗号化を検証 |
| SEC-004 | 旧PPT暗号とCFB streams | LegacyEncryption | P7 | 拒否 | 文書種と暗号方式を正確に判定 |
| SEC-005 | macro/scriptの保持と除去 | MacroPolicy | P7 | 部分対応 | 暗黙削除を拒否し削除した関連物を報告 |
| SEC-006 | 電子署名の保持・検証 | SignatureInfo | P7 | 部分対応 | 未変更byte一致と暗号的validを区別 |
| SEC-007 | 署名除去・再署名 | Signing | P7 | 拒否 | 明示操作と対象・鍵管理を分離 |
| SEC-008 | 編集制限・IRM・感度label情報 | ProtectionInfo | P7 | 原本保持中心 | unsupported protected inputを安全に拒否 |
| SEC-009 | ZIP bomb・XML/IWA予算 | ReadBudget | P1 | 部分対応 | 全体共有の展開量・node・object上限を守る |
| SEC-010 | 表反復・参照・時間graph予算 | ModelBudget | P1 | 未実装 | containerが小さくても巨大modelを拒否 |
| SEC-011 | 外部参照/DTD/ENTITY・マクロ実行 | ExternalResourcePolicy | P1 | 基本範囲あり | 読書きで外部取得や実行を行わない |
| SEC-012 | ディレクトリ・path/symlink安全性 | PackageSource | P6 | 部分対応 | traversal/正規化衝突/入れ子上限を検査 |

## IO 検査・保存・巨大文書

速度・メモリと診断可能性を操作契約で扱う。

| 形式 | 表現・探索先 |
|---|---|
| PPTX/PPTM | slide別partの遅延読取・patch・ZIP file writer |
| ODP | 共有styleと単一content.xmlのincremental parse/patch |
| Keynote | IWA索引と必要object/resourceの遅延decode（実測） |

根拠・探索資料: [S01](https://ecma-international.org/publications-and-standards/standards/ecma-376/)、[S07](https://docs.oasis-open.org/office/OpenDocument/v1.4/os/part2-packages/OpenDocument-v1.4-os-part2-packages.html)、[S08](https://docs.oasis-open.org/office/OpenDocument/v1.4/OpenDocument-v1.4-part3-schema.pdf)、[S14](https://raw.githubusercontent.com/obriensp/iWorkFileFormat/master/Docs/index.md)、[S15](https://github.com/psobot/keynote-parser)。内部表現候補は規範仕様と解析資料を区別して検証する。

| ID | 機能 | API/モデル案 | 工程 | 現行PPTX | 固有の受入条件 |
|---|---|---|---|---|---|
| IO-001 | inspectと根拠つきsummary | InspectOptions | P1 | 部分対応 | declared/scanned/unknown countを区別 |
| IO-002 | 能力一覧とprofile query | CodecCapabilities | P0 | 未実装 | read/create/edit/preserve/render/playを別表示 |
| IO-003 | 遅延slide readerと選択読取 | SlideReader | P2 | 未実装 | 省略slideを空modelにしない |
| IO-004 | async sequenceとcancel | SlideSequence | P2 | 未実装 | 需要駆動でbufferと停止を制御 |
| IO-005 | 新規文書streaming writer | StreamingWriter | P3 | 未実装 | append/close/cancelと未解決IDを検査 |
| IO-006 | 原子的file保存・失敗時原本維持 | FileTarget | P1 | 基本範囲あり | disk full/cancelで出力先を部分上書きしない |
| IO-007 | 大容量file直接出力 | SaveResult | P2 | 未実装 | Data全体の保持なしでwarningsを返す |
| IO-008 | 未変更byte一致 | PreservationStore | P1 | 基本範囲あり | 入力全byteと比較して保証 |
| IO-009 | 編集の依存graph patch | SavePlan | P1 | 部分対応 | 変更範囲と未知参照を計画・検査 |
| IO-010 | bounded並行読取・shared budget | ReadConcurrency | P2 | 未実装 | 決定的順序と実測working setを守る |
| IO-011 | asset/style cache・eviction | CacheBudget | P2 | 部分対応 | 強制展開せずbytes budgetで管理 |

## CNV 変換・診断・編集契約

形式の機能差を利用者が保存前に判断できるようにする。

| 形式 | 表現・探索先 |
|---|---|
| PPTX/PPTM | OOXMLモデルと未対応raw partsの二層 |
| ODP | ODFモデルと未知XML/style/embedded objectの二層 |
| Keynote | 共通modelと未知field/object graphの二層（版別検証） |

根拠・探索資料: [S01](https://ecma-international.org/publications-and-standards/standards/ecma-376/)、[S08](https://docs.oasis-open.org/office/OpenDocument/v1.4/OpenDocument-v1.4-part3-schema.pdf)、[S13](https://support.apple.com/en-gb/105050)、[S14](https://raw.githubusercontent.com/obriensp/iWorkFileFormat/master/Docs/index.md)、[S15](https://github.com/psobot/keynote-parser)。内部表現候補は規範仕様と解析資料を区別して検証する。

| ID | 機能 | API/モデル案 | 工程 | 現行PPTX | 固有の受入条件 |
|---|---|---|---|---|---|
| CNV-001 | 保存前のloss/unsafe edit計画 | SavePlan | P1 | 部分対応 | 位置・feature・理由・actionを返す |
| CNV-002 | read/write両段階の変換診断 | ConversionResult | P4 | 未実装 | sourceで未解釈だった情報も失わず報告 |
| CNV-003 | 明示loss policyとfallback | ConversionOptions | P4 | 部分対応 | unsafe model/参照破損は許可で迂回しない |
| CNV-004 | stale planと原本外部変更検出 | SourceSnapshot | P1 | 未実装 | model/assets/options/sourceの変更を検知 |
| CNV-005 | 参照を保つimport/duplicate | ImportPlan | P1 | 拒否 | opaque依存が不明なら編集を拒否 |
| CNV-006 | 編集transaction・rollback | Transaction | P1 | 未実装 | closure失敗で部分model変更を反映しない |
| CNV-007 | 構造diff・change summary | PresentationDiff | P1 | 未実装 | IDと意味を基に変更対象を報告 |
| CNV-008 | renderer fallbackと外観固定 | ConversionFallback | P8 | 未実装 | image化と文字のeditability損失を診断 |
| CNV-009 | PPTX↔ODP↔Keynoteの全方向 | ConversionMatrix | P6 | 拒否 | 6方向を元producer×dest profileで検証 |

## QA 検証・性能・スキーマ追跡

機能数や成功件数だけで互換性を判定しない。

| 形式 | 表現・探索先 |
|---|---|
| PPTX/PPTM | OOXML XSD/拡張と実アプリ、MS-PPT record台帳 |
| ODP | ODF RNG/プロパティ表とLibreOffice実アプリ |
| Keynote | app version/registry/unknown typesとKeynote実アプリ |

根拠・探索資料: [S01](https://ecma-international.org/publications-and-standards/standards/ecma-376/)、[S03](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-pptx/efd8bb2d-d888-4e2e-af25-cad476730c9f)、[S05](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-ppt/6be79dde-33c1-4c1b-8ccc-4b2301c08662)、[S07](https://docs.oasis-open.org/office/OpenDocument/v1.4/os/part2-packages/OpenDocument-v1.4-os-part2-packages.html)、[S08](https://docs.oasis-open.org/office/OpenDocument/v1.4/OpenDocument-v1.4-part3-schema.pdf)、[S11](https://support.apple.com/guide/keynote/welcome/mac)、[S15](https://github.com/psobot/keynote-parser)。内部表現候補は規範仕様と解析資料を区別して検証する。

| ID | 機能 | API/モデル案 | 工程 | 現行PPTX | 固有の受入条件 |
|---|---|---|---|---|---|
| QA-001 | 全schema/field/recordの詳細台帳 | CoverageLedger | P0 | 未実装 | reachable項目の未分類ゼロ、対象外理由を記録 |
| QA-002 | 機能ごとの架空producer fixtures | FixtureManifest | P0 | 部分対応 | read/create/edit/preserve/convertの証拠を紐付け |
| QA-003 | 独立parser・schema検証 | InteropOracle | P0 | 部分対応 | 対応範囲と未判定を可視化 |
| QA-004 | 実アプリopen/resave・修復要求 | ApplicationOracle | P0 | 部分対応 | 版・OS・保存可否を記録し未実施を区別 |
| QA-005 | 画像/PDFの外観比較 | VisualOracle | P8 | 部分対応 | 同フォント/OSで差と許容値を記録 |
| QA-006 | 再生・interactive動作比較 | PlaybackOracle | P8 | 未実装 | イベント時刻・録画・操作結果を照合 |
| QA-007 | 破損negative/fuzz・参照graph検査 | SafetyOracle | P1 | 部分対応 | truncated/overflow/cycle/unknown依存を検出 |
| QA-008 | 時間とpeak RSS・規模別benchmark | BenchmarkSuite | P2 | 部分対応 | 同じ操作で時間/RSSを併記、比較は交互実行 |
| QA-009 | API consumer/部分リンク/Swift6 | APIContract | P1 | 部分対応 | 機能追加でも第三者codecと現行作例が動く |

## 根拠の種類

| ID | 資料 | 種類 |
|---|---|---|
| S01 | [ECMA-376](https://ecma-international.org/publications-and-standards/standards/ecma-376/) | 規範仕様入口 |
| S02 | [PresentationML構造](https://learn.microsoft.com/en-us/office/open-xml/presentation/structure-of-a-presentationml-document) | 提供者資料 |
| S03 | [MS-PPTX](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-pptx/efd8bb2d-d888-4e2e-af25-cad476730c9f) | 規範拡張仕様 |
| S04 | [PowerPoint形式一覧](https://learn.microsoft.com/en-us/office/compatibility/office-file-format-reference) | 提供者資料 |
| S05 | [MS-PPT](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-ppt/6be79dde-33c1-4c1b-8ccc-4b2301c08662) | 規範バイナリ仕様 |
| S06 | [MS-OFFCRYPTO](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-offcrypto/11dfbc00-031a-44bc-a836-e7b9872438fd) | 規範暗号仕様 |
| S07 | [ODF 1.4 Packages](https://docs.oasis-open.org/office/OpenDocument/v1.4/os/part2-packages/OpenDocument-v1.4-os-part2-packages.html) | 規範仕様 |
| S08 | [ODF 1.4 Schema](https://docs.oasis-open.org/office/OpenDocument/v1.4/OpenDocument-v1.4-part3-schema.pdf) | 規範仕様 |
| S09 | [Impressフィルター](https://help.libreoffice.org/latest/en-US/text/shared/guide/convertfilters.html) | 提供者資料 |
| S10 | [LibreOffice描画プロパティ](https://raw.githubusercontent.com/LibreOffice/core/master/xmloff/source/draw/sdpropls.cxx) | 提供者実装・可変ブランチ |
| S11 | [Keynoteガイド](https://support.apple.com/guide/keynote/welcome/mac) | 提供者機能資料 |
| S12 | [iWorkパッケージと単一ファイル](https://support.apple.com/en-il/119883) | 提供者機能資料 |
| S13 | [iWork書き出し](https://support.apple.com/en-gb/105050) | 提供者機能資料 |
| S14 | [iWorkFileFormat](https://raw.githubusercontent.com/obriensp/iWorkFileFormat/master/Docs/index.md) | 解析者の一次観察・旧世代 |
| S15 | [keynote-parser](https://github.com/psobot/keynote-parser) | 解析実装・可変ブランチ |
| S16 | [Keynote表の数式](https://support.apple.com/en-euro/guide/keynote/tanfb0588a84/mac) | 提供者機能資料 |
| S17 | [Keynoteチャート](https://support.apple.com/en-euro/guide/keynote/tan1a8924264/mac) | 提供者機能資料 |
| S18 | [Keynote遷移](https://support.apple.com/en-euro/guide/keynote/tanff5ae749e/mac) | 提供者機能資料 |
| S19 | [Keynote数式](https://support.apple.com/en-au/guide/keynote/tan72a69d01f/mac) | 提供者機能資料 |
| S20 | [Keynote録画](https://support.apple.com/guide/keynote/record-presentations-tan81813d552/mac) | 提供者機能資料 |

追加の未知要素はこの台帳へ分類し、詳細スキーマ台帳でQName/field/record単位の未分類を追う。達成条件は[形式調査](format-research.md)と[実装計画](implementation-roadmap.md)に従う。
