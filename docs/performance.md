# 性能の測定

2026-10-03のローカルrelease測定。高速性の比較保証ではありません。
macOS 27.0 arm64 / Apple Swift 6.4、各操作を別プロセスで5回実行して中央値を採りました。
100枚×10図形、各図形にテキスト・塗り・線を持つ架空資料。画像なし。PPTXは126,324 bytes。

| 操作 | 中央値 ms | プロセス最大RSS MiB |
|---|---:|---:|
| create | 249.70 | 14.67 |
| read | 221.03 | 13.42 |
| noop | 220.99 | 13.38 |
| edit | 451.63 | 17.44 |

createはモデル構築＋エンコード＋ファイル保存。readはファイル読込＋モデル化＋テキスト抽出。
noopはread＋未変更エンコード＋原本bytesとの比較。editはread＋1図形の移動＋strictエンコード＋再読検証。
時間はSwift処理区間のwall time。RSSはOSのtimeコマンドが測るプロセス全体の最大常駐量で、モデル単独の割当量ではありません。
全操作は同じ資料で測っていますが、処理内容は異なります。キャッシュを強制消去せず、他ライブラリや他マシンとの比較もしていません。

再現スクリプトは`scripts/benchmark.py`。一時的なSwift consumerをreleaseビルドして時間・RSS・全サンプルをJSONで出力します。
macOS/Linux用。Swiftとシステムzlib、OSの`/usr/bin/time`を使います。

```sh
python3 scripts/benchmark.py > benchmark.json
```

画像・動画の多い資料、複雑なXML、入力上限付近での速度とメモリは別途測定が必要です。
