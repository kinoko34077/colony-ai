# Base Project Meta

このディレクトリは、**KiNoTch. Repository Base / Runtime 構想そのものの背景・到達目標・判断基準**を保持する。

通常の個別機能開発では毎回読む必要はない。以下の場合に参照する。

- Repository Baseそのものを変更するとき
- KiNoTch. Runtimeへ共通機能を追加・変更するとき
- 個別repoの処理をBase / Runtimeへ昇格させるか判断するとき
- Baseの構造や共通境界の理由を確認するとき
- 既存repoをBase準拠へ移行するとき

## 読み順

1. [00_CONTEXT.md](00_CONTEXT.md) — なぜこの基盤を作るのか
2. [01_TARGET_STATE.md](01_TARGET_STATE.md) — 何をどういう状態まで持っていくか
3. [02_ROADMAP.md](02_ROADMAP.md) — 段階的な進行計画
4. [03_GUARDRAILS.md](03_GUARDRAILS.md) — 今回特に守る境界・非目標
5. [04_EXTRACTION_CRITERIA.md](04_EXTRACTION_CRITERIA.md) — Base / Runtimeへ抽象抽出する基準
6. [05_VALIDATION_PLAN.md](05_VALIDATION_PLAN.md) — 実repoでの検証方法
7. [06_DEFAULT_FIRST_STANDARD.md](06_DEFAULT_FIRST_STANDARD.md) — Default-first標準化方針

## 位置づけ

- `.kinotch/` は共通Repository規約・Schema・共通操作・Base Metaの実体。
- `KiNoTch. Runtime` は複数repoが依存して再利用する実装部品。
- `project/` は通常、各repo固有の仕様・実装・設定を置く領域。
- この `.kinotch/meta/` は、**Repository Base / Runtime全体を開発するための共通Meta** として、Base構想の文脈を保持する。

個別repoへBaseを流用する際、このMetaは「共通基盤をなぜこの形で使うのか」を理解する参考として残してよいが、個別仕様の正本として扱わない。
