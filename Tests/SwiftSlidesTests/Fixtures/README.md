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

- `native-synthetic.keynote.zip`: `scripts/make-residual-fixtures.py`が独立生成する架空IWA。2枚（非表示1枚）・文字・画像・notes・未知type/field。Appleのprotoやthemeは再配布しない。内容判定でKeynoteとして読み、秘密鍵との拡張子衝突を避けてZIP名にする。
- `encrypted-native.keynote.zip`: 上記の合成IWAをPython cryptographyでiwpv2 v2/f1・PBKDF2SHA1/AES128CBCに暗号化。末尾20bytesの意味・認証は検証対象外。
- `encrypted-agile-{128,192,256}.pptx`: 架空stored.pptxをPython cryptography/hashlib/hmacでAgileに暗号化。CFB v3/v4、mini stream、AES128/192/256、SHA1/256/512、4096byteセグメント、HMACを照合する。
- `encrypted-standard-{128,192,256}.pptx`: 同じ架空PPTXをStandard AES-ECB/SHA1固定50,000回KDFで独立暗号化。Standardの全体HMACはない。
- `encrypted-aes-{128,256}.odp`: 架空styles.odpのcontent.xmlをraw DEFLATE・PBKDF2・AES-CBC・SHA1/1K checksumで独立暗号化。start hashはSHA1/SHA256。暗号fixtureの共通passwordは公開の架空文字列`fictional-鍵`。

- `native-advanced.keynote.zip`: 独立生成の架空UTF16文字run・段落/文字/shape style・2×2 BNC v5表・疎なchart grid・transition/build/chunk。期待値はResidualReadingTestsで固定し、描画/再生・式・merge・軸・Apple素材は含まない。

- `native-unsupported-cell.keynote.zip`: v5の架空表に未対応v6セルを入れた負例。表を空へ変えずopaque・警告と原本wireに保持し、同じslideのchart読取を続ける。
- `native-paths.keynote.zip` / `native-invalid-path.keynote.zip` / `native-unknown-path.keynote.zip`: 独立生成の通常図形・接続線とTSP.Pathの5命令。自然座標領域・flipを比較し、点数不正を拒否、未知命令を原本wireへ保持する。

`math-3d.pptx` / `math-3d-strict.pptx`は`scripts/generate-math-3d-fixture.py`で作る架空OMML・DrawingML 3D資料。上記python-pptx fixtureのOPCを土台に、分数/根号/上添字/総和/行列、未選択Choice/Fallback、未知拡張、直接camera/light・押出し/bevel/色を合成する。名前空間置換Strictを含め、構造と安全な保存境界の検査用。実アプリ由来の数式/3D fixtureや見た目の互換性証拠ではない。

`semantic-reading.odp`は`scripts/generate-odp-semantic-fixture.py`が標準ライブラリだけで生成するODF 1.3の架空資料。16命令のenhanced path、modifier/guide、viewBox/text area/handle、未知geometryノードと命令、空path、MathMLの内部object/inline・annotation・preview画像・外部objectを含む。原本保持と構造読取の証拠で、実アプリ由来ではない。`verify-odp-semantic-reading.py`は公開CLIと独立XML parserで照合し、任意のODF 1.3 RNG検査では意図的な未知geometryノード1個だけを除外する。ODF RNGはmath内部を任意XMLとして許すため、数式の引数数・token・annotation境界はSwiftテストと独立照合で別検査する。


残読取fixture（2026-10-08）: `remaining-native.keynote.zip`/`remaining-preuff.keynote.zip`は標準Pythonのwire生成による式・結合・UFF/PreUFF chart軸の架空資料。`legacy-xml.key.zip`/`legacy-gzip.key.zip`/`legacy-impress.sxi`も架空XMLで、`scripts/generate-remaining-reading-fixtures.py`から再生成する。`libreoffice-legacy.ppt`は既存の架空python-pptx文書をLibreOfficeのMS PowerPoint 97 filterで出力したもの。旧PPTの寸法960×540、文書順ID256/257と本文を検査する。

`keynote-formula-15.4.key.zip`はKeynote 15.4（macOS）で新規作成した架空の3×3表。A1:B1結合、A2=2、B2=3、C2を=A2+B2とし、アプリから式文字列と値5を独立取得した。readerの保存済み値5・セル参照token・結合spanと比較する。個人パス・author名を含まないことを展開IWAと通常パーツでも確認した。全Keynote版・全書式・式再計算の証拠ではない。

`completion-flat.fodp`は手書きの架空Flat ODP 1.3。100×80ptと200×150ptの2ページで、本文はFictional。異なるページ寸法・Flat XML原本保持・読取専用境界を検査する。追加のContent MathML/ODP chart/Keynote wire/glTF数値はReadingCompletionTests内で架空入力として組み立て、実アプリ由来とは扱わない。
