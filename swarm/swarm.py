from __future__ import annotations

import asyncio
import argparse
import json
import inspect
import random
import re
import sys
import time
import urllib.error
import urllib.request
from dataclasses import asdict, replace
from pathlib import Path
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Awaitable, Callable, Protocol, Sequence


NODE_SYSTEM_PROMPT = """元の問いと与えられた断片をもとに、問いへの思考を進める新しい内容を1つだけ出力せよ。

既存内容の補強・修正・反論・接続・別案の提示など、最も自然な続きを自由に生成してよい。
単なる言い換えや不要な反復は避ける。

出力は1つの短い意味単位のみとし、説明・前置き・箇条書き・ラベルを付けない。"""


@dataclass(frozen=True)
class Settings:
    model: str = "qwen3:0.6b"
    node_count: int = 100
    sample_min: int = 1
    sample_max: int = 4
    max_output_chars: int = 30
    readout_interval: int = 5
    max_generations: int = 100
    temperature: float = 0.8
    num_predict: int = 24
    num_ctx: int = 2048
    think: bool = False
    keep_alive: int = -1
    ollama_url: str = "http://127.0.0.1:11434"
    readout_max_chars: int | None = None
    finalizer_max_chars: int | None = None

    def __post_init__(self) -> None:
        if self.node_count < 1:
            raise ValueError("node_count must be positive")
        if self.max_generations < 1:
            raise ValueError("max_generations must be positive")
        if self.readout_interval < 1:
            raise ValueError("readout_interval must be positive")
        if self.sample_min < 0 or self.sample_max < self.sample_min:
            raise ValueError("sample range is invalid")
        if self.max_output_chars < 1:
            raise ValueError("max_output_chars must be positive")
        if self.readout_max_chars is not None and self.readout_max_chars < 1:
            raise ValueError("readout_max_chars must be positive when set")
        if self.finalizer_max_chars is not None and self.finalizer_max_chars < 1:
            raise ValueError("finalizer_max_chars must be positive when set")


@dataclass(frozen=True)
class NodeResult:
    node_index: int
    sampled_previous_outputs: tuple[str, ...]
    raw_output: str
    normalized_output: str
    error: str | None = None
    metadata: dict[str, Any] = field(default_factory=dict)


class EventLogger(Protocol):
    def write(self, event: dict[str, Any]) -> None:
        ...


NodeGenerator = Callable[[int, str, Sequence[str], int], Awaitable[str] | str]


@dataclass(frozen=True)
class GenerationResponse:
    content: str
    metadata: dict[str, Any] = field(default_factory=dict)


class GeneratorClient(Protocol):
    async def generate(
        self,
        system_prompt: str,
        user_prompt: str,
        settings: Settings,
        max_chars: int | None = None,
    ) -> GenerationResponse:
        ...


def sample_previous(
    previous: Sequence[str],
    rng: random.Random,
    minimum: int,
    maximum: int,
) -> list[str]:
    """Select a bounded, non-repeating sample from one prior generation."""
    if not previous:
        return []
    if minimum < 0 or maximum < minimum:
        raise ValueError("sample range is invalid")
    upper = min(maximum, len(previous))
    lower = min(minimum, upper)
    count = rng.randint(lower, upper)
    return rng.sample(list(previous), count)


def build_node_prompt(original_prompt: str, samples: Sequence[str]) -> str:
    """Build the only user context visible to a swarm node."""
    prompt = f"【元の問い】\n{original_prompt}"
    if samples:
        prompt += "\n\n【前世代から取得した断片】\n" + "\n".join(samples)
    return prompt


def normalize_output(raw: str, max_chars: int) -> str:
    """Reduce model text to one short meaning unit."""
    if not raw:
        return ""
    first_line = next((line.strip() for line in raw.strip().splitlines() if line.strip()), "")
    first_line = re.sub(r"^(?:[-*・]|\d+[.)])\s*", "", first_line).strip()
    return first_line[:max_chars]


async def _maybe_await(value: Awaitable[str] | str) -> str:
    if inspect.isawaitable(value):
        return await value
    return value


async def run_generation(
    original_prompt: str,
    previous_generation: Sequence[str],
    settings: Settings,
    node_generator: NodeGenerator,
    rng: random.Random,
    generation: int,
    logger: EventLogger | None = None,
    event_callback: Callable[[dict[str, Any]], None] | None = None,
) -> list[NodeResult]:
    """Generate one synchronized generation from an immutable prior snapshot."""
    previous_snapshot = tuple(previous_generation)

    async def run_node(node_index: int) -> NodeResult:
        samples = tuple(
            sample_previous(
                previous_snapshot,
                rng,
                settings.sample_min,
                settings.sample_max,
            )
        )
        prompt = build_node_prompt(original_prompt, samples)
        try:
            raw_output = await _maybe_await(node_generator(node_index, prompt, samples, generation))
            if not isinstance(raw_output, str):
                raw_output = str(raw_output)
            error = None
        except Exception as exc:  # A single weak node must not kill the generation.
            raw_output = ""
            error = str(exc)
        result = NodeResult(
            node_index=node_index,
            sampled_previous_outputs=samples,
            raw_output=raw_output,
            normalized_output=normalize_output(raw_output, settings.max_output_chars),
            error=error,
        )
        event = {
            "event": "node",
            "generation": generation,
            "node_index": node_index,
            "sampled_previous_outputs": list(samples),
            "raw_output": result.raw_output,
            "normalized_output": result.normalized_output,
            "error": result.error,
        }
        if logger is not None:
            logger.write(event)
        if event_callback is not None:
            event_callback(event)
        return result

    return await asyncio.gather(*(run_node(index) for index in range(settings.node_count)))


