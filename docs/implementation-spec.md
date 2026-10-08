# SwiftSlides 実装仕様

この仕様はAPIと対応境界の正典。初期開発版、API互換性は未保証。

## API全体レビューによる統一（2026-10-08）

SwiftSheetsの1.0前の整理（B.46–B.68、B.89–B.94）に合わせ、文書操作は`CodecSet`とumbrellaの同じ動詞・ラベルを使う。メモリ保存の正規入口は`Presentation.write(as:options:)`、計画済み保存は`write(using:options:)`とする。公開前の0.1.0で`data` / `encoded` / `save`の別名を削除し、警告を受け取れる`write`へ一本化する。`WriteResult.data`と`warnings`は不変とする。`inspect`は全入口・公開codecで`InspectOptions(limits:)`を受ける。エラーの引数ラベルは`noCodec(for:)`と`unsupportedEncryption(detail:)`へ揃える。URLのread / inspect / slideReaderとpassword付き入口にも`format:`を提供する。省略時は内容判定、明示時は選択codecの内容検査とし、拡張子から推測しない。

具体的な組込codecはpackage限定とし、公開する選択は`Codec.pptx`等へ一本化する。第三者用protocolは維持する。ODP書式索引は`ODPStyleIndex(data:limits:)` / `init(contentsOf:limits:)`から取得する。Boolの動詞は`includesNotes` / `showsMasterShapes` / `rotatesWithShape` / `advancesOnClick`とし、折返しは`wrapsText`、反転は`isFlippedHorizontally` / `isFlippedVertically`とする。モデルJSONの既存キーはCodingKeysで維持し、ファイル形式の属性名は変えない。

`ReadOptions`の全設定はinitializerで渡せる。`ReaderCacheBudget`はumbrellaとCodecSetの同期・非同期file readerでも利用可能にする。予算は保持Dataの合計であり、辞書・索引・返却モデル・解析中の一時領域やRSS全体の上限ではない。ゼロ予算では空Dataもキャッシュせず、空エントリだけで無制限に増やさない。キャッシュヒットとLRU更新は件数に比例する配列走査を行わず、挿入時の追出しだけを追出し件数に比例させる。

選択readerはdescriptorの順序・index・summary件数を検査し、不整合を破損として拒否する。並列読取は共通の有界実行器を使い、空選択でもキャンセルを検査する。XML索引は入力Dataを借用し、全体のUInt8配列を複製しない。公開XMLの子孫検索は文書順の反復走査を使い、深い木で再帰呼出しや中間配列を積み重ねない。計画作成では同じ出力ZIPを二重に索引化しない。

レイアウトの均等配置は変更前に全対象の有限座標・非負寸法と配置可能性を検査し、失敗時は配列を変更しない。負寸法や非有限値を後段の保存まで流さない。

## 追加する読取契約（2026-10-08）

残読取の追加は保存・変換から独立させる。ODF高度図形の式はmodifier・guide・組込変数と算術/関数を評価し、循環・欠損・非有限結果をthrowする。DrawingMLの追加効果と文字外観、ODFの3Dは単位を明示した値モデルと原本を併記する。3D継承はtheme/master/layout/directの出所を返す。3Dモデルは内部資源と外部参照を区別し、資源を勝手に取得しない。

チャートのworkbookはXLSXの保存済みセル値・式を取得する。埋込はpackageから、外部は呼出側が明示的に提供したbytesから読む。式の再計算やネットワーク取得は行わない。キャッシュとworkbook値は別に保持し、不一致を診断する。Keynoteの表は式の構造・保存済み値・結合領域を区別し、軸と高度書式は確認したwire schemaを使う。未知版・未知fieldは原本索引に保持し診断する。

file-backed readerは入力fileの開いたdescriptorから範囲を読み、ZIP索引と上限付きcacheを所有する。入力の変更・置換を検出して以後の読取を拒否する。Data入口のsnapshot契約は維持する。旧PPT・旧Keynote XML・旧Impressは独立した読取codecとし、形式を現行形式へ偽装しない。読取subsetと未検証範囲は能力台帳に記す。実アプリ検証は実施結果だけを記録する。

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
ODPはSlideODP、KeynoteはSlideKeynoteの読取専用codec。暗号文書は独立製品SlideDecryptで復号して通常readerへ渡す。

## Swift並行処理と能力照会

`CodecSet`と`Presentation`のread / inspect / write / URL保存に同名の`async throws` overloadを提供する。`asset(at:)`にも非同期入口を提供する。同期initializerと同期関数は維持する。async文脈では同名overloadが選ばれるため、既存呼出しに`await`が必要になる場合がある。

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

### ODPのMathMLと高度図形（追加実装）

