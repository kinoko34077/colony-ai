# Project / Base Boundary

## 通常編集する

- `README.md`
- `project/**`

## 通常編集しない

- `.kinotch/**`
- `AGENTS.md`
- `knt.cmd`
- `.editorconfig`
- `.gitattributes`
- `.github/workflows/verify.yml`

## 例外

外部プラットフォームがルート固定配置を要求する場合のみ、必要最小限の個別ファイルをルート側へ追加してよい。

例:
- GitHub Actionsの個別deploy trigger
- GitHub固有metadata

その場合もDomain仕様や処理本体をルート特殊ファイルへ埋め込まない。
