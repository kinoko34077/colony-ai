# colony-ai

> Local multi-node LLM experiment with shared CLI and Tkinter GUI entry points.

## 概要

このRepositoryは KiNoTch. Repository Base v0.3.7 に準拠します。

- 個別情報・仕様・実装: project/
- 個別プロジェクト定義: project/project.json
- 個別仕様索引: project/docs/INDEX.md
- 現在状態: project/docs/CURRENT_STATE.md
- 共通操作: .kinotch/README_BASE.md

## 主な機能

- Python標準ライブラリだけで動くunit test対象のswarm実験
- CLIとTkinter GUIから共通の実験本体を利用
- Ollama接続を明示的なProject-owned外部境界として保持

## 最短利用方法

~~~powershell
.\knt.cmd doctor
.\knt.cmd setup
.\knt.cmd dev
~~~