`Element.equation`と`TextRun.equation`はODPの埋込/inline MathMLも返す。`Equation.Dialect.mathML`を追加し、token、分数、根号、上下添字、上下限、行列、semanticsの構造を元の子順で保持する。MathMLの引数は元要素の位置で区別し、OMMLの引数wrapperを捏造しない。`lexicalText`は数式tokenのみを連結し、annotation/annotation-xmlは含めない。直接math:math、および内部objectのcontent.xmlにあるMathMLルートを対象とし、同じframeのpreview画像は原本構造に残す。Content MathMLのapply/bind/演算子/変数/数値成分を型付きで返す。未知ノードはnativeと診断に残す。外部objectは取得しない。既知の引数数の不整合、欠損内部参照、XML/展開予算違反は拒否する。計算・線形式化・描画・保存を追加しない。

`Element.enhancedGeometry`はODP custom-shapeの直接type、viewBox、modifier、guide式、鏡像指定、text area、handle原本を返す。`EnhancedPathCommand`はODFの命令を型で区別し、`GeometryOperand`は数値・modifier index・guide名を区別する。命令と引数は原本順、座標はviewBox内の値で、ptへ早期換算しない。guide式は明示的なGeometryEvaluatorで評価する。省略pathはnil、明示空pathは空配列。未知命令/字句はpath全体を未解決（nil）とし原本と診断を返す。既知命令の引数数、不正な非有限数・負viewBox寸法、modifier/guide欠損・重複guideは拒否する。transformは順序付き行列へ投影する。独自draw:engineは原本と識別子を保持し、明示providerを使用できる。3D/extrusionはSpatialGeometryにも投影する。text-pathの配置指示はTextPathPropertiesへ投影し、glyph配置・文字計測は行わない。

