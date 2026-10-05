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
