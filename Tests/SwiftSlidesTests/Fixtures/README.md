# 架空のテスト資料

`python-pptx.pptx`と`producer-oracle.json`はMITのpython-pptx 1.0.2で生成・再読して期待値を採ります。
全内容は架空。作者情報はFixture Author/Fixture Generator。生成は`scripts/generate-fixtures.py`。

stored、zip64、strict、relocatedはコンテナ/名前空間/パーツ名の変種。unknownは架空の拡張XML。
macro.pptmのVBAパーツは実行できない架空bytesで、マクロの実行検証ではありません。
fixture.pngは1ピクセルPNG。impress.odpはmimetype検出だけの最小ZIP。
LibreOffice由来fixtureは`scripts/verify-interop.py`でpython-pptx文書を再保存して生成します。
実際のユーザー資料、環境パス、購入テンプレートを含みません。python-pptxのMITな既定パッケージから生成しており、帰属と許諾はLICENSE-python-pptx.txtに記載しています。