このsubsetの根拠は[ODF 1.3 Part 3](https://docs.oasis-open.org/office/OpenDocument/v1.3/OpenDocument-v1.3-part3-schema.html)の10.4.6/10.6.2/19.145と[W3C MathML 3](https://www.w3.org/TR/MathML3/)で、ODF 1.3の合成fixtureで検査する。ODF 1.2/1.4のschemaとLibreOfficeで確認した限定範囲は検証記録を参照する。PPTXへのモデル持込・投影変更で追加値を黙って捨てず拒否する。ODP保存は読取専用のまま。

### 残対応の読取契約（2026-10-08、追加実装）

PPTXの数式は`TextRun.equation`で段落内の順序を保って返す。OMMLの分数、根号、上下添字、総和、行列、関数等を`EquationNode`の型と引数ノードへ投影し、未知ノード・書式・原本の名前空間は`Equation.source`に保持する。`TextRun.text`は数式のtextノードを文書順に連結した字句文字列であり、演算子を補った線形式や計算結果ではない。`a14:m`とOMMLの直接数式、対応名前空間だけを要求するAlternateContentのChoiceを対象とし、Fallbackと未知Choiceは同じ原本構造に保持する。未知Choiceを数式として選ばない。数式を含む文字領域の再構成・数式の新規保存を拒否する（除去してから保存する操作も含む）。無関係な位置変更・未変更保存は原本を保持する。表セル・notes・layout/masterでも同じ読取を適用する。未対応ノードは診断し、計算・LaTeX変換・描画を提供しない。

PPTXの`Element.scene3D`は直接指定のcamera preset/FOV/zoomとcamera/lightの回転、light rig/directionを、`Element.shape3D`は深さ・押出し・輪郭幅・材質・上下bevel・色を返す。寸法はpt、角度は度、zoomは100%=1。省略値はnilとし、既定値や実効継承を補わない。backdropと未知属性は各`source`に保持する。数値・必須camera/light要素の破損を拒否し、投影の変更・新規生成を拒否する。model3D資源参照と文字3Dは追加読取契約を参照。chartの3D、透視変換、描画はこのsubsetに含めない。Transitionalと名前空間置換Strictの合成fixtureで検査し、実アプリ互換性は別途unverifiedとする。

構造の参照元はMicrosoft公開[DrawingML Math](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-odrawxml/853b19c7-68a9-4f9a-a2ae-5e6cb0d02e62)、[Scene3D](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.scene3dtype)、[Shape3D](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.shape3dtype)。型識別と直接値の投影に限定する。

全機能の意味解釈と、全内容への原本アクセスを区別する。`Presentation.readSourceXML(at:)`は任意の保持XMLを、名前空間・属性・混在文字列・子要素の順序を保持した不変`SourceXMLNode`として返す。qualifiedNameとattributeNamesで元のQNameを保持し、namespaceBindingsにはその要素で有効な接頭辞→URI（既定名前空間は空文字列、xmlは標準URI）を含む。QNameを持つ属性値やMC Requiresの接頭辞はこの束縛から解決でき、子要素による接頭辞の再定義も区別する。型付きモデルにまだない拡張、数式、3D、ink、view/settings、table style、notes/handoutもこの入口から取得できる。意味の未解釈を能力台帳のsupportedへ変更する根拠にはしない。XML深さ・ノード数・partサイズ・キャンセル・CRC検査は通常の読取と共通。

新コメントは作者・rich text・reply・status・作成時刻・task属性・anchor構造を読み、従来コメントとは別の`CommentThread`を返す。位置は新コメントのEMUをptへ換算する。未知anchor/task拡張は名前空間つき木と原本XMLを保持する。チャートはscatter/bubbleのx/y/size、多段カテゴリ、全既存ChartML群の系列・軸・書式構造を取得する。描画・式再計算は行わない。

PPTXの継承読取は明示的な`resolveElement(slideID:elementID:)`で行い、layout/masterのplaceholder照合、位置・塗り・段落/文字既定を解決し、属性ごとの出典と未解決診断を返す。直接モデルや原本を変更しない。フォント計測・SmartArt配置・固有効果の評価は範囲外。あいまいなplaceholderを選ばず診断する。

ODPのanimation木、メディア、annotation、custom shape/enhanced geometry、埋込object・MathML・3Dは原本の構造と参照を投影する。既存の共通モデルへ無理に平坦化せず、未知内容と外部参照を診断する。時間値は原単位と字句値を保持する。ODPのモデルは読取専用を維持する。

KeynoteはSnappy/IWA/Protobufの上限つき不変索引とobject/data参照を追加する。型・fieldの根拠をregistryに記録し、文書順・slide・文字など確認できた意味だけを共通モデルへ投影する。未知wire fieldと型は取得可能なまま診断する。公開codecの状態は実装とfixture検査の結果に合わせて更新し、未知文書を空スライドの成功に変えない。書込みは提供しない。

暗号化文書の復号は独立製品`SlideDecrypt`で提供する。`decrypt(_:password:limits:)`とpasswordを受けるPresentation/CodecSet/SlideReaderの同期・非同期入口は、OOXML AgileのAES-CBC（128/192/256、SHA-1/256/512）とODFのAES-CBC/PBKDF2を対象とする。SwiftSheetsのMIT実装を参照し、CFB鎖・宣言サイズ・XML名前空間・KDF回数・復号展開量を検査する。パスワード不一致は`wrongPassword`、方式未対応は`unsupportedEncryption`として区別する。OOXMLは存在するHMACを検証する。証明書・IRM・RC4・Blowfish・未知保護は方式を明示して拒否する。Keynoteのiwpv2保護は下記契約で扱う。復号した原本は平文snapshotとして保持するため、通常の保存は平文となる。再暗号化は提供しない。password便利入口のReadResultにはこの事実を診断として返す。入力ファイルを変更せず、復号データのディスク一時保存はしない。

### 表示用の直接値の投影

追加の読取契約（2026-10-08）:

- `Fill.gradient` / `.pattern` / `.picture`はstop順・位置、線形角度、path、前景/背景色、内部/外部画像参照、crop・tile/stretchと原本XMLを保持する。stop listや画像参照の省略は継承で補わず、空stop/nil imageと診断で明示する。画像参照は所在partを基準に解決し、外部取得はしない。`Image.crop`は上下左右の倍率（100%=1、負値も保持）。追加の塗りとcropの生成・変更保存は拒否し、未変更値と無関係な編集は原本を保持する。
- `TableCell.borders`は上下左右と対角線の直接罫線を区別し、明示noFillを保持する。`TableCell.value`はODPのvalue-typeと字句値・通貨、`formula`は名前空間接頭辞を含む原本式を保持する。数値や日時を表示文字から推測せず、再計算しない。追加属性は読取専用で、PPTX生成・変更保存で黙って落とさない。PPTX表にも`maxTableCells`を文書全体と選択スライド単位で適用する。
- `Slide.transition`は効果名/名前空間、speed、クリック進行、進行時刻(ms)、拡張duration(ms)とXMLを保持する。`Slide.timing`は名前空間つきノード木・全属性・対象shape ID・XMLを読む。indefinite等の時間値を0に置換せず字句値として扱い、再生・トリガー評価は提供しない。
- `Element.media`はaudio/videoとOffice拡張mediaの内部/外部参照・content typeを返す。`Slide.comments`は従来コメントの作者ID/名前/イニシャル、原本日時、位置(pt)、本文、原本XMLを返す。新形式コメントや未解釈拡張は`NativeFeatureDescriptor`に原本XML・所在part・名前空間・参照を残し、意味を解釈できたと表示しない。投影変更・新規保存は拒否する。

根拠: [Microsoft Transition](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.presentation.transition)、[Microsoft Video](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.presentation.video)、[MS-PPTX新コメントpart](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-pptx/b85a9293-bdca-4c6b-a554-8f3918db9791)、[OASIS ODF 1.3 Part 3](https://docs.oasis-open.org/office/OpenDocument/v1.3/OpenDocument-v1.3-part3-schema.html)。実アプリ検証結果は`verification.md`に操作別で記録する。この直接投影契約とは別にSlideKeynoteの読取codecを提供する。全機能の意味解釈は保証しない。

描画用の情報取得をライブラリの責務とし、OS固有の描画・文字計測・ぼかし、Excel数式評価、SmartArt自動配置は提供しない。以下は原本の直接値であり、実効外観・完全互換を保証しない。

- `TextSpacing.points` / `.percentage`はポイントと倍率（100%=1）を区別する。`ParagraphStyle`の`lineSpacingValue` / `spaceBeforeValue` / `spaceAfterValue`が旧Double属性より優先する。旧属性は表現できる単位のときだけ読取で設定する。nilと0を区別し、`overlaying(_:)`で指定属性だけを単位ごと上書きする。`TextBody.listStyle`、`Presentation.defaultTextStyle`、masterのtitle/body/otherスタイルは直接値として保持し、継承の自動適用はしない。
- `TextRun.field`はID、type、原本キャッシュ、field内の段落書式を保持する。`TextFieldEvaluator`は明示された番号・日時・locale・timeZoneでslidenumとGregorianのdatetime / datetime1〜13 / datetimeFigureOutを評価し、未知・不正・特殊暦はキャッシュと診断を返す。datetimeはlocaleのshort date/timeとする。読取と評価はモデル・原本を変更しない。明示的保存時はrun.textとfield.cachedTextの一致が必要。`Presentation.firstSlideNumber`は未指定と整数を区別し、番号は非表示スライドも含む現在の文書順で求める。
- `Color.value(ColorValue)`はsRGB/scheme/system/scRGB/HSL/presetの基本値とXML順の変換を保持する。変換なしのsRGB/schemeは既存ケースを使う。`ColorResolver`は明示されたtheme/colorMap/phClrとalpha/alphaMod/alphaOffのみを初期解決対象とし、その他は値と診断を返す。未解決値を成功したRGBへ変えない。新しい色ケースは読取専用で、新規生成・変更保存は拒否する。既存のColorをswitchする利用者は新ケースへの対応が必要。
- `Presentation.readLayout(at:)` / `readMaster(at:)`は原本または取り込みパーツから共通Element/画像/表を読み、パーツ参照・背景・色map・showMasterSp・文字既定・themeOverrideと診断を返す。IDはパーツ内で一意で、パーツpathと組にして扱う。slideへ継承要素やサンプル文字を自動追加しない。外部取得はしない。
- `Element.customGeometry`はパス固有座標、move/line/quadratic/cubic/arc/close、guide/adjustment式を保持する。数値パスは利用可能。式・円弧はGeometryEvaluatorで標準演算・楕円の幾何として評価する。`Element.effects`は直接効果リスト、外側の影の寸法・角度・色とeffectRefを保持する。未知効果・DAGはXMLと診断を保持する。テーマeffect styleも投影する。自由曲線・効果の新規生成や属性変更保存は拒否する。
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
Chart/SmartArtはopaqueの原本に加え、上記の限定投影を提供する。動画・アニメーション・遷移・コメントは参照/構造/直接値を上記範囲で提供する。OLE・数式・未解釈拡張は原本に保持し、警告する。
未知の図形はopaque要素、元XMLとパーツは保全。
ノート省略指定時は警告、保存時は原本ノートを維持。
非PPTのOLEコンテナ、暗号ZIP、壊れたXML、欠落relationship、重複ID、制限超過はthrow。
ODP ZIPはSlideODPの読取専用codecを提供する。KeynoteはSlideKeynoteの限定read/inspectを提供し、ZIP markerだけで推測せずDocument/Showのwire構造を確認する。
Keynoteのcodecは検証時点の最新版だけを実アプリ確認の対象とする。実際に確認したアプリ版・OS・文書registryを記録し、旧版確認を公開の必須条件にしない。未検証の文書世代を最新版の確認から対応済みと推測せず、安全性を判断できない入力は拒否する。

## 保存

### 参照inventory（B）

`Presentation.inspectPreservation()`と個別リンクの`CodecSet.inspectPreservation(_:)`は、PPTX/PPTM原本の`PackageGraph`を返す。全relationshipとXML内のrelationship属性、timingのshape target、connector endpointを、part・namespace付きXML経路・属性・所属slide/elementの位置とともに列挙する。論理slide/element IDと元part/IDの対応も返す。原本IDがないopaque要素では生成したモデルIDを原本IDと推測せずsourceIDをnilにする。外部参照は取得しない。モデル変更後も原本のinventoryであり、保存後のgraphではない。

公開仕様で確認したscalar metadata（creation/modification ID・画像保存設定）以外の未知namespace/拡張の参照は既知と推測せず、未知の属性と未解決scopeを残す。XMLを展開・CRC確認するため通常readより重い。非XML内容の内部参照は解釈せず`uninspectedParts`へ記録し、完全な依存解釈を保証しない。新規文書は原本graphが空。第三者codecは追加protocolに対応しない限りinventoryを拒否する。

要素・スライド削除はこのgraphで既知参照を検査し、影響範囲の未知scopeが残る場合も拒否する。削除される要素同士の参照は許容するが、残る要素からのtiming/connector参照は拒否する。未変更保存と無関係の局所編集は従来どおり原本を保持する。

### 保存計画（C）

PowerPoint形式に必須の手順ではない。通常保存は`write`だけでよい。用途は、保存確認画面で変更・保持・削除パーツと警告を確認し、その確認済みbytesを再エンコードせずに保存すること。計画保持中は出力Dataもメモリに残る。単なる保存可否チェックにはエンコードとfingerprint計算の負担があり、全診断やディスク空き容量・権限の保証には使わない。

`planWrite(as:options:)`は現行writerで出力を事前生成し、不変の`SavePlan`にformat、判明した出力profile、copy/create/patch/removeのpart actions、diagnostics、canSave、変更part数・展開bytes、source/model/optionsのSHA-256 fingerprintを持たせる。初期版は遅延計画ではなく、エンコード時間と出力Dataのメモリが必要。新規・編集・未変更経路を区別する。モデル不正、危険編集、未登録codecはcanSave=falseの診断となる。破損・制限超過・キャンセル・予期しないエラーはthrowし、拒否を空データの成功へ変えない。拒否計画の診断は最初の停止理由であり全理由の網羅を保証しない。

`write(using:)`と`write(to:using:)`は計画の原本・モデル・options一致を再検査し、違えば`SlideError.stalePlan`で拒否する。options省略時は計画時の値を使う。公開varによる直接変更と同じIDの別原本への置換も検知する。計画は読み取ったData snapshotに結び付き、元URLの後日の変更は追跡しない。保存先が原本URLと同じでも読み込みsnapshotを保存する契約であり、元URLを監視する契約ではない。file-backed選択readerは別APIとして変更・置換を検出する。

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
write/transactionのWriteResultはdiscardableにしない。警告を確認するか、`_ =`で明示的に破棄する。保存はwriteのみとし、警告を結果から確認する。
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

基本のrect/ellipse/line、text frame、group、内部画像、表、notes、metadataを投影する。transform/custom geometry/埋込object等はopaqueまたは保持診断にし、opaque custom-shapeの直接段落は表示文字だけ投影し、未知内容を空の成功に変えない。外部画像は取得せずopaqueとして保持する。automatic style自身のpropertyを直接指定としてモデルへ投影し、named parent/masterの継承値で埋めない。異なるスライド寸法は単一sizeで正確に表せないため拒否する。表の反復展開はPackageLimits.maxTableCells（既定1,000,000）で制限する。式・型の未解釈部分、結合や列幅の未解決を診断し原本に保持する。

`ODPStyleIndex(data:limits:)`の`ODPStyleIndex.resolve`はdefault、named parent chain、automatic、drawing-pageのmaster、直接propertyを解決しproperty単位の出典を返す。キーはnamespace URIとlocal nameを`|`で結んだ文字列。familyとcontent/stylesのautomatic scopeを分離し、parentはnamed styleだけから引く。none、未指定、未解決を区別し、循環は失敗、継承深さはmaxXMLDepthで制限し、未知style/masterはunresolvedで返す。文字計測やmaster上の図形・placeholderの外観計算はしない。

## 選択readerとatomic file target（H）

`CodecSet.slideReader(_:format:options:)` / `slideReader(contentsOf:format:options:)`は同期・async双方で選択readerを開く。umbrellaはcodecsを省略できる`SlideReader(data:format:options:)` / `SlideReader(contentsOf:format:options:)`も提供する。Dataの明示format・PackageLimits・includesNotesを全入口で引き継ぐ。`SlideReader.asset(at:)`と計画の`write(using:)`にもasync overloadを提供し、実処理を`@concurrent`で呼出元Actorから移す。

`SlideReader(data:/contentsOf:codecs:options:)`は不変snapshotと形式別索引を保持する。`summary`、`slideDescriptors`、`slide(id:)`、`asset(at:)`、需要駆動の`slides(selection:)`を提供する。結果は`SlideReadResult(slide,warnings)`で、部分Presentationを生成しない。PPTXはheader/ZIP索引を共有し、本文は要求した1枚だけ解析する。ODPは単一content.xmlを開く時に走査しpage XMLとstyle索引を保持するのでindexは文書サイズに比例する。全CRC検査・file監視・bounded asset cacheは提供しない。URL入口はファイルをmemoryへ読み取るsnapshotで、元URLの後日の変更には影響されない。

`FileTarget`は出力Dataを同じディレクトリの専用一時fileへ分割書込みし、キャンセル・write/fsync/rename失敗では元の保存先を保持する。確定直前にキャンセル確認し、rename後にキャンセル失敗を返さない。既存URL保存とSavePlan保存も同じ経路を使う。これはエンコード済Dataのsinkで、StreamingWriter・メモリ一定のエンコードではない。失敗検査はENOSPCの注入と専用16MiB HFS+ volumeでの実容量不足を別々に確認する。既存fileのpermissionは維持するがACL/xattr転送、directory fsyncによる停電耐性は保証しない。

## Keynoteの原本索引と読取（G・追加実装）

`scripts/probe-keynote.py`の限定試作を基に、SlideKeynoteのCodec.keynoteをCodecSet.allへ登録する。Snappy/IWAを不変のKeynoteInventoryとして索引化し、全object/field/参照/原本bytesを取得可能にする。型registryの由来・hash・fixture/app/OSを記録する。試作スクリプトの再包装・同長文字fieldの局所変更と、公開codecの読取専用契約は分ける。公開codecは全Keynote保存を拒否する。アプリからの型抽出や再署名はしない。未検証の型と世代を対応済みとしない。

### Standard暗号の追加契約

SlideDecryptはOOXML Standard（2/3/4.2、AES-ECB 128/192/256bit、SHA-1、固定50,000回KDF）も読み取る。EncryptionHeader/Verifierの長さ・方式・鍵サイズを検査し、検証値の不一致はwrongPasswordにする。Standard方式に暗号package全体のHMACはないため、復号後のZIP/CRCを読取時に検査する。RC4・外部provider・IRMはunsupportedEncryption。参照: [MS-OFFCRYPTO鍵導出](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-offcrypto/84f1cce1-1e82-4e05-bc8e-91456ad44823)、[EncryptionHeader](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-offcrypto/dca653b5-b93b-48df-8e1e-0fb9e1c83b0f)。

### 現行Keynote暗号の追加契約

SlideDecryptは`.iwpv2`（version 2/format 1、104bytes）を検出する。UTF-8 passwordとsaltからPBKDF2-HMAC-SHA1でAES128鍵を導出し、CBC復号した検証値のSHA256を確認する。Index/*.iwa・Data/*・BuildVersionHistory.plist（およびIndex.zip）の暗号streamは、先頭IV・AES-CBC・PKCS7・復号先頭16bytesのprefixを扱う。末尾20bytesは公開解析の未解釈領域であり、整合性を保証しない。方式・padding・上限違反を拒否し、外部取得はしない。復号snapshotから.iwpv2/.iwphを除き、全通常入口へ渡す。現行Keynote 15.4で作成した架空文書で導出とIWA復号を独立照合する。参照: [iWorkFileFormatの一次解析](https://github.com/obriensp/iWorkFileFormat/blob/master/iWorkFileInspector/iWorkFileInspector/Crypto/NSData%2BIWCrypto.m)。再暗号化は提供しない。

### 継承styleの補足

resolveElementはmaster/layoutのplaceholder照合（layoutはidx、masterはtitle/ctrTitleを正規化したtype）と段落level別既定を重ねる。themeのfill/line/effect matrixの1-based index、backgroundの1001-based index、fontRefと+mj/+mnフォント参照を解決し、phClrの色変換順序を保持する。theme overrideは指定済み値だけを重ねる。未知参照はdiagnosticsを返し、未解決値を実効値として補完しない。色のOS依存/未対応変換、renderer/再生は別の能力である。

効果はmaster→layout→直接指定の順に重ね、明示的な空effectLst/index 0を「効果なし」として継承を止める。preset geometryとcustom geometryは同時に実効値へ残さず、最後の指定で置き換える。
上位のfill/line/effect参照が範囲外または未解決なら、その属性の実効値と出典を未解決にし、下位の継承値を成功した解決として返さない。直接指定の値が併存する場合は直接値で上書きできる。

暗号OfficeのCFBでもPackageLimits.maxEntriesを空きdirectory slotではなく有効なroot/storage/stream entryの総数へ適用し、読取前に上限超過を拒否する。

Keynoteの確認済み型はDocument 1、Show 2、SlideNode 4、Slide 5、Placeholder 7/12、Note 15、TextStorage 2001、ShapeInfo 2011、Image 3005、Group 3008、PackageMetadata 11006。slide treeとdrawableの循環・重複・参照不在を拒否する。directory packageをsnapshotへ正規化しsymlinkを拒否する。Index.zipはnested archive viewで索引し、outer assetsを一括展開しない。KeynoteInventory.dataReferencesはID・所在path・remoteURL・metadata fieldsを返し、remoteURLは取得しない。field.message(maxFields:)はschemaでmessageと確認したfieldを明示解析する入口で、任意bytesを子messageと自動推測しない。確認済み書式・式/結合・chart軸・path/build属性をモデルへ投影する。未知型/属性/版差は原本索引と警告に残る。確認済みの追加投影は次節を参照する。


### 読取の追加境界

PPTX実効styleはplaceholderのtransformをまとまりとして継承し、直接`noFill`の線と各階層の背景参照を省略から区別する。新コメントは作者・返信・task/anchorの原本構造を保持する。Keynoteは確認したTSD/TSWPのstyle参照、文字run境界、TST表のBNC v5セル、TSCH chart grid、KN build/chunkとtransitionを追加投影する。固有属性と未知型の原本wire索引は残し、式の再計算・固有効果の再生・書戻しには転用しない。セル解釈に未対応の版は空の表にせずopaqueと診断する。展開予算・参照循環・欠損参照を検査する。


### ODP埋込chart

内部draw:objectが参照するODF chartのcontent.xmlとlocal-tableを読み、seriesのlabel/category/value rangeを単純なA1範囲について解決する。ポイントの欠落は0で埋めず、rangeを解決できない場合は式/原本と診断を返す。埋込XMLの全書式、axis、plot、seriesをSourceXMLへ保持する。外部データは取得しない。local-tableの反復セルと文字は通常のODP展開予算に含む。

### Keynoteの数値Bezierパス

Shape 3004とConnectionLine 3009もshape/connectorとして読む。確認したTSP.Pathのmove/line/quadratic/cubic/closeとnaturalSizeをCustomGeometryへ投影する。PathSourceのBezier/connection-line内のBezierを対象とし、未知命令は数値パスへ誤変換せず原本wire索引へ残す。点数不整合・非有限座標・負のnaturalSizeは破損として拒否する。parameterized/editable pathや接続UUIDの評価は提供しない。nativeObjectIDから元の接続参照と全fieldを取得する。


## 残読取APIの境界

- `GeometryEvaluator.evaluate`はODF guideの算術、abs/sqrt/sin/cos/tan/atan/atan2/min/max/ifを評価。ifの非選択branchは評価しない。三角関数はradian、独自変数は呼出側から渡す。maxOperations/maxDepthで制限し、欠損・循環・非有限値を拒否する。draw:handleの旧複合位置とODF 1.4の分割位置属性を同じvaluesへ評価する。自動shape配置や座標変換は行わない。
- `TextAppearance`の長さはpt、baselineは比率、scriptは元のsuper/sub等、baselinePointsはKeynoteの元値。DrawingEffectは順序付きtreeと原本を保持する。未知属性や省略を既定値で補わない。
- `WorkbookDataReader.readXLSX`はTransitional/Strict workbookのshared/inline strings・型/字句・formula属性とセルSourceXML。A1範囲・名前付き範囲・union/intersection/3D参照を解決し、欠損セル/cacheは点列へ追加しない。ChartData.workbookPointsをchart cacheと分離し、不一致を診断する。XLSや未知参照式は原本に保持、再計算しない。
- `TableCell.nativeFormula`はKeynote TSCE postfix token、元のnode bytes、独立した保存済みcache。式の文字列化・再計算なし。merge map/merge owner tractは検証後spanへ投影する。軸はUFF/PreUFFの確認済み番号とstyle親参照を解決し、複合値のwireを保持する。
- `CodecSet.fileSlideReader`はZIPとKeynote directoryを対象に、読み込み中のサイズ/mtime/ctime/inode変更・path置換を拒否する。cacheBytesは圧縮bytes cacheだけの上限で、index/XML/modelのメモリは別。DataとcontentsOfの既存snapshot APIの意味を変えない。
- `.ppt`はCFBのCurrentUser/UserEdit/PersistDirectoryから現行slide順と本文を読む。全shape・notes・styleの意味解釈は未提供。`.keynoteLegacy`はKeynote2 XMLのsize/slide/text、`.sxi`は旧office XMLの基本page/text。全原本を保持し、未知内容はopaqueと警告。全て書込を拒否する。


## 読取残件の拡張契約（2026-10-08）

保護方式、旧PPT/旧Keynote XML/SXI、Workbookの旧XLSは追加対象外。変換・保存・再計算・描画/再生の追加も行わない。以下の読取APIは原本を変更せず、結果に元の意味・単位・未解決理由を残す。

- DrawingML geometryは全標準guide演算と組込み座標を評価する。調整値の上書き、循環/欠損/非有限値/計算予算を検査し、円弧は楕円中心・半径・角度・終点として返す。描画用の近似曲線へ丸めない。
- Workbookは大文字小文字を区別しない名前付き範囲とsheet scope、union/intersection/3D sheet range、行/列範囲を解決する。保存値だけを返し、参照を返さない式は再計算せず拒否する。共有数式は相対参照だけを平行移動し、文字列・絶対参照・原本式を保持する。
- Content MathMLはapply/bind/変数/数値/演算子/qualifier/集合/区分関数を式木として区別する。内容辞書の記号と束縛変数を保持し、任意の関数を評価しない。
- ODPの2D変形は元の順序を持つ変換列と行列へ投影する。独自engineは識別子・入力原本を保持し、呼出側が登録した解釈器に明示的に委譲できる。text-pathとchart書式/軸は構造と型付き直接値を返す。
- 追加文字外観の継承は属性単位に解決し、省略と明示解除を区別する。chartの3D view/壁/床と3D model資源は参照・構造・値を保持する。glTF/GLBは場面graph/mesh/accessorを原本とともに読む。外部資源は明示providerからだけ取得する。
- Keynoteは既知schemaの複合式参照・軸/文字/図形/build属性を構造化する。未対応型/版のbytesを既知型と推測しない。意味解釈器を拡張できる入口と原本wire保持を維持する。
- readerは文書内の上限付き並行読取、共有のbyte予算を持つcache、directory packageのfile-backed読取を追加する。索引・結果の占有量とcache量を区別し、入出力の途中変更を検出する。未知参照の診断と原本索引を明示取得できる。
- 対応範囲と完了判定は回帰検査・独立期待値・実行済みの実アプリ/OS検証へ紐付ける。未実行のOSや未知の文書世代を完了に数えない。

Flat ODPは`office:document`とpresentation MIMEを確認して`.odp`の読取経路へ渡す。埋込binary-dataだけを予算内で内部パーツとして扱い、外部URLを開かない。異なるページ寸法は`Slide.sizeOverride`に保持し、文書の既定寸法を第1ページとする。PPTXへの保存ではこの読取専用値を黙って捨てない。

### 読取専用モデルと予算の具体的な境界

`SlideReader.readSlides`は同時数を制限し選択順で返す。`ReaderCacheBudget.totalBytes`を指定したfile-backed readerでは圧縮cacheと展開索引cacheへ半分ずつ割り当てる。`cacheStatistics.retainedBytes`は現在の保持Data量、`peakRetainedBytes`は各cache peakの和（同時peakの上界）。modelはcacheへ再保持せず、assetは返却するだけ。XML/IWA位置索引・操作中のDOM/展開領域・返却結果はPackageLimitsと並列数で制限し、RSSの厳密な上限とはしない。索引のための一巡は必要だが、全ページDOMや全IWA fieldモデルは保持しない。

`SpatialGeometry.evaluated`はcube頂点・ellipsoidの中心/軸と、extrude/rotateのSVG断面・深さ/角度を返す。座標は原本の領域。draw:transformはODF 1.4/主要producerのradianを既定とし、旧規定のdegreeを明示選択できる。dr3d:transformはODF 1.2–1.4のdegree規定を使う。独自engineのプログラム実行、glyph計測、曲面の三角形化は行わない。

`Model3DReader`はglTF 2.0/GLB 2のscene/node/TRS/mesh/accessor、正規化整数・matrix padding・sparse、PBR material・skin・animation参照を解釈する。必須extensionと未供給bufferはwarningsへ出し、未知JSONもsourceに残す。外部取得は明示providerだけ。`KeynoteSchemaReader`は登録されたschemaの型を検査してNativeValueへ投影し、未知fieldを原wireのまま返す。未知版へ既知schemaの意味を自動推定しない。Keynoteの参照inventoryはIWA headerのobject/data参照を列挙し、本文の任意整数を参照と見なさない。
