# Common Agent Rules

## Read Economy

毎回全ファイルを読まない。`AGENTS.md` の読取順序から開始し、現在問に必要な資料だけ取得する。

## Source of Truth

- 個別定義: `project/project.json`
- 個別仕様: `project/docs/`
- 現在状態: `project/docs/CURRENT_STATE.md`
- Action: `project/contracts/actions.json`
- Surface差分: `project/contracts/surfaces.json`
- Base Meta: `.kinotch/meta/`
- 新規Repository用Template: `.kinotch/templates/project/`

実装コードが仕様と衝突した場合、勝手にコードを正本化しない。

Base-wide MetaとTemplateは共通層に置く。個別Projectの情報を `.kinotch/` へ書かない。

## Modification Boundary

個別案件の作業では `README.md` / `project/**` を変更対象とする。Base / Runtimeそのものを変更するタスクでない限り共通層を触らない。

## Implementation

- Domain CoreにSurface固有I/Oを埋め込まない。
- UI状態をDomain正本にしない。
- 同じ変換・判定・定数を複数Surfaceへ複製しない。
- 生成物を手編集しない。
- fallbackは元データを破壊しない方向を優先する。
- destructive operationには復元可能性・確認・dry-runのいずれかを検討する。

## Verification

完了宣言の前に、利用可能なら `knt verify` を実行する。外部接続やUIを変更した場合は対応するsmoke/実利用経路も確認する。
