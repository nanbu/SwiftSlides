# 検証手順と境界

開発時の検証記録。全PowerPoint機能・全アプリ版への互換性保証ではありません。

## 自動検査

- `swift test`:96テスト関数（パラメータ化を含む実行件数はログで確認）。公開入口、部分リンク、独立したpython-pptxの期待値、Strict/ZIP64/PPTM、破損・危険編集・並行読み取り、保存保全を検査。
- 非同期の回帰検査: MainActorからの移動とTask local継承、read/inspect/asset/encoded/URL保存、TaskGroupの同時数と結果順、失敗・親キャンセル時の子Task終了、キャンセル前の読取拒否・保存先保持、第三者codecの既定能力、保持概要。圧縮は0/1/65,535/65,536/65,537/200,000 bytesの圧縮しやすい入力・乱数入力・破損で検証。
- `swift build -c release`:最適化したライブラリとCLIをコンパイル。
- `python3 scripts/build-capabilities.py --check`:32能力宣言・23証拠の機能ID、fixture SHA-256、回帰テスト、操作/プロファイル別の範囲、生成結果を検査。13負例。実アプリ互換性の証明ではない。
- 機能別能力・診断の回帰検査: 未掲載/重複宣言のunverified、Strict/TransitionalとPPTX/PPTMの分離、旧JSON互換、未知ID・コードの保持、位置別集約、読取/保存の実データ、署名/マクロ/ノート省略、外来namespaceから機能を推測しないこと、strict拒否を検査。
- B〜Dの回帰検査: namespace/位置付き原本inventory、未知参照による削除拒否、connector/animationの対象保護、SavePlanのcopy/patch/create、SHA-256独立ベクトル、モデル・原本・optionsのstale検知、atomic失敗/キャンセル時の出力先保持、notes/chart/workbook/assetsの複製、明示link mapping、URI escaping/fragment、Strict/PPTM複製、複数importと共有依存、拒否時の文書非変更を検査。
- `python3 scripts/check-contract.py`:対応表・作例・テスト名の整合と5負例。
- `python3 scripts/check-public-content.py --history`:公開内容と全Git履歴の監査。11負例。
- `scripts/build-docs.sh`:公開シンボルをDocCへ展開。4負例、ガイド、公開アーティファクトの個人パス除去を検査。
- `python3 scripts/verify-interop.py`:python-pptx 1.0.2による作例のフォント・図形・線・表・ノート・寸法検証。
- `python3 scripts/verify-interop.py --libreoffice`:上記に加え、LibreOfficeで2種類の文書を再保存し、独立系とSwiftSlidesで再読。指定した場合、LibreOffice不在を成功扱いしない。

- `python3 scripts/verify-clone-interop.py`:公開APIだけを使う別SwiftPM consumerをコンパイルし、3種類の出力をpython-pptxで独立検査。notes/chart/embedded Workbook/images/layout/master/ID/relationshipを照合。`--libreoffice`指定時は3文書の実アプリ再保存を必須にする。

