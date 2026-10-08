# Changelog

SemVerに従う。1.0未満ではAPI変更をminorで示し、互換性を保証しない。バージョン定数・README・この台帳を同時に更新する。

## [0.1.0] — 2026-10-09

- 初回バージョン。PPTX/PPTMの原本保持・限定編集、ODP/Keynote/旧形式の読取と独立復号製品。
- 保存APIをwriteへ一本化。InspectOptions、明示format、引数ラベル、不変WriteResultをSwiftSheetsと整合。
- 同期・非同期の入口、原本診断、任意の保存計画、部分読取、予算付きキャッシュ。
- PowerPointの全機能・全実アプリ互換性を保証しない。保存計画は事前エンコードとパーツ差分確認を伴う任意機能。
