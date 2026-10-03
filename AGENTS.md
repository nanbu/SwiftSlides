# SwiftSlides

- 共通規約は `~/.claude/CLAUDE.md`。
- APIと読み書き契約は `docs/implementation-spec.md`。仕様を先に更新する。
- 共通モデルはSlideCore、PowerPoint固有の処理はSlidePPTX。
- 読めない内容を空データに変えない。未対応要素は保持して警告する。危険な編集は保存を拒否する。
- `swift test`、`swift build -c release`、`scripts/check-contract.py`、`scripts/check-public-content.py --history` が公開前の検査。
- 公開資料とGit履歴に個人パス・非公開資料を混ぜない。架空fixtureだけを使う。
- 測定していない互換性・高速性を保証しない。性能は時間とメモリを併記する。
- Conventional Commits。公開・タグ作成は依頼された範囲で行う。
