# Project Specification

Status: active — Repository Base v0.3.7 Canary adoption

## Purpose

`colony-ai` runs repeated generations of small LLM nodes from a shared Python
core. CLI and Tkinter GUI are Surface entry points; Ollama access and experiment
semantics remain Project-owned.

## Requirements / Acceptance

1. `knt doctor` validates the repository manifest and Base boundary.
2. `knt verify` reaches the standard-library unit tests without requiring Ollama.
3. CLI and GUI continue to use the same swarm implementation.
4. Ollama-dependent smoke remains explicit and is not part of the default unit gate.

## Inputs

Prompt, generation count, node count, seed, model, and Ollama URL as defined by
the existing CLI/GUI.

## Outputs

Console progress, JSONL logs, Readout, and Finalizer output as defined by the
existing Project implementation.

## Behavior

The CLI and GUI validate experiment settings, invoke the shared swarm runner,
stream progress/readout information, and persist JSONL logs. Invalid local
settings fail at the entry point; Ollama transport failures remain visible as
Project-level run errors.

## State / Ownership / Lifetime

The swarm runner owns generation state for one invocation. JSONL logs are
Project-owned outputs; the Repository Base owns only repository structure and
verification entry points.

## Constraints

Python 3.11 or later is required. Ollama must be available for live runs, but
it is not required for unit tests.

## Exceptions / Fallback

Unit tests use no external fallback. Live Ollama failures are reported by the
existing runner and do not silently become a successful verification result.

## Compatibility

Keep the existing CLI module invocation, GUI module invocation, JSONL log shape,
and standard-library-only dependency boundary compatible.

## Implementation Boundary

Keep project-specific behavior in project/**. Keep common behavior in .kinotch/**.

## Tests

`python -m unittest discover -v` is the project test command and is exposed
through `knt verify`; `scripts/smoke_ollama.ps1` remains an explicit live smoke.
