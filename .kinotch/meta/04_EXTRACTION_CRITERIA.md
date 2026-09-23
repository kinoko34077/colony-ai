# 04 — Extraction Criteria

個別repo内の仕組みをBase / Runtimeへ昇格させる際の判断基準。

## A. Baseへ昇格するもの

Baseは「配置・規則・操作入口・契約」を担当する。

次を満たす場合に候補とする。

1. 複数repoで同じ開発上の意味を持つ。
2. 技術スタックに依存しない、またはprofile差で吸収できる。
3. 個別repoごとに変える合理的理由が少ない。
4. Agentが共通で知る価値が高い。
5. 配置や命名を固定すると探索量が明確に減る。

例:

- AGENTSの入口
- `project/docs/INDEX.md`
- Current Stateの位置
- `knt test/verify/doctor`という操作語彙
- Action / Error等のSchema
- generated artifactは手編集禁止という規則

## B. Runtimeへ昇格するもの

Runtimeは「複数repoから実際に再利用する実装」を担当する。

次を満たす場合に候補とする。

1. 異なるrepoで実装が重複している。
2. Domain固有意味を含まない。
3. 入出力Contractを安定して定義できる。
4. 共通化によって条件分岐・dependency・設定量が増えすぎない。
5. 独立テスト可能。
6. Optional moduleとして切り離せる。

例:

- ProgressEvent
- Cancellation
- File / Folder resource abstraction
- CLI JSON formatter
- Windows File Dialog adapter
- MCP Action mapper
- generated stale checker

## C. Projectに残すもの

次は原則Projectに残す。

- Domain Core
- 個別UIレイアウト
- 特殊な性能最適化
- repo固有の互換処理
- 特殊なdeploy policy
- 一度しか現れていない仕組み
- 変更理由が他repoと異なるもの

## D. Domain Libraryとして分離するもの

複数repoで再利用するが、Runtime一般機能ではない場合。

例:

```text
kinotch-text
kinotch-music
kinotch-image
```

Runtimeへ押し込まず、独立したDomain Libraryを検討する。

## 判断手順

```text
個別repoで重複を発見
↓
同じ知識 / 同じ変更理由か？
├─ No → Projectに残す
└─ Yes
   ↓
配置・規則・契約か？
├─ Yes → Base候補
└─ No
   ↓
実装を複数repoで再利用するか？
├─ Yes → Runtime候補
└─ No → Projectに残す
```

## 昇格時の原則

個別実装を即削除しない。

1. 共通版を作る。
2. 代表repoで置換する。
3. 既存テスト / smokeで同等性を確認する。
4. 共通化による複雑化がないか確認する。
5. 問題なければ他repoへ適用する。
