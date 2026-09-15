$ErrorActionPreference = "Stop"

ollama --version
$models = ollama list
if (-not ($models -match "qwen3:0\.6b")) {
    throw "qwen3:0.6b is not installed. Run: ollama pull qwen3:0.6b"
}

python -m swarm.swarm `
    --prompt "需要不足が起きる理由を一つ考える" `
    --generations 2 `
    --nodes 5 `
    --readout-interval 2 `
    --seed 7 `
    --log logs/ollama-smoke.jsonl
