# colony-ai

小型LLMを多数の論理ノードとして反復実行する実験系です。ノードは固定ロールを持たず、元の問いと前世代からランダム抽出した断片だけを入力にして、短い意味単位を生成します。

## 前提

- Python 3.11 以降
- Ollama が起動済み
- `qwen3:0.6b` がインストール済み

確認コマンド:

```powershell
ollama --version
ollama list
```

Ollama は `http://127.0.0.1:11434` を使用します。外部APIキーは不要です。

## CLI

小規模確認:

```powershell
python -m swarm.swarm --prompt "需要が落ちた理由を考える" --generations 2 --nodes 5 --seed 7
```

通常実験:

```powershell
python -m swarm.swarm --prompt "ここに問い" --generations 100 --nodes 100 --seed 7
```

長い問いはファイルから読めます。

```powershell
python -m swarm.swarm --prompt-file .\question.txt --generations 10 --nodes 100
```

Readout周期を短くして小規模 smoke を行う場合は `--readout-interval 2` のように指定できます。

実行中は世代進行と5世代ごとのReadoutを表示し、生ノード出力は `logs/*.jsonl` に保存します。JSONLには設定、ノードのサンプル・raw/normalized出力、Readout、Finalizer、経過時間を記録します。

## 最小GUI

```powershell
python -m swarm.gui
```

GUIでは問い、世代数、ノード数、seed、モデル、Ollama URLを確認・変更できます。画面は左に各世代内の各ノードの直接出力、右に5世代ごとのReadout、下にFinalizerの最終出力を表示します。実験本体はCLIと同じ関数を使用します。

システムプロンプトはGUI上部の「ノード」「Readout」「Finalizer」タブで個別に編集できます。Readout文字数上限とFinalizer文字数上限も指定できます。空欄なら文字数での追加制限はなく、Ollamaの `num_predict=24` は共通で適用されます。

## テスト

Ollamaを呼ばないunit test:

```powershell
python -m unittest discover -v
```

実Ollama smoke:

```powershell
.\scripts\smoke_ollama.ps1
```

## 実測済み確認

2026-09-15 にローカル Ollama `0.33.3` / `qwen3:0.6b` で確認しました。

- 5ノード × 2世代、Readout周期2: 約3.94秒。node 10件、Readout 1件、Finalizer 1件。
- 100ノード × 1世代、Readout周期1: 約31.55秒。node 100件、エラー0件、Readout 1件、Finalizer 1件。
- いずれも `think=false`。ノード正規化出力の最大長は30文字。

100ノードの全断片をReadoutへ渡すと初期値の `num_ctx=2048` を超えるため、ノード生成は2048のまま、ReadoutとFinalizerだけ観測用 `num_ctx=8192` を使用します。Ollamaへの物理HTTPリクエストは既定1本ずつですが、ノードは論理的にasyncで生成します。

## v0.1の境界

Readoutは観測専用で、群体ノードへフィードバックしません。Planner、Critic、評価・スコアリング、embedding、DB、外部検索、GUI以外の外部サービスは実装していません。LLM生成そのものの完全なbit再現性や品質向上は保証しません。
