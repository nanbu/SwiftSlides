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
| 書出し結果 | WriteResult。警告を明示的に受け取る | WriteResult。write / save / transactionは破棄時にコンパイラが警告 |
| 原本保持 | 内部storageと公開PreservationSummaryを分離 | 同じ分離。PackageGraphで原本の参照を別途検査 |
| 部分読取 | StreamingReaderは行単位 | SlideReaderはスライド単位。部分Presentationを作らない |
| APIの検証 | 独立consumer、アクセス拒否・結果破棄の負例 | check-public-api.pyをmacOS/LinuxのCIへ追加 |

同じ操作には同じラベルを使う。Dataは`format:`、書出しは`as:`、URLは`contentsOf:` / `to:`、対象は`id:`、挿入位置は0起点の`at:`。クロージャーは末尾に置く。読み取った位置とモデルのIDは区別する。機械判定はerrorのcaseやwarningのcodeを使い、説明文の一致に依存しない。

## 取り入れた学び

SwiftSheetsのeditSheetは、値を取り出して編集したあと書き戻し忘れる問題を、クロージャーで解消している。SwiftSlidesでも対象を仮の値へコピーし、正常終了時だけ反映する。検索はIDを使い、欠落や重複を黙った成功にしない。コピーは取り消しのために必要で、変更がコピーなしになるとは主張しない。

文書全体の`transaction`はwriterで保存可否も検査する。危険なopaque変更や不正寸法を反映する前に拒否する。strictの既定はtrueとし、警告を許容する場合も戻り値へ残す。既存writeの既定strict=falseは維持する。transactionはエンコードを伴うため、UIでは同期処理の時間がかかり得る。重い処理はSendableの文書コピーを所有するTask内で行い、確定した値を呼出元へ戻す。

保存結果は警告も含むAPIである。`@discardableResult`をwrite/saveから外し、意図的な破棄は`_ =`で示す。IDを返すadd/duplicateや、任意の戻り値を返すモデル編集にはdiscardableを維持する。data便利APIは互換のため残すが、警告を確認する用途はencoded/writeを使う。

内部テストだけでは、package限定の実装が外部から見えないことを証明できない。独立SwiftPM consumerでCore、PPTX、ODP、umbrellaの4構成をコンパイル・実行する。内部storage/ZIP/XMLと原本XMLのsetterは個別の負例で拒否を確認する。sync/asyncの保存結果を無視した呼出しはwarnings-as-errorsで失敗し、明示的に受け取れば成功する。負例のあとに正例を再コンパイルし、環境全体の破損を成功と誤認しない。

保存計画は原本・モデル・optionsに加えて作成時のCodec選択へ結び付ける。同じ形式の別実装を再登録した集合ではstalePlanを返す。同じCodec値から作った集合では再利用できる。実装の型名だけで設定の同一性を推測しない。

## 形式の違いとして維持する点

SwiftSheetsはURL拡張子から出力形式を選ぶ。SwiftSlidesは明示指定→元形式→PPTXの順で選び、認識できる拡張子との不一致を拒否する。PPTMや未解釈パーツを保持している文書で、名前変更を形式変換にしないためである。

SwiftSheetsのSheet名は参照にも使う。Slideは同名を許し、編集はIDで指定する。順序変更や名前変更で対象を取り違えない。名前の重複回避や数式の書換えをSlideへ移植しない。

メモリへの出力は既存のencoded/dataを維持する。公開PresentationCodecも既存の拡張点として維持し、第三者codecの選択reader等は能力別protocolで追加する。SwiftSheetsの移行時のAPI削除をそのまま適用しない。

Tableはプレゼンテーションの図形であり、Spreadsheetの式・日付基準・計算結果を直接持ち込まない。データ交換は将来のSlideSheetsBridgeへ分離する。NumbersのIWA実装から学べる低層処理も、Keynoteの型registryと参照を検証するまで公開codecにしない。

## 残る設計と互換性の注意

型付きID/Collection、ElementContent、文字範囲編集、真のfile-backed readerとメモリ予算付きcache、ODP保存、Keynote公開codecは将来設計のまま。公開varの名称や型を一括置換して見かけを揃えない。対応能力・機能台帳に未検証を残し、実装の追加と実アプリ互換性の証明を分ける。

既存の引数ラベルでの呼出しは維持する。Data入口の形式引数追加は関数値の型に影響し、async overloadを追加した操作はasync文脈でawaitが必要になることがある。保存結果の無視は新たなコンパイラ警告になる。認識できる拡張子との不一致は、従来保存できた呼出しでもthrowする。SwiftSlidesは未リリースでAPI互換性は未保証だが、変更する契約と影響を明示する。

API変更の検査は`swift test`、`python3 scripts/check-public-api.py`、`scripts/build-docs.sh`。公開前のrelease build・契約台帳・公開内容/履歴の検査も実行する。実行していないOSや実アプリの互換性を、コンパイル結果やテスト数から補完しない。
