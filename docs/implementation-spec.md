# SwiftSlides 実装仕様

この仕様はAPIと対応境界の正典。初期開発版、API互換性は未保証。

## 将来仕様と実装計画

現行契約は本書の以下の節と`docs/support.json`に記す。次の文書は将来設計であり、記載したAPI・形式・機能は実装済みを意味しない。

- [形式調査](format-research.md): OOXML、ODF、Keynoteの根拠・形式の範囲・完全再現の評価方法。
- [機能台帳](feature-catalog.md): 読取・生成・編集・保持・変換で必要になる機能。正典データは`feature-catalog.json`、生成は`python3 scripts/build-feature-catalog.py`、整合検査は同コマンドの`--check`。
- [API将来設計](api-design.md): SwiftSheetsを参考にした値型モデル、保存計画、遅延読取、形式固有機能の契約。
- [実装計画](implementation-roadmap.md): 依存順、試作、受入条件、互換性・性能の測定計画。

新APIは実装する段階で本書の現行契約へ移し、対応台帳と回帰検査を更新する。計画だけでREADMEの対応表示を増やさない。

## 構成と共通モデル

Swift 6.4以上、Swift 6言語モード。2026-10-03時点の最新安定版6.4を最低ツールチェーンとCIに固定する。macOS 14 / iOS 17以上、Foundation/FoundationXMLとシステムzlib。外部Swift依存なし。
SlideCore: Sendableの値型Presentation/Slide/Element/TextBody/Paragraph/TextRun/Table/Image/Geometry、コーデック契約、ZIP/XML。
SlidePPTX: ECMA-376 / ISO 29500 PresentationML。SwiftSlides:再公開と便利な入口。
寸法はポイント(1 pt = 12,700 EMU)、角度は度。配列はファイル順・描画順。
共通モデルは形式固有のXML名を公開APIの主語にしない。テーマ色・未解決のスタイルは参照として保持し、解決済み外観と混同しない。
ODPはSlideODPの読取専用codec。Keynoteは限定wire試作のみでcodecは未提供。

## Swift並行処理と能力照会

`CodecSet`と`Presentation`のread / inspect / encoded（CodecSetはwrite）/ URL保存に同名の`async throws` overloadを提供する。`Presentation.data`と`asset(at:)`にも非同期入口を提供する。同期initializerと同期関数は維持する。async文脈では同名overloadが選ばれるため、既存呼出しに`await`が必要になる場合がある。

コーデックの同期protocolは維持し、非同期の実処理を`@concurrent`で呼出元のActorから汎用executorへ移す。UIのMainActorからawaitできる。FoundationのファイルI/O自体は同期であり、OSの非同期ディスクI/Oや処理時間短縮を保証するものではない。`Task.detached`を使わず、task priority・task local・キャンセルを引き継ぐ。全公開結果・モデル・codecは`Sendable`。可変XMLツリーとwriterは操作内だけで所有する。

`readAll(contentsOf:options:maxConcurrentReads:) async throws -> [ReadResult]`は構造化TaskGroupで同時文書数を制限する（既定4、正の整数のみ）。結果は入力URL順。失敗・親キャンセルで残りをキャンセルし、子Taskの終了を待ってthrowする。上限は同時処理数で、結果全体・プロセスRSS・全ファイル合計の予算ではない。各ファイルにはPackageLimitsを個別適用する。単一文書内の並行解析は未提供。選択readerの需要駆動AsyncSequenceは下記Hの契約を持つ。

キャンセルは開始前、ZIP entry、展開・圧縮chunk、XML callback、スライド・要素処理の境界で協調的に確認する。`CancellationError`を破損・空データ・警告へ変換しない。第三者codecが確認しない区間、Foundationのファイル読書き、XML文字列生成など単一同期処理を強制中断する契約ではない。URL保存はencode後、一時fileへの64KiB書込境界、fsync前、renameによるatomic確定直前にキャンセルを確認する。最後の確認を通過した後のキャンセルでは保存が成功し得る。確定後にキャンセルエラーを返さない。同一URLの並行書込を直列化する責任は呼出側にある。

