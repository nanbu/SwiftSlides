# コントリビュート

仕様を先に変更し、対応する失敗テストを追加する。未対応内容は原本を保持して警告、安全に保存できない変更はthrow。
`swift test`、`swift build -c release`、`python3 scripts/check-contract.py`、`python3 scripts/check-public-content.py --history`を実行する。
独立した互換性検証は`scripts/verify-interop.py`。外部ツールが必要な検証は不足時に成功扱いしない。
API資料は`scripts/build-docs.sh`で生成する。Conventional Commits、公開資料へ個人パス・実データを含めない。
