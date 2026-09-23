# Common Development Flow

```text
目的 / 要求
↓
受入条件
↓
仕様
↓
Action / 状態 / 境界
↓
Core / Application
↓
必要なSurface Adapter
↓
Test
↓
Regression
↓
Smoke / 実利用経路
↓
CURRENT_STATE更新
```

## 新規機能

1. `project/docs/` で要求・挙動・受入条件を確認または定義
2. Action化できる場合は `project/contracts/actions.json` に追加
3. Domain / Applicationを実装
4. 必要なSurfaceだけ接続
5. unit / contract / integration / smokeを必要範囲で追加
6. `knt verify`
7. `CURRENT_STATE.md` 更新

## バグ修正

1. 再現条件を固定
2. 可能なら失敗する回帰テストを先に追加
3. 最小責務で修正
4. 関連回帰を確認
5. Current State / 仕様へ影響する場合のみ更新

## 共通化候補

個別repo内で解決した後、複数repoへ同じ知識として再利用されることが確認できた場合のみBase / Runtimeへ昇格する。

ただし、Domain意味を持たず安全に外せる共通便利機能は、Default-first方針に従いProject単位の `DEFAULT` / `OVERRIDE` / `DISABLED` として先に提供できる。Portable Contractの成熟度をDefault導入の前提にしない。