`CodecSet.capabilities(for:)`は登録codecの`CodecCapabilities`を返し、未登録形式は`noCodec`をthrowする。inspect/read/create/edit/preserve/convert/render/playの状態はsupported / partial / preserveOnly / unsupported / notApplicable / unverified。未記載はunverified。第三者codecには全項目unverifiedの既定値を提供する。

`CodecCapabilities.features`は`FeatureID`（機能台帳のID）、`CapabilityProfile`、操作ごとの`FeatureCapability`を返す。`capability(for:operation:profile:)`で照会できる。プロファイルは拡張可能な文字列型で、PPTXの`ooxmlTransitional`/`ooxmlStrict`、ODPの`odf12`/`odf13`/`odf14`を区別する。形式はCodecCapabilitiesのformatに従う。未掲載の機能・操作・プロファイル、および重複した宣言はunverifiedとし、形式全体の能力や別プロファイルの結果から補完しない。保存のプロファイル指定や文書単位の保存可否判定はまだ提供しない。

詳細能力の正典は`docs/capabilities.json`。`python3 scripts/build-capabilities.py`でPPTX/ODPの宣言を生成し、`--check`で機能ID・重複・fixtureのSHA-256・対応テスト・操作/プロファイル別の証拠・生成結果を検査する。`CapabilityEvidence`は架空fixtureと回帰テストの定義・検証範囲を示す。テスト実行結果や実アプリ互換性の証明ではない。fixtureの加工条件はscopeに記す。掲載した限定範囲以外は未検証のままとする。

`ReadResult.diagnostics`、`WriteResult.diagnostics`、`Presentation.readDiagnostics`は既存warningsの構造化投影。拡張可能な`DiagnosticCode`、read/write段階、severity、action、FeatureID（判明時のみ）、part/sourceElement/slideID/elementIDの位置、件数・説明を返す。sourceElementは従来のwarning.elementであり、XMLのlocal name等とモデルIDを同一視しない。未知の機能・位置を文言やlocal nameから推測しない。collectorは機能と位置が同じ診断だけ集約する。既存のwarnings、count、strict保存・危険編集の拒否規則は維持する。構造化診断が空でも完全互換を意味しない。参照inventoryとSavePlanは下記の契約を持つ。

`Presentation.preservationSummary`はsourceFormat、原本有無・bytes、保持パーツ数、現在モデル内のopaque要素数、読取時警告の集計を返す。パーツを展開せず、グループ内opaqueも数える。未知パーツの完全列挙、依存inventory、署名検証、マクロ解釈、変換可能性は含まない。原本のない新規文書では原本bytes/partsは0。ReadResultからも同じ概要を取得できる。

`Span` / `InlineArray` / ownership関連機能は、低層parserの測定後に採用する。OS上の利用可能性と安全性を確認せずに導入しない。actorは将来の共有cacheや状態所有者へ使い、不変の文書モデルをactorへ置き換えない。

