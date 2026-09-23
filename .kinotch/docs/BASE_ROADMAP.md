# KiNoTch. Base / Runtime Roadmap

この文書は共通層から参照する短いRoadmap Indexである。
背景・到達状態・判断基準・検証計画を含む詳細な設計Metaは [`../meta/README.md`](../meta/README.md) を参照する。

## Phase 0 — Repository Base v0.1系

- Base / Project境界
- 共通AGENTS
- Project Manifest
- Action / Surface Contract
- `knt` command router
- doctor / verify / base-check
- Spec / Current State / ADR骨格
- Base / Runtime設計Meta

## Phase 0.5 — Repository Base v0.2 Hardening

- Base自身のIdentityとSPEC / CURRENT_STATE
- `.kinotch/meta/` と `.kinotch/templates/project/` の分離
- Manifest / Action / Surface Schema validation
- Profile / path / command diagnostics
- Base self-test fixtures and runner
- Deterministic `base-refresh` and strict Base protection
- Runtime Contractの確定済み / 候補の分離

## Phase 1 — Runtime Kernel v0.1

- Action / Result / Error / Progress / Resourceの最小実装
- Config / filesystem / logging
- 言語別の薄いbinding方針

## Phase 2 — 代表repoで試験導入

- CLI + MCP: `jev-audit`
- Windows GUI + CLI: `SynTrail-LM`
- API / Web: `kinotch-api` / `standby-display`
- Portable Contractの成熟度と適用範囲を評価し、Runtimeをprovisionalに保つ

## Phase 2B — Default extraction

- Portable Contractの成熟を待たず、安全に外せる共通便利機能をDefault化する。
- Surface DefaultとTool Defaultを分離する。
- 正本は `.kinotch/defaults/catalog.json` とする。

## Phase 3A — KiNoTch. Default Catalog

- Surface: `minimal`, `web-app`, `cli`, `windows`, `mcp`, `api`, `agent`, `library`
- Tool: `verify-binding` (CLI alias `verify`), `ci-test`, `generated-integrity`, `file-io`, `pwa`, `pages`, `secrets`, `local-app`
- `knt init`はProfile選択からRuntime moduleを自動注入しない。
- 既存Framework・Project実装はOverrideとして保持できる。

## Phase 3B — Actual Default behavior (safe slice complete)

- `verify-binding` optional Project binding; the `knt verify` common router is L1
- `ci-test` separate non-deploy doctor→setup→verify workflow template
- `generated-integrity` source and artifact SHA-256 check/update templates
- `web-app` / `pwa` relative-base manifest, service worker, registration, and check templates
- `file-io` format-independent boundary and UTF-8 text-only helper
- `cli` JSON/error/help/exit helper
- `windows` Explorer/clipboard shell boundary
- `mcp` tool boundary descriptor without a second registry
- `api` permissive error-envelope schema without HTTP policy
- No Domain format, deploy policy, or Runtime module is generated.

## Phase 4 — init / migrate and existing repository adoption (next)

- `knt init --profile <surface> --default <tool-default>`
- `knt migrate` dry-run / explicit `--apply`
- Explicit apply materializes only missing safe helpers and preserves overrides.
- Manifest-less repository-shape probe via a Base source override
- generated artifact / stale check
- 詳細doctor / conformance report

## Phase 5 — 既存repoへ段階導入

一括書換えを行わず、保守・改修のタイミングで適用する。

## Phase 6 — 必要時のみ安定化拡張

Version migration / multi-language binding / generated descriptors等は、実利用上必要になった場合のみ進める。
