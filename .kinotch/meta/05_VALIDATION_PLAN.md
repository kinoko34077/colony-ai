# 05 — Validation Plan

Base / Runtimeは文書上きれいでも、個別repoが扱いづらくなるなら失敗とする。

## 検証対象

### 1. CLI + MCP系 — jev-audit

確認するもの:

- 同じAudit Coreを維持したままSurfaceを薄くできるか
- CLI JSON / exit codeをRuntime化できるか
- MCP mappingがCoreへ侵入しないか
- setup / doctorでPython環境検出を一般化できるか

### 2. Windows GUI + CLI系 — SynTrail-LM

確認するもの:

- GUI optional featureを維持できるか
- New/Open/Save/Save As/D&Dを共通Shellへ寄せられるか
- Progress / Pause / Resume / Cancelのうち何が一般化可能か
- GUI依存がCoreへ逆流しないか

### 3. API系 — kinotch-api

確認するもの:

- Action / validation / error / request ID等を共通化できるか
- Cloudflare固有Service BindingをProject側に残せるか
- auth / rate-limit / deploy policyを無理に一律化しないか

### 4. Web / generated同期系 — standby-display

確認するもの:

- generated artifact / hash / stale checkを一般化できるか
- legacy / modern compatibilityをProject固有のまま保持できるか

### 5. Agent系 — dev_agent

確認するもの:

- Agent固有OrchestrationとAction実行を分離できるか
- AgentがRuntimeを使用してもPlanner等の独自性を損なわないか

## 成功条件

導入前後で次を比較する。

### 開発量

- setup / CLI / GUI shell / MCP / API等の重複実装が減る。

### 探索量

Agentが新規repoへ入った際、入口探索なしに次へ到達できる。

```text
AGENTS.md
→ project/project.json
→ project/docs/INDEX.md
→ 対象仕様 / code / test
```

### 依存量

不要Surfaceのdependencyが追加されない。

### 実行性能

共通化によって不要なserver / IPC / reflection等が挟まらない。

### 可読性

個別repoを読む際、Base由来とProject固有を迷わず識別できる。

### 変更影響

Runtime更新はRuntime利用箇所だけ、個別Domain変更はprojectだけへ閉じる。

## 失敗条件

以下が起きる場合、その抽象は戻す・細分化する。

- 単純な個別実装より設定ファイルが増える。
- 共通化のためのif/switchが大量に増える。
- Runtimeを理解しないとDomain Coreを読めなくなる。
- GUIだけのツールがMCP/API dependencyを持つ。
- Base規格に合わせるため既存互換性を壊す。
- Agentの探索対象が逆に増える。

## 評価原則

「共通化できたか」ではなく、

> 新しいrepoを作る・読む・直す・検証する手間が実際に減ったか

で判断する。