根拠: [Swift 6.4](https://www.swift.org/blog/swift-6.4-released/)、[Concurrency](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/)、[SE-0461](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md)。

## 読み取り

### 表示用の直接値の投影

描画用の情報取得をライブラリの責務とし、OS固有の描画・文字計測・ぼかし、Excel数式評価、SmartArt自動配置は提供しない。以下は原本の直接値であり、実効外観・完全互換を保証しない。

- `TextSpacing.points` / `.percentage`はポイントと倍率（100%=1）を区別する。`ParagraphStyle`の`lineSpacingValue` / `spaceBeforeValue` / `spaceAfterValue`が旧Double属性より優先する。旧属性は表現できる単位のときだけ読取で設定する。nilと0を区別し、`overlaying(_:)`で指定属性だけを単位ごと上書きする。`TextBody.listStyle`、`Presentation.defaultTextStyle`、masterのtitle/body/otherスタイルは直接値として保持し、継承の自動適用はしない。
- `TextRun.field`はID、type、原本キャッシュ、field内の段落書式を保持する。`TextFieldEvaluator`は明示された番号・日時・locale・timeZoneでslidenumとGregorianのdatetime / datetime1〜13 / datetimeFigureOutを評価し、未知・不正・特殊暦はキャッシュと診断を返す。datetimeはlocaleのshort date/timeとする。読取と評価はモデル・原本を変更しない。明示的保存時はrun.textとfield.cachedTextの一致が必要。`Presentation.firstSlideNumber`は未指定と整数を区別し、番号は非表示スライドも含む現在の文書順で求める。
- `Color.value(ColorValue)`はsRGB/scheme/system/scRGB/HSL/presetの基本値とXML順の変換を保持する。変換なしのsRGB/schemeは既存ケースを使う。`ColorResolver`は明示されたtheme/colorMap/phClrとalpha/alphaMod/alphaOffのみを初期解決対象とし、その他は値と診断を返す。未解決値を成功したRGBへ変えない。新しい色ケースは読取専用で、新規生成・変更保存は拒否する。既存のColorをswitchする利用者は新ケースへの対応が必要。
- `Presentation.readLayout(at:)` / `readMaster(at:)`は原本または取り込みパーツから共通Element/画像/表を読み、パーツ参照・背景・色map・showMasterSp・文字既定・themeOverrideと診断を返す。IDはパーツ内で一意で、パーツpathと組にして扱う。slideへ継承要素やサンプル文字を自動追加しない。外部取得はしない。
- `Element.customGeometry`はパス固有座標、move/line/quadratic/cubic/arc/close、guide/adjustment式を保持する。数値パスは利用可能。式・円弧の評価は未提供で診断する。`Element.effects`は直接効果リスト、外側の影の寸法・角度・色とeffectRefを保持する。未知効果・DAGはXMLと診断を保持する。テーマeffect styleも投影する。自由曲線・効果の新規生成や属性変更保存は拒否する。
- `Element.chart`は2D bar/line/pieを中心に元part、種類、grouping、系列順・タイトル・カテゴリ・値のcache/literal・数式・軸・凡例・書式XMLを読む。欠落indexを0で補わず疎な点列として保持する。外部・埋込データは参照だけを返し更新しない。unsupported種類・高度な書式は診断する。要素kindはopaqueを維持し、新規生成・変更保存は拒否する。
- `Element.diagram`はdata/layout/quickStyle/colors/drawingの参照、データの文字と保存済みdrawingのElementを読む。描画がない場合は診断し、自動配置しない。DrawingML diagramの名前空間を確認し、循環や不正なパーツを空データに変えない。kindはopaqueで、編集保存は拒否する。

新しいoptionalモデル属性がない旧JSONはnilとして読める。PPTX Transitional/Strictの合成fixtureで投影・原本保持・危険編集拒否を検証する。ODPについて新しい機能の対応を推測しない。read/preserveとcreate/edit/renderの能力は分けて台帳へ記す。

フィールド形式の根拠: [Microsoft fld仕様](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oi29500/209a8afb-4ce6-4ad9-ad6b-f18da263502e)。色変換の根拠: [DrawingML Primer](https://download.microsoft.com/download/e/1/4/e14fb96f-83b8-4a2a-84db-7fa8acbe061a/Office%20Open%20XML%20Part%203%20-%20Primer.pdf)。

### 共通APIの整合性と値型編集

`Codec.format`、`CodecSet.formats`、`contains(_:)`、`codec(for:)`で登録を照会する。formatsは最初の登録順で重複を含まず、同じ形式を再登録すると実装だけを最後のものへ置き換える。公開Codecは選択を表し、実装の呼出しはCodecSetを通す。第三者の`PresentationCodec`拡張点は維持する。

Data入口の`Presentation(data:format:options:)`、`Presentation.read(_:format:options:)`、`inspect(_:format:limits:)`はCodecSetと同じ形式指定を受ける。省略時は内容で判定し、指定時はそのcodecが内容を検査する。URLの読取形式を拡張子から推測しない。

`Presentation.editSlide(id:_:)`、`Slide.editElement(id:_:)`、`Element.editText(_:)`はクロージャーの戻り値を返し、正常終了時だけ変更を反映する。対象不在は`slideNotFound(id:)` / `elementNotFound(id:)`、重複・空ID・対象のID変更・文字を編集できないkindまたはtext欠落は`invalidModel`で拒否する。elementの検索はgroupのchildrenも含む。slide IDは文書内、element IDはgroupも含めスライド内で一意。同名slideと別slide間の同じelement IDは許容する。editTextは既存のshapeのTextBodyを編集し、opaque・画像・表・connectorへ文字を追加しない。失敗時は値と原本保持情報を維持する。

これらの編集はIDの整合性を検査するモデル操作であり、全書式・元形式の保存可否はwrite/planWriteで検査する。`CodecSet.transaction(_:options:_:)`とumbrellaの`Presentation.transaction(options:_:)`は複数の編集を仮の値へ適用し、現在の元形式（新規ならPPTX）でエンコード検査が成功した場合だけ文書へ反映する。戻り値は検査で生成した`WriteResult(data,warnings)`。strictの既定値はtrue。クロージャー失敗・不正モデル・危険編集・警告によるstrict拒否・キャンセルでは文書を変更しない。ファイルへは保存しない。エンコード時間と出力Dataのメモリが必要で、COW編集の高速性は未測定。第三者codecの検査内容はそのwrite契約に従う。

Presentation(data:)/contentsOf、read、inspect。CodecSetで個別リンクも同じ操作。
OPCのroot relationshipからmainPart、スライドrelationshipから順序を解決。固定パスを仮定しない。
PPTX/PPTM、Transitional/Strict、stored/deflated ZIPとZIP64の読み取り。
スライド寸法、名前、表示フラグ、図形/コネクタ/グループ/画像/表、直接指定の文字と段落書式、内部・外部リンク、ノート、メタデータをモデル化。
グループ内座標は親ローカル座標。グループのchildFrameも保持。継承レイアウトとテーマは原本パーツとして保持、外観計算はしない。
画像は内部参照とサイズ・代替文。画像バイトはasset(at:)で必要時にCRC検証・展開。
Chart/SmartArtはopaqueの原本に加え、上記の限定投影を提供する。OLE/動画/数式/アニメーション/遷移/拡張XMLは未解釈として原本に保持、警告。
未知の図形はopaque要素、元XMLとパーツは保全。
ノート省略指定時は警告、保存時は原本ノートを維持。
OLEコンテナ(旧PPTまたは暗号化Office)、暗号ZIP、壊れたXML、欠落relationship、重複ID、制限超過はthrow。
ODP ZIPはSlideODPの読取専用codecを提供する。Keynoteはenumと設計を提供、IWAの型判定前にKeynoteとして推測しない。
Keynoteの将来コーデックは検証時点の最新版だけを実アプリ確認の対象とする。実際に確認したアプリ版・OS・文書registryを記録し、旧版確認を公開の必須条件にしない。未検証の文書世代を最新版の確認から対応済みと推測せず、安全性を判断できない入力は拒否する。

## 保存

### 参照inventory（B）

`Presentation.inspectPreservation()`と個別リンクの`CodecSet.inspectPreservation(_:)`は、PPTX/PPTM原本の`PackageGraph`を返す。全relationshipとXML内のrelationship属性、timingのshape target、connector endpointを、part・namespace付きXML経路・属性・所属slide/elementの位置とともに列挙する。論理slide/element IDと元part/IDの対応も返す。原本IDがないopaque要素では生成したモデルIDを原本IDと推測せずsourceIDをnilにする。外部参照は取得しない。モデル変更後も原本のinventoryであり、保存後のgraphではない。

公開仕様で確認したscalar metadata（creation/modification ID・画像保存設定）以外の未知namespace/拡張の参照は既知と推測せず、未知の属性と未解決scopeを残す。XMLを展開・CRC確認するため通常readより重い。非XML内容の内部参照は解釈せず`uninspectedParts`へ記録し、完全な依存解釈を保証しない。新規文書は原本graphが空。第三者codecは追加protocolに対応しない限りinventoryを拒否する。

要素・スライド削除はこのgraphで既知参照を検査し、影響範囲の未知scopeが残る場合も拒否する。削除される要素同士の参照は許容するが、残る要素からのtiming/connector参照は拒否する。未変更保存と無関係の局所編集は従来どおり原本を保持する。

### 保存計画（C）

`planWrite(as:options:)`は現行writerで出力を事前生成し、不変の`SavePlan`にformat、判明した出力profile、copy/create/patch/removeのpart actions、diagnostics、canSave、変更part数・展開bytes、source/model/optionsのSHA-256 fingerprintを持たせる。初期版は遅延計画ではなく、エンコード時間と出力Dataのメモリが必要。新規・編集・未変更経路を区別する。モデル不正、危険編集、未登録codecはcanSave=falseの診断となる。破損・制限超過・キャンセル・予期しないエラーはthrowし、拒否を空データの成功へ変えない。拒否計画の診断は最初の停止理由であり全理由の網羅を保証しない。

`encoded(using:)`と`save(to:using:)`は計画の原本・モデル・options一致を再検査し、違えば`SlideError.stalePlan`で拒否する。options省略時は計画時の値を使う。公開varによる直接変更と同じIDの別原本への置換も検知する。計画は読み取ったData snapshotに結び付き、元URLの後日の変更は追跡しない。保存先が原本URLと同じでも読み込みsnapshotを保存する契約であり、ファイル監視・遅延file readerは未実装。

計画の出力Dataをatomic保存し、確定直前を最後のキャンセル確認とする。失敗・stale・キャンセルで出力先を置換しない。第三者codecも現行write契約から計画を作れるが、part actionsはPPTX/PPTMでのみ提供する。計画が保存可能でも実アプリ互換性や全CRC確認の証明にはならない。

計画は作成時の`Codec`選択にも結び付く。同じ形式でも別のCodecを再登録した集合ではstalePlanを返す。CodecSetの値コピー、同じCodec値から作った別集合、`codec(for:)`で取り出した選択の再登録は同じ計画を使える。形式名や実装の型名だけでは同じ設定のcodecと推測しない。第三者codecのwrite設定が変わる場合は新しいCodec値を登録する。同じ選択内の共有可変状態の変化は追跡しない。

### 明示的な複製・取り込み（D）

`duplicateSlide(id:at:)`、`importSlide(id:from:at:options:)`と個別リンクのCodecSet入口は、新しいslide identityを返す。挿入位置省略時は末尾。範囲・対象・参照が不正ならthrowし、文書を変更しない。既存の値をそのままappendする操作は引き続き重複IDとして拒否する。

PPTX/PPTM複製は原本XML、notes、chartと埋込Workbook、内部/外部リンク、画像・媒体を保持する。shape IDはslide内のローカルIDとして維持し、timing/connector対象も維持する。複製partのcreation/modification IDとfield UUIDは新規発行する。notes/chartは独立したpartへ複製し、同じ原本のlayout/master/theme/assetsは共有する。自己リンクは複製先、他のslideへのリンクは元の対象へ向ける。取り込みは同じ寸法・OOXMLプロファイルのPPTXに限定し、layout/master/themeも衝突しないpartへコピーする。別slideリンクには`SlideImportOptions.slideLinks`でsource slide ID→destination slide IDを明示する。自己リンクは自動処理する。内部Targetのfragmentは保持し、空白等を含むpartパスはURI escapeして保存する。

未知参照・未知scope、異なるnotes masterの併存、独自table style、マクロ/署名の別文書取り込み、異寸法・異プロファイルは拒否する。notes masterは仕様上最大一つなので、既存masterと整合を証明できない場合に黙って差し替えない。Strict新規生成は未提供だが、同じStrict原本内の複製は既存XMLから行える。chartの表示cacheや式を再計算しない。新規文書の複製も一度PPTXに正規化するため、返す要素IDは元のUUIDから変わり得る。

初期版はsourceの現行モデルをエンコードして安定したsnapshotを作り、依存graphをコピーし、targetの保存検査を通してから反映する。大容量cloneの遅延I/O・性能は未測定。staged partsはasset(at:)から取得でき、計画fingerprintにも含める。取り込み後のモデル変更は通常の部分編集規則で検査する。元のURLやsourceの後日の変更は取り込みsnapshotへ影響しない。

新規PPTX:theme/master/layoutとその参照、presentation、slide、notes、media、content types、metadataを出力。
保存APIはdata(as:options:) / write(to:as:options:) とWriteResult(data,warnings)。URL書き込みはatomic。
保存形式は明示指定→元形式→PPTXの順で決め、拡張子によって変換しない。`PresentationFormat(fileExtension:)`はpptx/pptm/odp/keyを大文字小文字を区別せず認識し、`fileExtension`で標準拡張子を返す。writeとSavePlanのsaveは、認識できる保存先拡張子が出力形式と違う場合に`outputFormatMismatch(format:fileExtension:)`をthrowし、保存先を変更しない。拡張子なし・未知拡張子は形式を変えない。
write/save/transactionのWriteResultはdiscardableにしない。警告を確認するか、`_ =`で明示的に破棄する。既存のdata便利APIは互換のため維持するが、警告を確認する用途はencoded/writeを使う。
既存PPTX/PPTM:元ZIPをバックアップとして所有。未変更保存は原本Dataを返す。
編集保存:不変パーツの展開内容をそのまま保持し、変更ノードをパッチ。既存図形ID・参照・未対応プロパティを維持。
文字編集は文字本体を置換するため、未対応の文字領域書式を含む場合は警告。strict保存は警告のある書き換えを拒否。
スライド追加・削除・並べ替え、要素追加・削除・並べ替えを提供。既存スライドの単純appendは二重のidentityとして拒否。複製はduplicateSlide、別文書はimportSlideを使う。
削除したスライドの未参照パーツは残す。リンク等で削除対象を参照する既存XMLは検出して危険な編集を拒否。
図形種類変更、既存グループ構造など安全にパッチできない変更はthrow。失敗を警告だけに変えない。
PPTMのマクロは保持し警告、実行しない。PPTM→PPTXの暗黙変換は拒否。署名済みパッケージは未変更保存のみ許可。
新規modelの不正値(非有限寸法、負のサイズ、重複ID、空画像形式、不正色、非矩形表など)は保存前にthrow。
圧縮保存はDEFLATE、ZIP32のサイズ上限を検査。読める範囲と書ける範囲の違いは明示する。

## 安全性と検証

既定:10,000 ZIP entries、合計512MiB展開、1 part128MiB、XML深さ128、2,000,000 nodes。
上限は宣言サイズ/解析量の制約でありプロセスメモリ保証ではない。DTD/ENTITYを拒否、外部参照は取得しない。
inspectはmain XML/metadataを読むが、全アセットCRC検証を保証しない。読む・編集するパーツとassetは展開時にCRC検証し、未変更パーツの圧縮済payload転写では展開しない。
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

既存ノートmasterを使ったノート追加は、原本のbody/sldImg/sldNumのplaceholder idxを参照する。bodyが一意でなければ保存を拒否する。

新規・変更geometryはDrawingML ST_ShapeTypeの187プリセットに限る。未知の既存geometryは原本のまま保持できるが、新規生成には使わない。

## ODP読取と書式索引（E・F）

`SlideODP`製品と`Codec.odp`を提供し、umbrellaの`CodecSet.all`へ登録する。ODF 1.2/1.3/1.4のZIP presentationだけを対象とし、mimetype、manifest、content/stylesのnamespace/version・必須参照を検査する。暗号、未知version、Flat XMLは拒否する。ODPのcreate/edit/convert/render/playはunsupportedで、writeは常に拒否する。原本は読取結果内に保持しasset(at:)で取得できるが、未変更ODP保存もこの段階では提供しない。PPTXへ黙って変換しない。

基本のrect/ellipse/line、text frame、group、内部画像、表、notes、metadataを投影する。transform/custom geometry/埋込object等はopaqueまたは保持診断にし、opaque custom-shapeの直接段落は表示文字だけ投影し、未知内容を空の成功に変えない。外部画像は取得せずopaqueとして保持する。automatic style自身のpropertyを直接指定としてモデルへ投影し、named parent/masterの継承値で埋めない。異なるスライド寸法は単一sizeで正確に表せないため拒否する。表の反復展開はPackageLimits.maxTableCells（既定1,000,000）で制限する。未対応の式・型・結合や列幅の未解決を診断し原本に保持する。

`ODPCodec.styleIndex`の`ODPStyleIndex.resolve`はdefault、named parent chain、automatic、drawing-pageのmaster、直接propertyを解決しproperty単位の出典を返す。キーはnamespace URIとlocal nameを`|`で結んだ文字列。familyとcontent/stylesのautomatic scopeを分離し、parentはnamed styleだけから引く。none、未指定、未解決を区別し、循環は失敗、継承深さはmaxXMLDepthで制限し、未知style/masterはunresolvedで返す。文字計測やmaster上の図形・placeholderの外観計算はしない。

## 選択readerとatomic file target（H）

`CodecSet.slideReader(_:format:options:)` / `slideReader(contentsOf:options:)`は同期・async双方で選択readerを開く。umbrellaはcodecsを省略できる`SlideReader(data:format:options:)` / `SlideReader(contentsOf:options:)`も提供する。Dataの明示format・PackageLimits・includeNotesを全入口で引き継ぐ。`SlideReader.asset(at:)`と計画の`encoded(using:)`にもasync overloadを提供し、実処理を`@concurrent`で呼出元Actorから移す。

`SlideReader(data:/contentsOf:codecs:options:)`は不変snapshotと形式別索引を保持する。`summary`、`slideDescriptors`、`slide(id:)`、`asset(at:)`、需要駆動の`slides(selection:)`を提供する。結果は`SlideReadResult(slide,warnings)`で、部分Presentationを生成しない。PPTXはheader/ZIP索引を共有し、本文は要求した1枚だけ解析する。ODPは単一content.xmlを開く時に走査しpage XMLとstyle索引を保持するのでindexは文書サイズに比例する。全CRC検査・file監視・bounded asset cacheは提供しない。URL入口はファイルをmemoryへ読み取るsnapshotで、元URLの後日の変更には影響されない。

`FileTarget`は出力Dataを同じディレクトリの専用一時fileへ分割書込みし、キャンセル・write/fsync/rename失敗では元の保存先を保持する。確定直前にキャンセル確認し、rename後にキャンセル失敗を返さない。既存URL保存とSavePlan保存も同じ経路を使う。これはエンコード済Dataのsinkで、StreamingWriter・メモリ一定のエンコードではない。失敗検査はENOSPCの注入と専用16MiB HFS+ volumeでの実容量不足を別々に確認する。既存fileのpermissionは維持するがACL/xattr転送、directory fsyncによる停電耐性は保証しない。

## Keynote限定試作（G）

公開codecへ登録せず、`scripts/probe-keynote.py`でSnappy/IWAのwire境界・type ID・未知fieldを保持する限定試作を行う。型registryの由来・hash・fixture/app/OSを記録し、意味が確認された文字fieldだけを局所変更する。アプリからの型抽出や再署名はしない。再包装・局所変更後の実アプリ再読と再保存の結果を個別に記録し、未検証の型と世代を対応済みとしない。
