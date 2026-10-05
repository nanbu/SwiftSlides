# コントリビュート

仕様を先に変更し、対応する失敗テストを追加する。未対応内容は原本を保持して警告、安全に保存できない変更はthrow。
`swift test`、`swift build -c release`、`python3 scripts/check-contract.py`、`python3 scripts/check-public-content.py --history`を実行する。
独立した互換性検証は`scripts/verify-interop.py`。外部ツールが必要な検証は不足時に成功扱いしない。
API資料は`scripts/build-docs.sh`で生成する。Conventional Commits、公開資料へ個人パス・実データを含めない。
公開APIを変更したら`python3 scripts/check-public-api.py`を実行する。独立したSwiftPM consumerでCore/個別形式/umbrellaをコンパイル・実行し、原本保持内部の不可視性と保存結果の明示的利用を負例でも検査する。CIはmacOS/Linuxで実行する。外部からの見え方を同じpackage内のテストだけで判断しない。

将来機能台帳は`docs/feature-catalog.json`を編集し、`python3 scripts/build-feature-catalog.py`で生成する。`python3 scripts/build-feature-catalog.py --check`で整合を検査する（CIでも実行）。計画中の機能を現行の対応表示へ移すのは、実装と回帰検査が揃ってから行う。

機能別の現行能力は`docs/capabilities.json`が正典。`python3 scripts/build-capabilities.py`で宣言を生成し、`--check`で機能ID・fixture hash・テスト・操作/プロファイル別の証拠を検査する（CIでも実行）。fixtureを変更したら証拠の限定範囲を再確認する。未検証を別プロファイルや操作の成功から補完しない。
