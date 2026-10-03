# 読み取りと保存の契約

## Overview

`Presentation(contentsOf:)`/`data:`は共通モデルと`readWarnings`を返します。
`Presentation.read`は`ReadResult`、`inspect`は本文を読まずに寸法・枚数・metadata・partsを返します。
画像は`asset(at:)`で必要時に展開してCRCを検査します。外部参照は取得しません。

モデルの寸法はポイント、角度は度。グループ内はローカル座標です。
Font/Color/Strokeは直接指定または生のテーマ参照。sourceThemesには原本テーマ定義を投影します。
レイアウト・マスターの継承と色変換の実効値は計算しません。

`encoded`/`write`は保存bytesと警告、`data`はbytesだけを返します。
未変更保存は原本bytes。編集保存は変更XMLを再直列化し、未変更パーツの圧縮済payloadを転写します。
文字段落や表の再構成は未対応書式を落とす場合があるため警告し、strictは警告のある変更を拒否します。
PPTMの形式変更、既存テーマ・layout変更、opaque要素編集、署名付き文書の編集は拒否します。

ZIPとXMLの上限は解析量の上限で、プロセスメモリ予算ではありません。
inspectと未変更パーツ転写は全CRC検証ではありません。展開するパーツでCRCを検査します。
コーデックは同期的。呼び出し側が実行タスクを選びます。
