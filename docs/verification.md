# 検証手順と境界

開発時の検証記録。全PowerPoint機能・全アプリ版への互換性保証ではありません。

## 自動検査

- `swift test`:46テスト関数（パラメータ化を含め53ケース）。公開入口、部分リンク、独立したpython-pptxの期待値、Strict/ZIP64/PPTM、破損・危険編集・並行読み取り、保存保全を検査。
- `swift build -c release`:最適化したライブラリとCLIをコンパイル。
- `python3 scripts/check-contract.py`:対応表・作例・テスト名の整合と5負例。
- `python3 scripts/check-public-content.py --history`:公開内容と全Git履歴の監査。11負例。
- `scripts/build-docs.sh`:392公開シンボルをDocCへ展開。4負例、ガイド、公開アーティファクトの個人パス除去を検査。
- `python3 scripts/verify-interop.py`:python-pptx 1.0.2による作例のフォント・図形・線・表・ノート・寸法検証。
- `python3 scripts/verify-interop.py --libreoffice`:上記に加え、LibreOfficeで2種類の文書を再保存し、独立系とSwiftSlidesで再読。指定した場合、LibreOffice不在を成功扱いしない。

CIはmacOSとLinuxで同じテストを実行します。APIリファレンスはmacOSのDocCで生成します。

## 実アプリ

2026-10-03、PowerPoint for Mac 16.113.3でCLIの2枚の作例を開き、日本語・図形・線・表・ノートを確認しました。修復要求なし。
初期実装で出た修復要求はノートmasterのoptional ID listを生成しない構造へ変更して解消。新規ノートmasterを共有し、本文プレースホルダーも整備しています。
この環境のPowerPointは閲覧モードのため、PowerPoint自身の再保存は未検証です。

LibreOffice 26.2.3.2では作例の読み取り、再保存、PDF化を検査。2枚を画像で確認しました。
公開仕様由来のOOXML XSDを一時的に使い、新規作例のPresentationMLとthemeを検証。スキーマは同梱しません。

iOSでの実行、Windows版PowerPoint、巨大な実務資料、アニメーションの再生、ODP/Keynoteの読み書きは未検証です。
既存master/layoutの実効外観、文字計測、グラデーション等はモデル化しません。未対応情報の保全契約はREADMEの対応表が正典です。

## 再現

```sh
python3 -m pip install python-pptx==1.0.2
swift test
swift build -c release
python3 scripts/check-contract.py
python3 scripts/check-public-content.py --history
python3 scripts/verify-interop.py --libreoffice
scripts/build-docs.sh
swift run swiftslides sample proposal.pptx
```

fixtureは架空資料のみ。LibreOffice fixtureの更新は`--libreoffice --update-fixture`を明示します。
