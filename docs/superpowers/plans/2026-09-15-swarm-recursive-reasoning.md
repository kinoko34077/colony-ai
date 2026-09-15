# 小型LLM群体再帰推論 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a small Python/Ollama experiment runner for synchronized recursive swarm reasoning, with JSONL observability, CLI execution, tests, smoke verification, and a minimal local GUI.

**Architecture:** Keep the core in `swarm/swarm.py` with dataclass settings and narrow callable boundaries for node, readout, and finalizer generation. Each generation receives an immutable copy of the previous generation; the logger records raw and normalized values without affecting the state. `swarm/gui.py` wraps the same CLI-facing orchestration and displays only configuration, connection status, progress, readouts, and the final answer.

**Tech Stack:** Python 3.11+ standard library (`asyncio`, `urllib`, `json`, `argparse`, `tkinter`, `unittest`) and Ollama HTTP API; no agent framework, database, vector store, or external UI dependency.

**Spec:** `docs/superpowers/specs/2026-09-15-swarm-recursive-reasoning-design.md`

## Global Constraints

- Model is `qwen3:0.6b` by default.
- Node generation uses `think=false`, temperature `0.8`, `num_predict=24`, `num_ctx=2048`, and `keep_alive=-1`.
- Every node in a generation reads the same prior-generation snapshot; same-generation outputs never enter sampling.
- Every node receives the complete original prompt.
- Node output is one normalized short meaning unit, capped at 30 characters.
- Readout runs every 5 generations and never feeds back into node input.
- Single-node errors become empty node results and do not abort the whole run.
- No roles, scoring, evaluator, external search, persistence database, or automatic content stop condition.

### Task 1: Project scaffold and pure core behavior

**Files:**
- Create: `swarm/__init__.py`
- Create: `swarm/swarm.py`
- Create: `tests/__init__.py`
- Create: `tests/test_swarm.py`
- Create: `requirements.txt`

**Interfaces:**
- `Settings` dataclass owns all defaults and validates positive counts and ranges.
- `normalize_output(raw: str, max_chars: int) -> str` strips, removes a leading list marker, keeps the first line/meaning unit, and caps length.
- `sample_previous(previous: Sequence[str], rng: random.Random, minimum: int, maximum: int) -> list[str]` samples without replacement and caps at available entries.
- `build_node_prompt(original_prompt: str, samples: Sequence[str]) -> str` includes the complete original prompt and only sampled fragments.
- `async run_generation(original_prompt: str, previous_generation: Sequence[str], settings: Settings, node_generator: NodeGenerator, rng: random.Random, generation: int, logger: EventLogger | None = None) -> list[NodeResult]` creates all tasks from one previous snapshot and returns one result per node.

- [ ] Write failing tests for defaults, prompt construction, sampling bounds/reproducibility, normalization, and synchronized generation input snapshots.
- [ ] Run `python -m unittest tests.test_swarm -v`; expect failures because `swarm.swarm` is missing.
- [ ] Implement the dataclass, pure helpers, typed result records, and `run_generation` with `asyncio.gather` and per-node exception isolation.
- [ ] Run the focused tests again; expect PASS.
- [ ] Commit `test: define swarm core behavior` and `feat: implement synchronized swarm core` separately after their respective green checks.

### Task 2: Ollama adapter, orchestration, readout, finalizer, and JSONL logs

**Files:**
- Modify: `swarm/swarm.py`
- Create: `tests/test_runner.py`

**Interfaces:**
- `class OllamaClient`: `generate(system_prompt: str, user_prompt: str, settings: Settings, max_chars: int | None = None) -> Awaitable[GenerationResponse]` and `check_connection() -> Awaitable[dict]`.
- `async run_experiment(original_prompt: str, settings: Settings, client: GeneratorClient, log_path: Path) -> ExperimentResult` returns generations, readouts, final answer, and timing metadata.
- `readout_prompt(original_prompt: str, recent_generations: Sequence[Sequence[str]]) -> str` and `finalizer_prompt(original_prompt: str, readouts: Sequence[str]) -> str` keep observation and final synthesis separate.
- `JsonlLogger.write(event: dict) -> None` writes one JSON object per line, including settings and timing.

