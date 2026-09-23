# 00 — Context / Why This Exists

## 背景

KiNoTch.の各種repoでは、扱うDomainは異なっていても、開発の周辺処理が繰り返し個別実装されている。

代表例:

- `jev-audit`: CLIとMCPが同じAudit Coreを利用し、PowerShell setup・PATH登録・JSON出力・exit codeを個別実装している。
- `SynTrail-LM`: libraryをCLI / GUI / Trainerから共有し、Windows native menu、Open/Save、D&D、Pause/Resume等を実装している。
- `colony-ai`: CLIとGUIが同じ実験Coreを利用する。
- `kinotch-api`: build → generated snapshot → stale check → test → deployという運用を持つ。
- `standby-display`: 別repoの正本から生成物を同期し、hash / stale checkを行う。
- `IDS-Composit`: AGENTS、仕様索引、Current State、ADR、Hard Scope、fallback境界を明示している。
- `lyric_reader_page`: Canonical Source、Adapter、Quality Gateを分離している。
- `srt2subtitle`: setup / check / packaging / runtime data directoryを個別に持つ。

これらから、同じDomain処理を共通化するのではなく、**プログラムを起動・操作・検証・接続・診断する横断的な仕組み**に反復が多いことが分かった。

## 解決したい問題

従来は新規repoごとに、以下を再検討・再実装しやすかった。

- ファイル / フォルダ階層
- README以外のAgent向け導線
- setup / dev / test / build / smoke
- CLI引数・JSON出力・exit code
- Windows File Dialog / D&D / Progress / Cancel
- API / MCPへの公開
- Error / Config / Secret / Logging
- Current State / ADR / Specの配置
- generated artifactの同期・stale検査
- 外部依存失敗と内部失敗の切り分け

この再実装は、コード量だけでなく、Agentが毎回repo構造を探索するコスト、仕様のばらつき、共通修正の取り込み漏れを増やす。

## 基本方針

解決方法は「巨大な万能frameworkを作る」ことではない。

1. 同じ**意味・契約・操作語彙**だけを共通化する。
2. Domain固有ロジックは各repoに残す。
3. GUI / CLI / API / MCP / AgentはCoreの別Surfaceとして扱う。
4. 共通ファイルは個別repoで原則編集しない。
5. 個別差分は `README.md` と `project/` に閉じ込める。
6. 実装として複数repoで再利用するものだけをKiNoTch. Runtimeへ昇格する。

## このBaseの目的

新しいプログラムを「一から構成する」のではなく、

> KiNoTch.標準の実行・開発基盤に、そのrepo固有の能力だけを差し込む

状態へ近づける。