class JsonlLogger:
    """Append-only experiment event logger."""

    def __init__(self, path: Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)

    def write(self, event: dict[str, Any]) -> None:
        with self.path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(event, ensure_ascii=False) + "\n")


class OllamaClient:
    """Small async wrapper around Ollama's local chat API."""

    def __init__(self, base_url: str = "http://127.0.0.1:11434", max_concurrency: int = 1):
        if max_concurrency < 1:
            raise ValueError("max_concurrency must be positive")
        self.base_url = base_url.rstrip("/")
        self._semaphore = asyncio.Semaphore(max_concurrency)

    async def check_connection(self) -> dict[str, Any]:
        return await asyncio.to_thread(self._request_json, "GET", "/api/version", None)

    async def generate(
        self,
        system_prompt: str,
        user_prompt: str,
        settings: Settings,
        max_chars: int | None = None,
    ) -> GenerationResponse:
        payload = {
            "model": settings.model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "stream": False,
            "think": settings.think,
            "keep_alive": settings.keep_alive,
            "options": {
                "temperature": settings.temperature,
                "num_predict": settings.num_predict,
                "num_ctx": settings.num_ctx,
            },
        }
        async with self._semaphore:
            response = await asyncio.to_thread(self._request_json, "POST", "/api/chat", payload)
        message = response.get("message") or {}
        content = message.get("content", "")
        if max_chars is not None:
            content = content.strip()[:max_chars]
        metadata = {
            key: response[key]
            for key in ("total_duration", "load_duration", "prompt_eval_count", "eval_count")
            if key in response
        }
        return GenerationResponse(content=content, metadata=metadata)

    def _request_json(self, method: str, path: str, payload: dict[str, Any] | None) -> dict[str, Any]:
        body = None if payload is None else json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(
            self.base_url + path,
            data=body,
            method=method,
            headers={"Content-Type": "application/json"} if body is not None else {},
        )
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"Ollama HTTP {exc.code}: {detail}") from exc
        except urllib.error.URLError as exc:
            raise RuntimeError(f"Ollama connection failed: {exc.reason}") from exc


@dataclass
class ExperimentResult:
    generations: list[list[str]]
    readouts: list[str]
    final_answer: str
    timings: dict[str, Any]


def readout_prompt(original_prompt: str, recent_generations: Sequence[Sequence[str]]) -> str:
    sections = [f"Generation {index}:\n" + "\n".join(values) for index, values in enumerate(recent_generations, 1)]
    return "【元の問い】\n" + original_prompt + "\n\n" + "\n\n".join(sections)


def finalizer_prompt(original_prompt: str, readouts: Sequence[str]) -> str:
    records = "\n\n".join(f"Readout #{index}\n{value}" for index, value in enumerate(readouts, 1))
    return "【元の問い】\n" + original_prompt + "\n\n【観測記録】\n" + records


READOUT_SYSTEM_PROMPT = """以下は同じ問いについて生成された群体AIの直近5世代分の出力である。

この5世代で現れている主要な思考内容、変化、現在残っている有力な考えを簡潔にまとめよ。

新しい推論を追加せず、与えられた内容の観測・要約に限定せよ。"""

FINALIZER_SYSTEM_PROMPT = """以下は一つの問いについて継続的に行われた群体推論の観測記録である。

観測記録全体を踏まえて、元の問いへの最終的な回答を構成せよ。
途中経過を単に列挙するのではなく、最終的に成立している内容を統合して答えよ。"""