- [ ] Write failing fake-client tests for generation transitions, Readout at intervals, no Readout feedback, Finalizer receiving all Readouts and original prompt, and isolated node failure.
- [ ] Run `python -m unittest tests.test_runner -v`; expect failures for missing runner behavior.
- [ ] Implement the stdlib HTTP Ollama adapter using `/api/version` and `/api/chat`, passing `think: false` and the configured options; preserve response metadata when present.
- [ ] Implement orchestration with a copied prior-generation list, Readout only after each interval, finalizer after the last generation, and elapsed-time records.
- [ ] Implement JSONL events for run, node, readout, finalizer, and completion.
- [ ] Run all unit tests; expect PASS.
- [ ] Commit `feat: add Ollama runner and experiment logs`.

### Task 3: CLI and documentation

**Files:**
- Modify: `swarm/swarm.py`
- Create: `README.md`
- Create: `.gitignore`
- Create: `tests/test_cli.py`

**Interfaces:**
- `build_parser() -> argparse.ArgumentParser` supports `--prompt`, `--prompt-file`, `--generations`, `--nodes`, `--seed`, `--log`, and `--ollama-url`.
- `main(argv: Sequence[str] | None = None) -> int` runs the experiment and prints generation progress, interval Readouts, and the Finalizer answer.

- [ ] Write failing parser tests for required prompt input and overrides.
- [ ] Run `python -m unittest tests.test_cli -v`; expect failures for missing parser/main.
- [ ] Implement CLI output without dumping all node results, and document setup, command examples, log format, and no-credential local Ollama requirements.
- [ ] Run all unit tests and a `--help` check; expect PASS and readable help.
- [ ] Commit `feat: add swarm CLI and usage docs`.

### Task 4: Real Ollama smoke test and 100-node verification

**Files:**
- Create: `scripts/smoke_ollama.ps1`
- Modify: `README.md`
- Create: `logs/.gitkeep`

**Interfaces:**
- Smoke command runs `python -m swarm.swarm --prompt ... --generations 2 --nodes 5 --seed 7 --log ...` against the local Ollama URL.
- Full verification runs the same CLI with `--nodes 100` and a small generation count selected to prove logical node count without starting the full 100-generation experiment.

- [ ] Run `ollama --version` and `ollama list`; verify `qwen3:0.6b` is present.
- [ ] Run the 5-node × 2-generation smoke script and inspect output plus JSONL for `think=false`, short output, generation updates, and Readout/Finalizer.
- [ ] Run the 100-node verification with a bounded generation count and record elapsed time, model, node count, and generation count.
- [ ] Update README with observed results and clearly label anything not measured.
- [ ] Commit `test: verify local Ollama swarm smoke`.

### Task 5: Minimal local GUI

**Files:**
- Create: `swarm/gui.py`
- Create: `tests/test_gui.py`
- Modify: `README.md`

**Interfaces:**
- `SwarmGui` displays editable prompt, generations, nodes, seed, model, Ollama URL, connection status, progress, latest Readout, final answer, and log path.
- `python -m swarm.gui` starts the local Tkinter window and invokes the same `run_experiment` function in a worker thread.

- [ ] Write failing tests for GUI configuration parsing and status formatting without requiring a display.
- [ ] Run `python -m unittest tests.test_gui -v`; expect failures for missing GUI helpers.
- [ ] Implement a compact Tkinter form, connection check button, start button, disabled state during execution, and text result area; keep all experiment logic in `swarm.swarm`.
- [ ] Run GUI helper tests and `python -m swarm.gui` manually if a desktop display is available.
- [ ] Run the complete unit suite and document GUI usage.
- [ ] Commit `feat: add minimal swarm configuration GUI`.

## Completion Verification

- [ ] `python -m unittest discover -v` passes.
- [ ] CLI help and a fake-client run are reproducible with a seed.
- [ ] Real 5-node smoke passes against `qwen3:0.6b`.
- [ ] Bounded 100-node run completes and its measured timing is recorded.
- [ ] GUI launches or, if the environment has no display, GUI helper tests pass and the limitation is reported.
- [ ] `git status --short` is clean except for intentionally ignored runtime logs.
