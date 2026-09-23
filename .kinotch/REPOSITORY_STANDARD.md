# KiNoTch. Repository Standard v0.1

## 1. 目的

個別repoごとに開発基盤・Agent規則・共通操作を再設計せず、個別差分だけへ集中できる状態を作る。

## 2. 中心原則

- 共通層と個別層を物理的に分離する。
- 通常の個別開発では共通層を編集しない。
- 個別差分は `README.md` と `project/**` に置く。
- READMEは外向きの紹介Surfaceであり、詳細仕様を重複保持しない。
- 同じDomain処理をCLI / GUI / MCP / APIへ再実装しない。
- SurfaceはApplication Actionへの薄いAdapterとする。
- 同一知識は一元化し、異なる変更理由は分離する。
- 小規模案件へ不要な階層・文書・抽象化を強制しない。

## 3. 標準読取順序

```text
README.md
→ project/project.json
→ project/docs/INDEX.md
→ project/docs/CURRENT_STATE.md
→ 関連仕様
→ 関連コード
→ 関連テスト
```

## 4. 個別領域

`project/**` は個別repoの正規編集領域である。Base-wide Metaは `.kinotch/meta/`、新規repo生成用Templateは `.kinotch/templates/project/` に置く。

推奨:

```text
project/
├─ project.json
├─ .env.example
├─ .gitignore
├─ docs/
├─ contracts/
├─ src/
├─ tests/
└─ scripts/
```

## 5. 共通領域

`.kinotch/**` と `AGENTS.md`、`knt.cmd`等はBase管理物である。個別repo固有事情をここへ書き込まない。Runtime implementationはBaseへコピーしない。

## 6. 技術スタック

Node / Python / Rust / static Web等を統一しない。`knt` が `project.json` のコマンドへ転送することで、人間・Agentから見える入口だけ統一する。

## 7. GitHub特殊配置

GitHub Actions等、ホスト側がルート固定パスを要求するものは例外になり得る。共通verify workflowはBase管理とし、個別deploy等が必要な場合は「ホスト要求による明示的例外」として最小ファイルだけ追加する。

## 8. Runtime

RuntimeはBaseへコピーしない。`project/project.json.runtime.modules` で必要Moduleを宣言し、実体は外部Runtime package / libraryとして参照する。Base v0.xのModule名は論理宣言であり、実在packageを意味しない。

## 9. Base更新

個別repoの共通ファイルを手修正して追従しない。Base側で版を上げ、Conformance / migration手順で更新する。
