# 形式を増やすための設計

共通モデルのPresentation、Slide、Elementは形式中立の値型。寸法はポイント、描画順とグループのローカル座標を保持する。
コーデックはPresentationCodec(Sendable)を実装し、Codecで型消去してCodecSetへ登録する。
ファイル検出と登録済み実装の有無を分け、対応していない形式はnoCodecを返す。

| 形式 | 実装 | 対応状態 | 将来の保存で注意するもの |
|---|---|---|---|
| PowerPoint PPTX/PPTM | SlidePPTX | 読み書き | OPC relationship、master/layout、テーマ、未対応XML、マクロ |
| LibreOffice Impress ODP | 将来SlideODP | mimetype検出のみ | ODF 1.4 ZIP、styles.xml、ページスタイル、単位、manifest、未対応要素 |
| Apple Keynote | 将来SlideKeynote | enum/設計のみ | IWA/Snappy/Protobuf、オブジェクト参照、バージョン差、フォントとビルド |

新形式でも警告・検査・読み取り・保存の戻り値をそろえる。保存時の情報落ちを黙認しない。
変換機能は各形式の読み書きと損失の検証が揃うまで公開しない。
レイアウト継承やテーマ解決は別層として追加する。レンダラーはコーデックと分離する。