async def run_experiment(
    original_prompt: str,
    settings: Settings,
    client: GeneratorClient,
    log_path: Path,
    seed: int | None = None,
    progress_callback: Callable[[str], None] | None = None,
    event_callback: Callable[[dict[str, Any]], None] | None = None,
    node_system_prompt: str | None = None,
    readout_system_prompt: str | None = None,
    finalizer_system_prompt: str | None = None,
) -> ExperimentResult:
    """Run synchronized generations, readouts, and the final synthesis."""
    if not original_prompt.strip():
        raise ValueError("original_prompt must not be empty")
    logger = JsonlLogger(log_path)
    rng = random.Random(seed)
    observer_settings = replace(settings, num_ctx=max(settings.num_ctx, 8192))
    node_system_prompt = node_system_prompt or NODE_SYSTEM_PROMPT
    readout_system_prompt = readout_system_prompt or READOUT_SYSTEM_PROMPT
    finalizer_system_prompt = finalizer_system_prompt or FINALIZER_SYSTEM_PROMPT
    started = time.perf_counter()
    logger.write({"event": "run", "settings": asdict(settings), "random_seed": seed})
    generations: list[list[str]] = []
    readouts: list[str] = []
    generation_elapsed: list[float] = []
    previous_generation: list[str] = []

    async def node_generator(node_index: int, prompt: str, samples: Sequence[str], generation: int) -> str:
        response = await client.generate(node_system_prompt, prompt, settings, settings.max_output_chars)
        if not response.content.strip():
            response = await client.generate(node_system_prompt, prompt, settings, settings.max_output_chars)
        return response.content

    for generation in range(1, settings.max_generations + 1):
        if progress_callback is not None:
            progress_callback(f"Generation {generation}/{settings.max_generations}")
        generation_started = time.perf_counter()
        results = await run_generation(
            original_prompt,
            tuple(previous_generation),
            settings,
            node_generator,
            rng,
            generation,
            logger,
            event_callback,
        )
        current_generation = [result.normalized_output for result in results]
        generations.append(current_generation)
        previous_generation = list(current_generation)
        elapsed = time.perf_counter() - generation_started
        generation_elapsed.append(elapsed)
        generation_event = {
            "event": "generation",
            "generation": generation,
            "outputs": list(current_generation),
            "elapsed_seconds": elapsed,
        }
        if event_callback is not None:
            event_callback(generation_event)
        if generation % settings.readout_interval == 0:
            recent = generations[-settings.readout_interval :]
            response = await client.generate(
                readout_system_prompt,
                readout_prompt(original_prompt, recent),
                observer_settings,
                settings.readout_max_chars,
            )
            readout = response.content.strip()
            readouts.append(readout)
            readout_event = {
                "event": "readout",
                "generation_start": generation - len(recent) + 1,
                "generation_end": generation,
                "readout": readout,
                "metadata": response.metadata,
            }
            logger.write(readout_event)
            if event_callback is not None:
                event_callback(readout_event)
            if progress_callback is not None:
                progress_callback(f"=== READOUT {generation - len(recent) + 1}-{generation} ===\n{readout}")

    final_response = await client.generate(
        finalizer_system_prompt,
        finalizer_prompt(original_prompt, readouts),
        observer_settings,
        settings.finalizer_max_chars,
    )
    final_answer = final_response.content.strip()
    finalizer_event = {"event": "finalizer", "final_answer": final_answer, "metadata": final_response.metadata}
    logger.write(finalizer_event)
    if event_callback is not None:
        event_callback(finalizer_event)
    timings = {
        "total_elapsed_seconds": time.perf_counter() - started,
        "generation_elapsed_seconds": generation_elapsed,
        "node_count": settings.node_count,
        "generation_count": settings.max_generations,
        "model": settings.model,
    }
    logger.write({"event": "complete", "timings": timings})
    return ExperimentResult(generations, readouts, final_answer, timings)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Synchronized recursive LLM swarm using local Ollama")
    parser.add_argument("--prompt", help="original question")
    parser.add_argument("--prompt-file", help="UTF-8 file containing the original question")
    parser.add_argument("--generations", type=int, default=100)
    parser.add_argument("--nodes", type=int, default=100)
    parser.add_argument("--readout-interval", type=int, default=5)
    parser.add_argument("--seed", type=int)
    parser.add_argument("--log", default=None, help="JSONL log path")
    parser.add_argument("--ollama-url", default="http://127.0.0.1:11434")
    return parser


def _prompt_from_args(parser: argparse.ArgumentParser, args: argparse.Namespace) -> str:
    if args.prompt and args.prompt_file:
        parser.error("--prompt and --prompt-file cannot be used together")
    if args.prompt_file:
        try:
            prompt = Path(args.prompt_file).read_text(encoding="utf-8")
        except OSError as exc:
            parser.error(f"cannot read --prompt-file: {exc}")
    elif args.prompt:
        prompt = args.prompt
    else:
        parser.error("one of --prompt or --prompt-file is required")
    if not prompt.strip():
        parser.error("prompt must not be empty")
    return prompt


async def _run_cli(args: argparse.Namespace, prompt: str) -> int:
    client = OllamaClient(args.ollama_url)
    connection = await client.check_connection()
    print(f"Ollama: {connection.get('version', 'connected')}")
    settings = Settings(
        node_count=args.nodes,
        max_generations=args.generations,
        readout_interval=args.readout_interval,
        ollama_url=args.ollama_url,
    )
    log_path = Path(args.log) if args.log else Path("logs") / (
        "swarm-" + datetime.now().strftime("%Y%m%d-%H%M%S") + ".jsonl"
    )
    result = await run_experiment(prompt, settings, client, log_path, seed=args.seed, progress_callback=print)
    print(f"Log: {log_path}")
    print("=== FINAL ANSWER ===")
    print(result.final_answer)
    print(f"Elapsed: {result.timings['total_elapsed_seconds']:.2f}s")
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    prompt = _prompt_from_args(parser, args)
    try:
        return asyncio.run(_run_cli(args, prompt))
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
