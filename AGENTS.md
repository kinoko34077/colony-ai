# AGENTS.md

このリポジトリは KiNoTch. Repository Base に準拠する。

## 1. 最初に読むもの

1. `README.md`
2. `project/project.json`
3. `project/docs/INDEX.md`
4. `project/docs/CURRENT_STATE.md`
5. 現在タスクに関係する `project/docs/`・コード・テスト

Base / Runtimeそのものの変更、共通化判断、既存repo移行を扱う場合のみ `.kinotch/meta/README.md` と関連Metaを追加で読む。

共通規則が必要な場合のみ `.kinotch/` を読む。毎回全共通資料やMetaを読み直さない。

## 2. 変更境界

通常の個別開発で編集してよいもの:

- `README.md`
- `project/**`

原則として編集しないもの:

- `AGENTS.md`
- `.kinotch/**`
- `knt.cmd`
- `.editorconfig`
- `.gitattributes`
- 共通CI
- KiNoTch. Runtime 本体

共通層の修正が必要に見える場合は、個別repoへ場当たり的に修正を入れず、Base / Runtime側へ昇格すべき変更か判定する。

## 3. 正本

- 個別プロジェクトの機械可読入口: `project/project.json`
- 個別仕様: `project/docs/`
- 現在状態: `project/docs/CURRENT_STATE.md`
- Action契約: `project/contracts/actions.json`
- Surface差分: `project/contracts/surfaces.json`
- 共通Repository規則: `.kinotch/REPOSITORY_STANDARD.md`
- 共通Agent規則: `.kinotch/AGENT_RULES.md`
- Runtime接続規則: `.kinotch/RUNTIME_INTEGRATION.md`

READMEはGitHub上の人間向け入口であり、詳細仕様の正本として重複記述しない。

## 4. 作業原則

- 要求・仕様・設計・実装・テストを混同しない。
- 同じ知識を複数箇所へ複製しない。
- Core処理をGUI / CLI / MCP / API固有コードへ埋め込まない。
- 変更前に関連仕様・既存テスト・影響範囲を確認する。
- 生成物は手編集しない。正本を変更し再生成する。
- 外部依存失敗と内部ロジック失敗を区別する。
- 共通化は同じ知識・同じ変更理由に対してのみ行う。
- 将来使う可能性だけを理由に抽象層を増やさない。

## 5. 共通コマンド

```text
knt doctor
knt setup
knt dev
knt test
knt build
knt verify
knt smoke
knt base-check
```

Windows cmdでは `knt.cmd <command>`、PowerShellでは `.kinotch/scripts/knt.ps1 <command>` を使用する。

## 6. 完了条件

最低限、変更対象に応じて以下を確認する。

- 関連仕様との整合
- 対象テスト
- 既存機能の回帰
- `knt verify`
- 必要なら `knt smoke`
- `project/docs/CURRENT_STATE.md` の更新
- 仕様そのものが変わった場合のみ正本文書の更新
