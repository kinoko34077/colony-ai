# 03 — Guardrails / Non-Goals

## 最重要原則

この基盤の目的は「共通化率を最大にすること」ではない。

目的は、**繰り返し発生する同じ知識・同じ操作・同じ境界だけを吸収し、個別repoで考える量を減らすこと**である。

## 共通層を個別repoで直接いじらない

通常の個別開発では以下を変更しない。

- `AGENTS.md`
- `.kinotch/**`
- `knt.cmd`
- 共通CI
- KiNoTch. Runtime本体

共通層に不足がある場合は、個別repoへforkした修正版を埋め込まず、Base / Runtime側の変更候補として扱う。

## 過剰抽象化を避ける

以下だけを理由にRuntimeへ追加しない。

- 将来使うかもしれない
- 一度だけ似たコードを書いた
- frameworkとして綺麗に見える
- 抽象化できそう

最低でも「異なるrepoで同じ意味・同じ変更理由として反復している」ことを確認する。

## DomainをRuntimeへ入れない

Runtimeへ入れない例:

- 音楽理論固有処理
- IDS解析固有処理
- Jev監査ロジック
- SynTrail学習ロジック
- 字幕変換ロジック

共通Domain Libraryが必要ならRuntimeとは別package/repoにする。

## Surface差を消しすぎない

共通化するのは意味まで。

例:

```text
Resourceを選択する
```

は共通化可能だが、

- Windows File Dialog
- CLI path argument
- HTTP upload
- MCP Resource

は各Adapterが担当する。

## Local処理へ不要なTransportを挟まない

GUI / CLIから同一processのCoreを呼べる場合、共通化だけを目的にlocalhost HTTPやMCPを挟まない。

- in-processで済む → direct call
- cross-processが必要 → IPC等
- remoteが必要 → HTTP / MCP

## Optional / Lazyを維持する

MCPを使わないGUIへMCP SDKを要求しない。
APIを使わないCLIへHTTP serverを要求しない。

- module単位dependency
- lazy initialization
- per-action resource acquisition

を優先する。

## READMEは個別の表紙

READMEはGitHub上の主要表示面なので個別にする。
共通操作・開発規則を重複記述せず `.kinotch/README_BASE.md` へ参照させる。

## Deployを一律化しない

Test / Build / Verifyは共通化しやすいが、Production Deployはrepoごとに責任境界が異なる。

- auto deploy
- manual deploy
- GitHub Pages
- Cloudflare
- local package
- deployなし

を個別に選択可能にする。

## Secrets

- secret値をBase / docs / logsへ書かない。
- `.env.example`は名前と用途のみ。
- Runtime/doctorはsecretの存在を検査しても値を表示しない。

## Compatibility

形式統一のために既存互換性を破壊しない。
legacy format / fallback / migrationは各project仕様として明示する。
