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

実行中は世代進行と5世代ごとのReadoutを表示し、生ノード出力は `logs/*.jsonl` に保存します。JSONLには設定、ノードのサンプル・raw/normalized出力、Readout、Finalizer、経過時間を記録します。

## 最小GUI

```powershell
python -m swarm.gui
```

GUIでは問い、世代数、ノード数、seed、モデル、Ollama URLを確認・変更できます。接続確認、実行中の世代表示、Readout、Finalizer結果、ログパスを表示します。実験本体はCLIと同じ関数を使用します。

## テスト

Ollamaを呼ばないunit test:

```powershell
python -m unittest discover -v
```

実Ollama smoke:

```powershell
.\scripts\smoke_ollama.ps1
```

## v0.1の境界

Readoutは観測専用で、群体ノードへフィードバックしません。Planner、Critic、評価・スコアリング、embedding、DB、外部検索、GUI以外の外部サービスは実装していません。LLM生成そのものの完全なbit再現性や品質向上は保証しません。
