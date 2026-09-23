# KiNoTch. Runtime Integration v0.2

Base v0.2はRuntime実装そのものを内包しない。ここではRepository Baseと将来のRuntimeの責任境界、接続宣言、Contractの検証状態を固定する。

## Base v0.2で定義済み

以下はRepository Baseが正本として所有し、Repository構造と宣言の検証に
利用する。

- Project Manifest
- Profile
- Surface declaration
- Action Registry structure
- Repository structure

Base側の `.kinotch/schemas/` には、Baseが検証する宣言のSchemaと、Runtime
Execution Contractの検証互換コピーが存在する。互換コピーはRuntimeの実行
実装やExecution Contractのcanonical sourceを意味しない。

## Runtime所有のExecution Contract

以下はKiNoTch. Runtimeが正本として所有し、実行意味を定義する。

- Action Result
- Action Error
- Progress Event
- Resource
- Artifact
- Action execution semantics

ActionRequest、ActionContext、Cancellation、Config execution semantics、
filesystem / logging / platform service bindingsは、Runtime側でPilotごとに
検証する候補であり、Baseの所有物ではない。

## 現在のRuntime Contract正本

`kinotch-runtime` v0.1が作成済みとなった現在、Execution Contractの正本は
以下である。

```text
kinotch-runtime/project/contracts/execution/
```

Base側の以下は、Repository Baseの検証互換コピーとして扱う。

```text
.kinotch/schemas/
```

関係は次で固定する。

```text
Runtime canonical source
        ↓ explicit, reviewed synchronization when needed
Base compatibility schema
```

BaseとRuntimeでExecution Schemaを独立編集してはならない。同期が必要に
なった場合も、Runtime正本の変更とBase互換コピーの更新を別責務として
レビュー・検証する。自動同期toolは、Contractの変更頻度と第2Pilotの
結果を確認するまで追加しない。

## 所有権

Repository Baseが所有するもの:

- Project Manifest
- Profile
- Repository structure
- Surface declaration
- Runtime version reference
- Runtime module declaration
- Base validation and common command vocabulary

KiNoTch. Runtimeが所有するもの:

- Action execution
- Result / Error / Progress execution semantics
- Resource / Artifact runtime behavior
- Cancellation
- Config execution behavior
- Language-specific bindings

Runtimeの正本ContractはRuntime Repositoryへ移行済みである。Baseは必要な
version参照、Repository構造検証、および明示的な互換Schema同期だけを担う。

Contractの成熟度（implemented / unit-tested / pilot-exercised /
multi-repo-validated / stable）はRuntime側のContract Matrixで管理し、
Baseは一括してstableとみなさない。

第2Pilotの現時点の境界は、JavaScript / Hono / Cloudflare Workersである
`kinotch-api`におけるAction IDとError semanticsのtest-only観察までである。
これはPARTIAL GOであり、GatewayへのRuntime依存、ActionRegistry、
ActionResultによるHTTP Response包装はHOLDとする。詳細な証拠と次の判断は
RuntimeのPilot Report / ADRを正本とする。

## Module候補

~~~text
kernel
config
errors
progress
resources
filesystem
logging
cli
windows
mcp
api
agent
tooling.doctor
tooling.verify
tooling.generated
tooling.bootstrap
~~~

すべてを一括依存しない。 project/project.json の runtime.modules は必要Moduleの論理宣言であり、Base v0.xでは実在packageを強制しない。

## 依存境界

~~~text
Surface Adapter -> Application -> Domain Core
       |
       +---- Runtime Contract / Platform Service
~~~

Domain CoreからGUI / MCP / HTTP / PowerShell等へ直接依存しない。

## Runtimeへ入れないもの

- 各repoのDomain処理
- 個別アルゴリズム
- 個別データモデル
- 個別deploy policy
- 将来用途だけの万能抽象化

## .ai-guidelinesとの関係

BaseはRepository / Agent / implementation workflowを所有する。.ai-guidelines はUI/UXとDomain横断設計ポリシーを所有する。両者は責任を参照し、同一規則を全文複製しない。
