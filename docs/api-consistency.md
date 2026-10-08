# APIの共通規約とSwiftSheetsからの学び

現行契約の正典は[実装仕様](implementation-spec.md)。SwiftSheetsの[CodecSet](https://github.com/nanbu/SwiftSheets/blob/d153773/Sources/SheetCore/Codec/CodecSet.swift)、[Workbookの編集](https://github.com/nanbu/SwiftSheets/blob/d153773/Sources/SheetCore/Model/Workbook.swift)、[API規約](https://github.com/nanbu/SwiftSheets/blob/d153773/docs/api-stability.md)を比較し、共通の使い方とプレゼンテーション固有の境界を整理した。

## 両ライブラリの入口

| 観点 | SwiftSheets | SwiftSlidesの現行方針 |
|---|---|---|
| モデル | Workbook / Sheet / Table | Presentation / Slide / Element。SlideCoreに置く |
| 形式の選択 | Codec値、CodecSet、umbrellaのall | 同じ構成。formats / contains / codec(for:)も同じ登録規則 |
| Data読取 | init(data:format:options:) / read / inspect | 同じ形式指定。URLは内容で判定 |
| 形式を限定した利用 | CodecSetからread / write / reader | 同じ入口でread / write / slideReader / 保存計画を利用 |
| 値型の複数編集 | editSheet(named:_:)。throwで取り消す | editSlide(id:_:) / editElement(id:_:) / editText(_:)。throwで取り消す |
| 書出し結果 | WriteResult。警告を明示的に受け取る | WriteResult。write / transactionは破棄時にコンパイラが警告 |
| 原本保持 | 内部storageと公開PreservationSummaryを分離 | 同じ分離。PackageGraphで原本の参照を別途検査 |
| 部分読取 | StreamingReaderは行単位 | SlideReaderはスライド単位。部分Presentationを作らない |
| APIの検証 | 独立consumer、アクセス拒否・結果破棄の負例 | check-public-api.pyをmacOS/LinuxのCIへ追加 |

同じ操作には同じラベルを使う。Dataは`format:`、書出しは`as:`、URLは`contentsOf:` / `to:`、対象は`id:`、挿入位置は0起点の`at:`。クロージャーは末尾に置く。読み取った位置とモデルのIDは区別する。機械判定はerrorのcaseやwarningのcodeを使い、説明文の一致に依存しない。

## 取り入れた学び

SwiftSheetsのeditSheetは、値を取り出して編集したあと書き戻し忘れる問題を、クロージャーで解消している。SwiftSlidesでも対象を仮の値へコピーし、正常終了時だけ反映する。検索はIDを使い、欠落や重複を黙った成功にしない。コピーは取り消しのために必要で、変更がコピーなしになるとは主張しない。

文書全体の`transaction`はwriterで保存可否も検査する。危険なopaque変更や不正寸法を反映する前に拒否する。strictの既定はtrueとし、警告を許容する場合も戻り値へ残す。既存writeの既定strict=falseは維持する。transactionはエンコードを伴うため、UIでは同期処理の時間がかかり得る。重い処理はSendableの文書コピーを所有するTask内で行い、確定した値を呼出元へ戻す。

保存結果は警告も含むAPIである。`@discardableResult`をwriteから外し、意図的な破棄は`_ =`で示す。IDを返すadd/duplicateや、任意の戻り値を返すモデル編集にはdiscardableを維持する。保存はwriteのみとし、警告を結果から確認する。

内部テストだけでは、package限定の実装が外部から見えないことを証明できない。独立SwiftPM consumerでCore、PPTX、ODP、Keynote、Legacy、Decrypt、umbrellaの7構成をコンパイル・実行する。内部storage/ZIP/XMLと原本XMLのsetterは個別の負例で拒否を確認する。sync/asyncの保存結果を無視した呼出しはwarnings-as-errorsで失敗し、明示的に受け取れば成功する。負例のあとに正例を再コンパイルし、環境全体の破損を成功と誤認しない。

保存計画は原本・モデル・optionsに加えて作成時のCodec選択へ結び付ける。同じ形式の別実装を再登録した集合ではstalePlanを返す。同じCodec値から作った集合では再利用できる。実装の型名だけで設定の同一性を推測しない。

## 形式の違いとして維持する点

SwiftSheetsはURL拡張子から出力形式を選ぶ。SwiftSlidesは明示指定→元形式→PPTXの順で選び、認識できる拡張子との不一致を拒否する。PPTMや未解釈パーツを保持している文書で、名前変更を形式変換にしないためである。

SwiftSheetsのSheet名は参照にも使う。Slideは同名を許し、編集はIDで指定する。順序変更や名前変更で対象を取り違えない。名前の重複回避や数式の書換えをSlideへ移植しない。

メモリへの出力はSwiftSheetsと同じ`write(as:options:)`を正規入口とし、計画済み出力も`write(using:)`へ揃える。0.1.0では旧別名を削除し、writeへ一本化する。組込codecの具体型はpackage限定とし、第三者用PresentationCodecと能力別protocolを公開拡張点として維持する。

Tableはプレゼンテーションの図形であり、Spreadsheetの式・日付基準・計算結果を直接持ち込まない。データ交換は将来のSlideSheetsBridgeへ分離する。NumbersのIWA実装から学べる低層処理も、Keynoteの型registryと参照を検証するまで公開codecにしない。

## 残る設計と互換性の注意

型付きID/Collection、ElementContent、文字範囲編集、ODP/Keynote保存は将来設計のまま。Keynoteと旧形式の確認済みsubset読取、file-backed readerと圧縮bytes予算付きcacheは公開APIを提供する。公開varの名称や型を一括置換して見かけを揃えない。対応能力・機能台帳に未検証を残し、実装の追加と実アプリ互換性の証明を分ける。

[移行表](api-migration.md)に記したBoolのラベル・プロパティ名と組込codec型は変更する。形式引数の追加は関数値の型に影響し、async overloadを追加した操作はasync文脈でawaitが必要になることがある。保存結果の無視はコンパイラ警告になる。認識できる拡張子との不一致はthrowする。SwiftSlidesは未リリースでAPI互換性は未保証だが、変更する契約と影響を明示する。

## 全体レビューで揃えた契約

比較の基準はSwiftSheetsのB.46–B.68（公開範囲・命名）、B.89（最終統一）、B.92–B.94（呼出し時の拒否・メモリ測定）。モデル・読取/書込・形式選択・能力照会・診断・原本・部分読取・並行処理・編集・レイアウト・表示値と形式固有投影を確認した。

- `Presentation.write`と`CodecSet.write`はメモリ・URL・保存計画で同じ名前を使い、`WriteResult`を返す。
- URLでも`format:`を指定できる。password付き、同期/非同期、全体/部分の各入口へ同じ指定を渡す。省略時は内容で検出する。
- `ReadOptions`は全設定をinitializerで渡せる。合計cache予算はumbrellaとCodecSetの同期/非同期file readerから指定できる。
- 組込codecは非公開。ODPの書式索引は`ODPStyleIndex`のinitializerで開く。外部consumerで具体型へアクセスできないことも検証する。
- キャッシュはLRU順を全件走査せず更新し、空Dataは保持しない。XML索引は入力bytesを借用し、子孫検索は反復走査で中間配列を抑える。保存計画は出力のZIP索引を再利用する。
- 空選択のキャンセル、descriptorの件数/index/IDの整合、均等配置の有限座標・非負寸法を検証する。

粒度はPresentation→Slide→Element→TextBody/Paragraph/TextRun、Table→行配列→TableCellとする。Sheetのセル座標・計算APIをSlideへ追加しない。チャートworkbookは保存済み値を読むための投影であり、SwiftSheetsの編集・数式計算の代替ではない。不変の高度投影が内部ストレージを共有する構成は、巨大な値を各Elementへインライン展開しないため維持する。未知語彙は元の名前と診断で保持する。

性能値は負荷と測定環境に依存する。`scripts/benchmark-reading-cache.py`は変更前ソースを指定して同一マシン・交互実行・新規プロセスで時間とpeak RSSを対に測る。小規模cacheの管理コストと大規模cacheの探索コストを分け、文書全体の高速化率として流用しない。

API変更の検査は`swift test`、`python3 scripts/check-public-api.py`、`scripts/build-docs.sh`。公開前のrelease build・契約台帳・公開内容/履歴の検査も実行する。実行していないOSや実アプリの互換性を、コンパイル結果やテスト数から補完しない。
