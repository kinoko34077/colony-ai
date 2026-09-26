# Current State

Base version: `0.3.8`

Last verified: 2026-09-27 — GUI long-run lifecycle maintenance

## Implemented

- Repository-local KiNoTch Base v0.3.8 and Project Overlay
- CLI and Windows GUI Surface declarations
- Existing swarm, scripts, tests, logs, and docs directories retained
- Structured Python setup, GUI development, and unittest verification commands
- Cooperative GUI cancellation at synchronized generation boundaries with a durable JSONL `cancelled` event
- GUI Stop control and frozen captured run configuration while an experiment is active
- Generation-level live UI updates instead of one Tk callback/full-history rewrite per node
- Conditional output auto-follow: manual scrollback is preserved unless the view was already at the bottom

## Default state

- `cli`: `OVERRIDE` — existing Python CLI is authoritative
- `windows`: `OVERRIDE` — existing Tkinter GUI is authoritative

## Known issues

- Ollama availability and model installation are required only for the external
  smoke script; unit tests do not call Ollama.

## Current constraints

- Runtime modules are logical declarations until Runtime implementation is connected.
- GUI Stop is cooperative: an in-flight synchronized generation is allowed to finish before cancellation is committed, so node/generation semantics are not interrupted mid-generation.
- Real Ollama latency/service behavior remains an external-runtime smoke boundary; deterministic GUI lifecycle tests use synthetic clients/events.

## Next work

1. Preserve the existing CLI and GUI as Project-owned overrides.
2. Consider a separate Ollama smoke gate only when the local service is available.

## Verification

- `knt doctor`
- `knt base-check`
- `knt setup`
- `knt verify`
- `python -m unittest discover -v`
- `tests/test_gui_lifecycle.py` covers cancellation, Tk event coalescing, conditional auto-follow and active-run configuration state.
