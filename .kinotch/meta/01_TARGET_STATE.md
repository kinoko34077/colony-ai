# 01 — Target State

## 最終的に目指す開発体験

新規repoでは、開発者・Agentが最初に考える項目を極力次へ限定する。

- このプログラムは何をするか
- 入力は何か
- 出力は何か
- Domain Coreは何か
- どのSurfaceが必要か
- どのRuntime Moduleが必要か

それ以外の定型処理はBase / Runtimeへ寄せる。

## Repositoryの最終像

```text
repository/
├─ README.md          # GitHub上の個別表紙
├─ AGENTS.md          # 共通
├─ .kinotch/          # 共通・原則編集禁止
├─ knt.cmd            # 共通操作入口
└─ project/           # 個別仕様・実装・設定
```

通常作業での判断は次の二択にする。

```text
共通の仕組みを知る → .kinotch / KiNoTch. Runtime
このrepo固有を知る → README.md / project/
```

## Runtimeの最終像

Runtimeは一枚岩にしない。

```text
kernel
errors
config
resources
progress
filesystem
logging

cli
windows
mcp
api
agent

tooling/doctor
tooling/verify
tooling/generated
```

必要なmoduleだけ導入・初期化する。

## Surfaceの考え方

同じ処理をSurfaceごとに再実装しない。

```text
GUI ─┐
CLI ─┤
MCP ─┼→ Action / Application → Domain Core
API ─┤
Agent┘
```

共通化するのは「Fileを選ぶ」「Actionを実行する」「Errorを返す」等の意味であり、Windows File DialogやHTTP multipart等の物理実装まで同一化しない。

## 到達基準

この構想が十分進んだ状態では、新規小型ツールについて次が成立する。

1. Baseから開始するだけでRepository構造を再設計しなくてよい。
2. Agentは`AGENTS.md → project/project.json → docs`で迷わず着手できる。
3. `knt setup/test/build/verify/smoke/doctor`が技術スタック差を吸収する。
4. 単純GUIなら標準Shell・File Dialog・D&D・Progress等を再利用できる。
5. CLI / MCP / APIは同一Action/Coreから公開できる。
6. Base / Runtime更新と個別Domain変更が混ざらない。
7. Runtime不要moduleを読み込まないため、小型ツールの軽さを維持できる。
