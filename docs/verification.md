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
既存master/layoutの実効外観、文字計測、グラデーション等はモデル化しません。未対応情報の保全契約はREADMEの対応表が正典です。

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
