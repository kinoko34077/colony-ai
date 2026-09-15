# 小型LLM群体再帰推論 v0.1 設計

## 目的

Ollama 上の `qwen3:0.6b` を、固定ロールを持たない独立論理ノード群として実行する。各世代の全ノードは同じ前世代を参照し、元の問いとランダム抽出した少数の断片から短い意味単位を1つ生成する。

## 範囲

実装対象は、単一ノード生成、同期世代更新、5世代ごとの読み出し、終了時のFinalizer、JSONLログ、CLI、unit test、実Ollama smoke test、および最後に追加する超簡潔なローカルGUIとする。Planner、Critic、スコアリング、DB、Web検索、分散実行、長期記憶は含めない。

## アーキテクチャ

`swarm/swarm.py` を中心に、設定 dataclass、Ollama クライアント境界、出力正規化、世代オーケストレーション、Readout、Finalizer、ログ出力を小さな関数として分離する。モデル呼び出しは関数引数またはProtocol経由で差し替え、unit testではfake generatorを使う。

ノード生成は `asyncio.gather` で論理的に並列化する。世代開始時点の `previous_generation` をスナップショットとして全タスクへ渡し、生成中は変更しない。Readout は直近5世代のログを観測するだけで、ノード用入力には渡さない。

## 設定

初期値は指示書どおりとする。

```text
MODEL=qwen3:0.6b
NODE_COUNT=100
SAMPLE_MIN=1
SAMPLE_MAX=4
MAX_OUTPUT_CHARS=30
READOUT_INTERVAL=5
MAX_GENERATIONS=100
TEMPERATURE=0.8
NUM_PREDICT=24
NUM_CTX=2048
THINK=false
```

CLIでは `--prompt`、`--generations`、`--nodes`、`--seed`、必要ならログ出力先を指定できる。Ollama URLは環境変数または設定の簡単な値として変更可能にする。

## 入出力とエラー

ノード入力は元の問い全文と、前世代から重複なしで1〜4個抽出した断片だけで構成する。第一世代は元の問いだけを渡す。出力は前後空白を除去し、最初の意味単位を採用し、30文字で切断する。空出力は1回だけ再生成し、それでも空なら空ノードとしてログに残す。単一ノード失敗はそのノードを空出力として記録し、世代全体を停止しない。

JSONLには実行設定、generation、node_index、sampled_previous_outputs、raw_output、normalized_output、Readout、Finalizer、実行時間と可能なtoken情報を保存する。

## GUI

CLIと同じ実行関数を呼ぶローカル専用の最小画面を最後に追加する。画面では prompt、generations、nodes、seed、Ollama接続状態、モデル名を確認・入力でき、実験開始後は現在世代、Readout、Finalizer結果、ログファイルを表示する。認証、外部公開、複雑な編集画面、リアルタイム全ノード表示は実装しない。GUIがなくてもCLIは完全に利用可能とする。

## 検証

fake generatorによるT1〜T10のunit testを先に作成する。実Ollamaでは5ノード×2世代で `think=False`、短い出力、世代更新、Readoutを確認し、その後100ノードを実行して時間と設定を記録する。READMEには実測値のみを記載し、未実施の性能は断定しない。
