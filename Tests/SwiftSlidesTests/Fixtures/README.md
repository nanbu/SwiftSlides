# 架空のテスト資料

`python-pptx.pptx`と`producer-oracle.json`はMITのpython-pptx 1.0.2で生成・再読して期待値を採ります。
全内容は架空。作者情報はFixture Author/Fixture Generator。生成は`scripts/generate-fixtures.py`。

stored、zip64、strict、relocatedはコンテナ/名前空間/パーツ名の変種。unknownは架空の拡張XML。
macro.pptmのVBAパーツは実行できない架空bytesで、マクロの実行検証ではありません。
fixture.pngは1ピクセルPNG。impress.odpはmimetype検出だけの最小ZIP。
LibreOffice由来fixtureは`scripts/verify-interop.py`でpython-pptx文書を再保存して生成します。
実際のユーザー資料、環境パス、購入テンプレートを含みません。python-pptxのMITな既定パッケージから生成しており、帰属と許諾はLICENSE-python-pptx.txtに記載しています。


- `styles.odp`: `scripts/generate-odp-fixture.py`が決定的に生成する架空ODF 1.3。named/automatic/default/master、文字・空白・tab・link、group・image・table・notes。`odp-oracle.json`が独立期待値。ODF 1.3のdocument/manifest RNGに適合確認。
- `libreoffice.odp`: 2026-10-03、LibreOffice 26.2.3.2で架空`python-pptx.pptx`から生成したODF 1.4。実資料・個人パスを含まない。custom geometry/chartは意味モデルへ変換せず診断・原本保持。
- `impress.odp`: 従来のmimetype検出用marker fixture。完全なODPではなく、必須part不足の負例。

Keynote実アプリ試作は一時領域だけで行い、アプリthemeの画像をfixtureとして再配布しない。合成wireデータの検査は`python3 scripts/probe-keynote.py --self-test`で再現する。

- `reading-models.pptx` / `reading-models-strict.pptx`: `scripts/generate-reading-fixture.py`で決定的に生成する架空の投影fixture。単位付き間隔、field、色変換、layout/masterの表・画像、自由曲線、影、疎なchart cache、diagramの保存済みdrawing。Strict版は名前空間置換で、Strict producerやピクセル互換性の証拠ではない。


- `advanced-reading.pptx` / `advanced-reading-strict.pptx`: `scripts/generate-advanced-reading-fixture.py`で決定的に生成。gradient/pattern/image fill・crop・個別罫線・push/timing・架空の無音WAV・従来コメント。Strict版は名前空間置換で、Strict producer検証ではない。基底素材の許諾は上記python-pptxと同じ。
- `libreoffice-advanced.pptx`: 2026-10-08、LibreOffice 26.2.3.2がadvanced-reading.pptxをPPTX再保存した架空資料。作者名はFictional Reviewer/Fixture Author。SHA-256は`df1deff17ca8992893e702c4a330207fb55e8edb7cc8ef39b88bd130952457a0`。crop・線幅等はアプリ出力の値を検証し、元入力との外観一致とは区別する。