CIはmacOSとLinuxでSwift 6.4.0を指定し、同じテストを実行する設定です。APIリファレンスもSwift 6.4.0を指定したmacOSのDocCで生成します。[setup-swift v2の対応version表](https://github.com/swift-actions/setup-swift/blob/v2/src/swift-versions.ts)に6.4がないため、Swiftlyを使うv3へ移行。[v3は提供者がbetaとする版](https://github.com/swift-actions/setup-swift)で、CIの実行確認は後続です。DocCとsymbolgraph extractorは、PATHで選択されたSwiftの`-print-target-info`から同梱ツールを特定します。最新変更はローカルmacOS / Apple Swift 6.4で検証。LinuxのCI実行とiOS実行はこの変更では未検証です。

## Swift 6.4への移行

最低ツールチェーンを6.2から6.4へ上げ、Swift 6言語モードを明示。同期protocol・initializerを維持し、非同期overloadを追加しました。async文脈の同名関数はawaitが必要になる場合があります。macOS 14 / iOS 17のdeployment targetは維持しています。actor/cache/AsyncSequence/Span等の後続採用は[API設計](api-design.md)と[実装計画](implementation-roadmap.md)を参照してください。

2026-10-03、非同期API追加と圧縮処理変更後にrelease build、DocC、python-pptx 1.0.2の出力検査、LibreOfficeの2種類の文書の再保存・再読を検証しました。PowerPointでの実アプリ確認は以下の先行検証であり、今回の変更後に再実施していません。この先行検証では巨大XMLの処理途中のキャンセル遅延やディスク書込中断を測定していません。分割書込中断は以下E〜Hで検査しました。

## B〜Dの検証記録

2026-10-03、原本inventory・SavePlan・duplicate/importの追加後に85テスト関数、release build、DocC 627公開シンボル、25行の対応契約、機能/詳細能力台帳、Git履歴を含む公開監査を検査。公開consumerと部分リンクもコンパイルしました。SwiftPMの検査は実行環境の制限に合わせ、一時module cacheと`--disable-sandbox`を使用。XcodeのdSYM生成は許可された通常のホスト実行で確認しました。

python-pptx 1.0.2で複製・別資料取り込み・複製先だけのnotes編集を検査し、LibreOfficeで3文書を再保存。先行するCLI作例と既存fixtureの2文書の再保存も再検査しました。PowerPoint、Linux CI、iOSはこの変更後には未検証です。読み取り値と依存の検査であり、master継承の実効外観やアニメーション再生の一致は測定していません。

公開仕様由来のOOXML XSDで3文書中73のPresentationML/DrawingMLパーツが適合。5チャートパーツは元python-pptx fixtureと全bytes一致のまま、原本由来の負数axis IDによりunsignedIntへ不適合でした。チャートの修正は行わず保持し、適合数には含めません。通常の`--schema-dir`検査はこの違反を失敗にします。`--allow-preserved-schema-errors`を明示したときだけ、元fixtureとの全bytes一致を条件として別集計します。未知の新規違反は常に失敗にします。スキーマファイルは同梱しません。

原本inventoryの非XML内部参照、元URLを監視する遅延reader、全停止理由の収集、異寸法/profile、競合notes master、独自table styleの別文書取り込み、大容量cloneの時間/RSSは未検証・未実装です。保存計画は入力Data snapshotと事前生成した出力を保持する初期版です。

## 実アプリ

2026-10-03、PowerPoint for Mac 16.113.3でCLIの2枚の作例を開き、日本語・図形・線・表・ノートを確認しました。修復要求なし。
初期実装で出た修復要求はノートmasterのoptional ID listを生成しない構造へ変更して解消。新規ノートmasterを共有し、本文プレースホルダーも整備しています。
この環境のPowerPointは閲覧モードのため、PowerPoint自身の再保存は未検証です。

LibreOffice 26.2.3.2では作例の読み取り、再保存、PDF化を検査。2枚を画像で確認しました。
公開仕様由来のOOXML XSDを一時的に使い、新規作例のPresentationMLとthemeを検証。スキーマは同梱しません。

iOSでの実行、Windows版PowerPoint、巨大な実務資料、アニメーションの再生、ODP保存・Keynote公開codecは未提供です。ODP読取とKeynote限定試作は以下のE〜Hを参照してください。
既存master/layoutの実効外観と文字計測は計算しません。グラデーション等の直接値は2026-10-08に読取投影を追加しました。未対応情報の保全契約はREADMEの対応表が正典です。

## 再現

```sh
python3 -m pip install python-pptx==1.0.2
swift test
swift build -c release
python3 scripts/check-contract.py
python3 scripts/check-public-content.py --history
python3 scripts/verify-interop.py --libreoffice
python3 scripts/verify-clone-interop.py --libreoffice
scripts/build-docs.sh
swift run swiftslides sample proposal.pptx
```

fixtureは架空資料のみ。LibreOffice fixtureの更新は`--libreoffice --update-fixture`を明示します。

Keynoteの将来実アプリ確認は検証時点の最新版だけを対象とし、確認した版・OS・registryを記録します。旧版確認は完成の必須条件にしません。Keynoteコーデックは未提供。最新版15.4で限定wire試作を実アプリ検証しました。

## E〜Hの検証記録

2026-10-03、ODP読取専用codec、限定style索引、選択reader、FileTargetを追加。97テスト関数（92＋部分リンク5）、release build、DocC 701公開シンボル、29行の対応契約、42能力宣言・26証拠を検査。選択外の壊れたPPTX本文を解析しないこと、URLの後日の変更からreader snapshotが独立すること、需要駆動AsyncSequenceの順序・キャンセル、ODPのnamespace/version・missing refs・style cycle/継承深さ・重複ID/匿名ID衝突・DTD・反復セル/文字の展開予算を検査しました。

`styles.odp`のcontent/styles/meta/manifestはOASIS公開ODF 1.3 RNGに適合。スキーマは同梱せず、`scripts/verify-odp.py --schema-rng <document RNG> --manifest-rng <manifest RNG>`で再現します。SlideCoreとSlideODPだけの独立consumerで基本値と全スライドのreader結果を照合し、Python標準XML parserでページ数を確認し、架空資料の既知の本文・notesを照合。LibreOffice 26.2.3.2で架空PPTXから生成したODF 1.4を読み、ODF 1.3 fixtureもLibreOfficeで再保存後に独立consumerで再読しました。再保存の外観一致は未測定です。ODF 1.2はparserの受付対象ですがproducer検証は未実施で、詳細能力はunverifiedです。

FileTargetの回帰検査で部分書込後の注入ENOSPC・キャンセル、rename失敗、出力先の全bytes一致、一時file回収を確認。別に専用16MiB HFS+ imageへ実際に2MiBを書込み、free 256KiBでENOSPC、元保存先保持・一時file回収を確認しアンマウントしました。再現はmacOSの`scripts/verify-file-target-capacity.py`。停電・デバイス故障・ACL/xattr転送は検証していません。

Keynote Creator Studio 15.4（7051.0.79）/ macOS 27.0で架空2枚の資料を作成。Apple公式store lookupも15.4、release 2026-09-29を確認。`scripts/probe-keynote.py`で26 IWA partを厳密Snappy展開し、未知header/object fieldを保った再包装を開封・アプリ再保存しました。確認したTSWP.StorageArchiveのtype 2001 / text field 3だけで`Synthetic title A`→`Synthetic title B`を置換。UTF-8 byte数・UTF-16単位数が同じ条件に限定し、アプリ再保存後の再開封で2枚のタイトル・本文・notesを確認。再包装・局所変更後の非IWA partは全bytes一致、未変更IWA payloadと未知fieldを保持しました。記録・入力hash・型registryの由来は[keynote-probe.json](keynote-probe.json)。

registryの参照元はkeynote-parserのrevision `56a4d3b0d38c999f4273d084acd45415665e2030`、14.4の定義です。project metadataはMITですが、アプリ由来の全型定義を再配布せず、試作には少数のtype IDとfield番号だけを参照しました。15.4で観察した限定fieldを確認した結果で、全registryの15.4互換性の証明ではありません。アプリからの型抽出・再署名は行いません。位置・画像編集、全参照graph、異世代、暗号、Keynote公開codecは未検証・未提供です。アプリtheme素材も再配布せず、wire合成の負例・未知field保全はスクリプトの`--self-test`で再現します。

10/100/1000枚のPPTX/ODPをreleaseで各3回、全読取と索引＋1枚を交互に測定し、時間・index cost・one-slide cost・peak RSSを[性能記録](performance.md)へ掲載。Data sinkも同じ入力と操作でFoundation atomicと比較しました。FileTargetの1,000枚sinkはFoundationより遅く、速度保証には使いません。既存PPTXのCLI作例・producer fixtureとclone/importの計5文書も、python-pptx 1.0.2の独立検査とLibreOffice再保存を再検査しました。file-backed ZIP、cache eviction、StreamingWriter、巨大media、Linux CI/iOS実行は後続です。


## API整合性とID編集の検証記録

2026-10-05、Apple Swift 6.4のローカルmacOSで全110テスト関数（105＋部分リンク5）、release build、DocCの724公開シンボルとguide、32行の対応契約、42能力宣言・26証拠、公開内容とGit履歴を検査しました。ID編集・文字編集のthrow時取り消し、group内検索、欠落/空/重複IDと対象ID変更の拒否、writer検査付きtransactionのstrict既定・危険編集/不正寸法/キャンセルの拒否を確認しました。失敗時はモデルと原本snapshotを維持し、未変更bytesの一致も検査しました。

Dataのformat指定、登録順と最後のcodec採用、reader/計画エンコード/assetのasync入口、保存形式と拡張子の不一致による保存先保持、同じ形式の別codec登録に対するstalePlanを検査しました。同じCodec選択の再登録・CodecSetの値コピー・umbrellaと個別製品間の同じ選択は計画を再利用できます。

`python3 scripts/check-public-api.py`は独立SwiftPM consumerのCore/PPTX/ODP/umbrellaの4構成をコンパイル・実行。10件の非公開/読み取り専用境界の負例、sync/async保存結果の破棄10件のコンパイラ警告を確認し、明示利用と最後の正例はコンパイル成功しました。CIにも追加しましたが、今回のローカル実行でLinux/iOS/Windowsを検証したとは扱いません。

`verify-interop.py --libreoffice`と`verify-clone-interop.py --libreoffice`で、独立python-pptxによる基本モデルとnotes/chart/workbook/assets/master/ID/依存参照を照合し、通常2文書と複製・取り込み・編集3文書をLibreOfficeで再保存して確認しました。PowerPointの実アプリ検証と外観一致の測定は行っていません。今回のAPI改善の実装・判断は[SwiftSheetsとの比較](api-consistency.md)に記しました。


## 追加の読み取り値と実アプリ検証（2026-10-08）

gradient/pattern/image fill、画像crop、セル各辺と対角罫線、遷移、timing木、メディア参照、従来コメント、ODP型付きセル値・式を追加。新投影の変更・新規保存を拒否し、表の同じ行列内の文字・寸法編集では無関係な個別罫線とセル拡張を保持します。PPTX表の文書/選択slide単位のmaxTableCellsを検査します。

架空のTransitional/名前空間置換Strict fixture、外部動画・新コメントURI・省略fill・不正数値・誤relationship・欠落JSON属性を検査。`scripts/verify-advanced-reading.py`は公開CLIの`read-json`とPython標準XML parserを使い、直接値・crop・参照先・各辺・遷移・timing全木・コメント本文を独立照合します。再生と外観一致の検証ではありません。対応契約43行、詳細能力116宣言・45証拠を記録しました。

| アプリ | 操作 | 実測結果と境界 |
|---|---|---|
| LibreOffice 26.2.3.2 | advanced-reading.pptxをPPTX再保存→SwiftSlides再読→XML照合 | 2枚、gradient/pattern/image fill、crop、24罫線、遷移、timing、音声参照2件、従来コメント1件を確認。出力をlibreoffice-advanced.pptxとして回帰検査。アプリがcropや線幅を変えており、元入力との値/外観の同一性は保証しない。 |
| PowerPoint for Mac 16.113.3 | 追加fixtureを開く | 2枚を開封、修復要求を観察せず。閲覧モードのライセンス表示により再保存は未検証。全効果の再生や外観一致は未測定。 |
| Keynote Creator Studio 15.4 (7051.0.79) | 新規架空資料→PPTX書き出し→SwiftSlides再読→XML照合→Keynote再開封 | 3枚と背景gradient1件（stop・色変換・角度）、クリック進行・速度を照合。設定したプッシュ効果は出力XMLに存在せず、復元しない。Keynote再開封時はフォント欠落の警告あり。 |
| Keynote Creator Studio 15.4 | advanced-reading.pptx / python-pptx.pptx / libreoffice.pptx / 今回のLibreOffice再保存出力の取り込み | 「ファイルフォーマットが無効」で拒否。自身の書き出しPPTXは開封できた。拒否原因は未特定で、これらの入力のKeynote互換性を成功扱いしない。 |

Keynoteの今回の3枚出力SHA-256は`15dfea53b6c020b94eb15afe4ad87155fc36ecb2aa9ab66ac35b4e83ab18c2ae`。アプリthemeをfixtureとして再配布せず、一時検証出力だけで確認しました。追加の実アプリ検証はmacOS 27.0.1で実施。この段階ではネイティブ.keyの公開codec、全機能の意味解釈、旧PPT/暗号、再生・renderは未提供または後続でした。ネイティブKeynoteと復号の追加検査は次節に記録します。

```sh
python3 scripts/generate-advanced-reading-fixture.py
swift test
swift build -c release
python3 scripts/verify-advanced-reading.py
python3 scripts/check-public-api.py
```

任意のアプリ出力は`python3 scripts/verify-advanced-reading.py exported.pptx`で照合できます。LibreOffice再保存入力の生成器は標準OPC namespaceを使います。初期の合成fixtureは関係part/content typesの接頭辞でLibreOfficeが拒否したため修正しており、初期失敗を互換性の成功へ含めません。

ローカル検査: 全136テスト関数（131＋部分リンク5）、Releaseビルド、DocCの1,135公開シンボルとguide、対応表・能力台帳・公開内容127ファイルとGit履歴6 revisionを検査しました。CIへの独立XML照合を追加しましたが、今回のローカル結果をLinux/iOS/Windows実行の検証には転用しません。

## 2026-10-08: 残読取API・ネイティブKeynote・復号

架空IWAと暗号fixtureを`scripts/make-residual-fixtures.py`で独立生成し、Swiftのreader/decryptと比較した。依存はPython cryptography 49.0と標準hashlib/hmac/zlib/zipfile。Keynoteは確認済み型/fieldの文書順・非表示・位置/回転・文字・画像・notes・未知field順序/bytes。PPTXはplaceholder/theme継承の出典、scatter/bubble・多段cache、新コメント。ODPはSMIL時間木、audio URI、annotation、geometry構造を検査する。

暗号はOOXML Agile AES128/SHA1、AES192/SHA256（CFB v4）、AES256/SHA512（CFB v3）、Standard AES128/192/256 SHA1、ODF AES128/256 SHA1/SHA256 start、Keynote iwpv2を照合。誤password、整合性/宣言長/方式/KDF/上限違反、協調キャンセルを検査する。AgileはHMACを確認する。Standardに全体HMACはなく、Keynoteの末尾20bytesは未解釈なので暗号文全体の認証成功とは扱わない。

Keynote Creator Studio 15.4（7051.0.79）、macOS 27.0で、AppleScriptによって1枚の架空「Fictional encryption fixture」を新規作成し、平文保存→password設定→暗号保存した。Pythonの独立PBKDF2/AESで検証値SHA256とIWA chunkの復号を確認。独立Swift consumerから平文/暗号のreadと索引を実行した。producer由来ファイルは一時領域だけに置き、Apple theme/assetsを再配布しない。これは同版の基本文書の読取であり、全型・全機能の互換性証明ではない。

復号snapshotのPPTX通常保存は平文byteになることを検査し、ReadResultに診断を返す。Keynote/ODPの書込みは拒否する。再暗号化、描画/再生、IRMやcertificate保護は検証していない。

追加で、現行Keynote 15.4に架空3×2表（文字、42.5）とchart（12.5、24）・Dissolve transitionを作成し、公開consumerからネイティブIWAの文字/数値セルとchart値を照合した。アプリ作成の暗号文書も同じconsumerで読取した。これらは一時検証物で、Appleのtheme/assetsは再配布しない。合成fixtureではUTF16 run/style、BNC v5セル、未対応セル版のopaque保持、疎なchart grid、build/chunk、数値Bezierパスと通常図形/接続線を検査した。

PPTXではlayoutの実際のrelationship先と一意のplaceholderを使い、theme effect/phClr・transform・custom geometryの継承、直接の空effectLstによる影の解除を検査した。ODPでは内部埋込chartのlocal-table/A1 rangeと欠落ポイント、外部table rangeの未解決診断を検査した。暗号CFBの有効entry上限、原本XMLのQNameと接頭辞再束縛/default/xml mappingも確認した。全機能の意味解釈、外観一致、再生を成功扱いしない。

ローカル最終検査は全153テスト関数（148＋部分リンク5）、Releaseビルド、6製品構成の独立SwiftPM consumer、通常製品と復号製品を個別に検査したDocCの1,295公開シンボル、対応契約53行、詳細能力144宣言・63証拠。CLIと独立XML parserによる3つの追加PPTX fixtureも通過した。公開内容169ファイルとGit履歴7 revisionも検査した。Linux/iOS/Windowsの実行は今回検証していない。

## 2026-10-08: OMML数式とDrawingML図形3Dの読取

`generate-math-3d-fixture.py`で架空Transitional/名前空間置換Strict fixtureを生成。分数・根号・上添字・総和・行列の型と引数境界、段落内の前後文字、表セル・notes・実際のrelationship先layoutでの読取を検査した。対応外Choiceを飛ばし、最初の対応Choiceだけを投影し、後続Choice・Fallback・未知拡張を原本構造へ保持する。JSON round tripと旧TextRun JSONの追加属性省略も確認した。

3Dではcamera preset/FOV/zoomとcamera/light回転、light rig/direction、z・押出し・輪郭幅・材質・上下bevel・色を独立値と照合。省略値はnil、明示0を0として返す。backdrop・未知拡張も原本構造に保持する。欠落/重複した数式引数・camera/light、負の押出し/zoom、非整数寸法、非有限数値・角度/FOV範囲外を拒否した。

未変更bytes一致、位置変更・表幅変更で数式と3Dの保持を確認。数式の投影除去・文字領域削除・ノート削除・セル本文差替え・表再構成、3D投影の除去、新規保存をstrict=falseでも拒否する。未選択Choice内の数式だけを持つ文字領域も再構成を拒否する。選択readerとasync読取結果は全読取と一致した。

全159テスト関数（154＋部分リンク5）、Releaseビルド、6製品構成の独立consumer、DocC全1,391公開シンボル、対応契約55行、詳細能力160宣言・69証拠、公開内容178ファイルとGit履歴7 revisionが通過。`verify-math-3d-reading.py`で公開CLIとPython標準XML parserを使い、両fixtureの数式の分子/分母・行列セル・字句と3D直接値を独立照合し、CIにも追加した。既存のadvanced-reading 3fixtureの独立XML照合も通過した。

初回の既存テストでは、2秒のsleepに依存するbatchFailureCancelsAndJoinsChildrenが負荷下で失敗した。最終の全テスト実行では通過し、その既存テストと並行処理実装は変更していない。sandbox下のRelease dSYM生成はmacOSの実行制限で失敗したため、許可された実行環境で標準Releaseビルドを完了。DocCは既存スクリプトをSwiftPMのnested sandbox無効で実行した。

実PowerPoint等からの数式/3D producer fixture、アプリ再保存、外観・描画・計算、3D model資源、文字/chartの3D、MathML/LaTeXは今回検証していない。Linux/iOS/Windowsの実行も未検証。変更は作業ツリーに保持し、公開・tag/releaseは行わない。

```sh
python3 scripts/generate-math-3d-fixture.py
swift test
swift build -c release
python3 scripts/verify-math-3d-reading.py
python3 scripts/check-public-api.py
python3 scripts/check-contract.py
python3 scripts/build-capabilities.py --check
python3 scripts/check-public-content.py --history
scripts/build-docs.sh
```

## ODP MathMLと高度図形の読取検査（2026-10-08）

`semantic-reading.odp`は標準Pythonだけで生成するODF 1.3合成fixtureで、再生成は全byte一致。SHA-256は`0ab37c1e02d9814c4f729cb2cc583abc98c2f99347c7d323319343d41a23dae7`。16種類のenhanced path命令、viewBox・数値/modifier/guide・text area・鏡像・handleと原本拡張、内部/inline MathMLのtoken・分数/根号/添字/上下限/行列・annotation境界とframeのpreviewを検査した。ODP数式はMathMLルートを読む。office文書全体を数式と推測しない。

未知pathはnilと原本/診断、欠損modifier/guide・重複guide・不正引数数・非有限値・負viewBox・壊れた内部XML/DTD・欠損パーツは拒否する。XMLとは別にpath token/modifierの数と、再利用された数式tokenの文書全体の展開予算も検査した。選択readerは同じsnapshotの要求ページだけに予算を適用し、同じ値を返す。JSON往復とPPTXへの持込/投影変更の拒否を確認した。保存・変換機能は追加していない。

公開CLIとPython標準XML parserの独立照合は、16命令・operand・guide・数式token/引数・inline順序で一致した。OASIS公開ODF 1.3 RNGでcontent.xml/styles.xmlの2パーツを検査し、意図的な未知geometryノード1個を除いた部分が適合した。MathML内部はODF RNGが任意XMLを許すため、RNG適合を数式の意味検証に数えない。

全165テスト関数（160＋部分リンク5）、6製品構成の外部consumerと公開APIの負例、DocC全1,466公開シンボル、対応契約57行、詳細能力161宣言・71証拠を検査した。Releaseビルド、公開内容185ファイルと履歴7 revisionも通過した。追加の大きなモデルをElementへ直接保持した初回テストでstack上限超過が起きたため、Equation/EnhancedGeometryを不変の共有storageへ変更し、値比較・JSON形状・Sendableを維持した。既存batchFailureCancelsAndJoinsChildrenの2秒sleepが負荷下で先に満了する競合も再現し、時刻ではなくキャンセル通知を待つ検査へ修正した。

ODF 1.2/1.4、実アプリの開封/再保存・外観、Linux/iOSでの実行は未検証。guide/数式の評価、Content MathMLの意味解釈、3D/extrusion、独自engine/transform、描画/再生は対象外。Release dSYM生成と通常キャッシュが必要な外部consumer/DocCは、sandboxの実行制限を避けた許可環境で検査した。変更は作業ツリーに保持する。

```sh
python3 scripts/generate-odp-semantic-fixture.py
swift test
swift build -c release
python3 scripts/verify-odp-semantic-reading.py
python3 scripts/check-public-api.py
python3 scripts/check-contract.py
python3 scripts/build-capabilities.py --check
python3 scripts/check-public-content.py --history
scripts/build-docs.sh
```


## 残読取カテゴリの実装・照合（2026-10-08）

追加したのはODFの3D/押出し属性とguide/handle式評価、DrawingMLの効果tree・追加文字外観・3D継承とモデル資源参照、XLSX保存値のworkbook解決、KeynoteのTSCE式token・結合・UFF/PreUFF chart軸、file-backed ZIP readerと圧縮cache、旧PPT/Keynote2 XML/SXIの読取専用codec。保存・変換は追加していない。追加投影の編集時は既存writerで拒否し、原本保持の境界を維持する。

179テスト関数（本体174＋部分リンク5）、7製品構成の独立consumer、公開APIの可視性と保存結果の未使用拒否、Releaseビルドを確認。DocCはSlideLegacyを含む全1,673公開シンボルを掲載。対応契約63行、詳細能力196宣言・87証拠を検査した。旧形式/未解釈属性をsupportedへ引き上げず、確認済みsubsetをpartialとする。

- OASISの[ODF 1.2](https://docs.oasis-open.org/office/v1.2/os/OpenDocument-v1.2-os-schema.rng)、[1.3](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/schemas/OpenDocument-v1.3-schema.rng)、[1.4](https://docs.oasis-open.org/office/OpenDocument/v1.4/os/schemas/OpenDocument-v1.4-schema.rng)公式RNGで各content/stylesを検査。1.4では新handle-position-x/yを使用。意図的な未知geometryノード1個を除く。MathML内部の意味は独立XML/Swiftテストで別途確認する。
- Keynote 15.4の新規架空3×3表で、A2=2/B2=3/C2の式=A2+B2、アプリの値5、A1:B1結合をAppleScriptから独立取得。読取のcache・相対セル参照token・結合spanと一致した。最初にmerge ownerの単一座標range_end省略と関数168 wrapperを検出し、両方に対応した。
- LibreOffice 26.2.3.2のMS PowerPoint 97出力で、2枚の寸法960×540・順序ID256/257・日本語本文を照合。元の架空fixture以外の資料を使用していない。旧SXI export filterはエラーを返したため、SXIは合成XMLのみの検査とする。
- LibreOfficeでODF 1.2/1.4正例を開封・再保存し、内部MathML数式と16パス命令を再読した。意図的な未知/空パス、直接inline MathML、外部object参照はこの正例から除外。別試行では空パスがMのみへ変化し、直接inline数式と外部参照が空object/欠損previewへ変わった。これらをreaderで空データにせず拒否した。全数式・全原本がアプリ再保存で保持されるとは保証しない。
- file-backed ZIPは8個の各2MiB stored assetで、索引段階の取得bytesが全体の1/4未満、1個読取後も1/2未満、cache peakが64KiB以内と検査。in-place書換えとatomic置換は拒否し、Data snapshotは継続して読める。これはheap/RSSや速度のベンチマークではない。
- DrawingML effectのxfrm tx/tyは長さ、relOff tx/tyは倍率として分離。[TransformEffect](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.transformeffect?view=openxml-3.0.1)、[RelativeOffset](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.relativeoffset?view=openxml-3.0.1)の一次仕様と、2pt/−1ptおよび0.25/−0.5の独立期待値を照合した。

`verify-remaining-reading.py`は公開CLIから旧PPT/Keynote実producerの値を照合し、任意の公式RNG directoryを指定するとODF 3世代も検査する。CIへproducer検査を追加した。未知Keynote式・高度書式・全版差、旧形式のshape/notes完全投影、独自geometry engine、再計算・描画/再生、PowerPoint実アプリの数式/3D生成物、Linux/iOS実行は未検証範囲として残る。新規保存・変換・公開・tag/releaseは今回実施しない。

```sh
swift test
swift build -c release
python3 scripts/verify-remaining-reading.py
python3 scripts/check-public-api.py
python3 scripts/check-contract.py
python3 scripts/build-feature-catalog.py --check
python3 scripts/build-capabilities.py --check
python3 scripts/check-public-content.py --history
scripts/build-docs.sh
```

## 読取・データモデルの残項目の追加検査（2026-10-08）

以下は上の各時点の未対応記録を更新する最終検査。保護方式、旧PPT/旧Keynote XML/SXI、旧セルstorage、Workbook旧XLSの拡張は今回の対象外。変換・保存・再計算・描画/再生は追加していない。

- DrawingMLの17演算、調整値上書き、組込み座標、楕円弧の極角による終点を独立数値と照合。ODPの2D/3D transformの順序・角度単位、text-path属性、cube/ellipsoidの解析的な値と押出し/回転断面をモデル化した。独自engineは明示provider、未供給時はopaqueと原本・診断。
- Content MathMLのapply/bind、束縛変数、内容辞書、rationalの成分境界を検査。Workbookの名前付き範囲・scope・union/intersection・3D sheet range・共有式展開を検査。絶対参照・全行/列・日本語名・UTF16 surrogateを保持し、循環・存在しないsheet・予算超過を拒否する。
- PPTX chartの3D view/床/壁/軸と文字外観の属性継承・明示解除、ODP chartの別styles.xmlからの親書式/軸/minor interval/面塗りを照合。Flat ODPと異なるページ寸法、原本flat.xmlのbytes保持も検査した。
- glTF/GLBのscene/TRS/accessor、sparse置換・材質を独立binary値と照合。参照循環・範囲/型・JSON/展開予算・宣言長違反を拒否。skin/animation参照と標準PBR材質を型付きで提供する。必須extensionの意味、未供給外部bufferは診断し、全JSONを保持する。
- Keynoteの入れ子式・UID参照・schema未知fieldと原wireの往復、editable Bezier/parameterized path、IWA header参照inventoryを検査。セルのstyle/format/error参照、軸の複合値、buildの追加属性を構造化した。任意の本文整数を参照だと推測せず、未解釈scopeをinventoryに残す。
- ODPページXML範囲とKeynote IWA object位置の遅延索引、2件同時の選択読取順序、圧縮/展開索引の合計2KiB cache上限、UTF16索引、file-backed directoryの変更・symlink拒否を検査。ZIP中央directoryをまとめて読む実装で、1byteごとのfile状態確認による過剰なI/Oを除いた。操作の前後の原本変更検査は維持する。

macOS 27.0.1・Apple M2・Swift 6.4と、iOS 27.0 Simulatorの双方で**194テスト関数（本体189＋部分リンク5）**が通過。7製品構成の独立SwiftPM consumerに新しいguide・Workbook・glTF・並列/cache APIの利用も追加し、公開APIの負例検査が通過。DocCは**2,037公開シンボル**、対応契約72行、詳細能力196宣言・93証拠と機能台帳が整合した。Releaseビルド、公開内容229ファイルとGit履歴7 revisionの検査も通過した。既存のPPTX高度属性・数式/3D・ODP図形/数式・Keynote実producer式cache/結合の独立照合も通過した。

### 時間とピークRSSの測定

`scripts/benchmark-readers.py`による架空文書。各ページに文字図形10個、画像なし。別条件として未要求の64MiB stored assetを追加する。Release、warm filesystem、各sampleは新規process、各3回を操作交互順で測定。表は時間とプロセス最大RSSのそれぞれの中央値。`file-backed 1枚`は合計8MiBのcache予算で、索引作成から中央の1枚の返却までを含む。CPU/OSは上記macOS環境。

| 形式・条件 | 全読取 ms / MiB | snapshot索引＋1枚 ms / MiB | file-backed索引＋1枚 ms / MiB |
|---|---:|---:|---:|
| PPTX 10枚 | 32.9 / 13.2 | 6.7 / 9.8 | 6.4 / 9.9 |
| ODP 10枚 | 24.2 / 11.5 | 5.8 / 10.1 | 5.9 / 10.1 |
| PPTX 100枚 | 249.7 / 32.0 | 17.3 / 10.7 | 19.2 / 10.9 |
| ODP 100枚 | 222.5 / 22.4 | 20.6 / 10.9 | 20.2 / 10.9 |
| PPTX 1,000枚 | 2,437.6 / 217.7 | 123.7 / 15.8 | 154.5 / 17.7 |
| ODP 1,000枚 | 2,139.5 / 130.3 | 158.6 / 17.8 | 155.5 / 17.9 |
| PPTX 10枚＋未要求64MiB | 33.0 / 13.3 | 6.6 / 9.9 | 7.1 / 10.2 |
| ODP 10枚＋未要求64MiB | 24.5 / 11.6 | 6.0 / 10.3 | 6.2 / 10.4 |

これはこの合成条件の比較であり、任意の実資料の速度・RSS保証ではない。Dataのmmapで未要求ページがresidentにならない場合もある。cache上限は保持Dataに適用し、返却モデルや一時解析領域・全RSSを含まない。巨大な単一XML/IWA partは索引作成時に一度展開する。Keynoteの時間/RSSはこの表で測定していない。

### 検証範囲の境界

Linux/Windowsでの実行、PowerPoint実アプリの数式・3D生成/再保存は未検証。ローカルのPowerPointは閲覧専用ライセンス、Linux/Windowsの実行環境はない。既存の実アプリ保存で失われる要素や未知Keynote field/版、独自engine、glTF extensionを完全互換と表記しない。新規APIは確認済み構造を読むものであり、未知の全形式・全参照graphを解釈済みとは扱わない。
