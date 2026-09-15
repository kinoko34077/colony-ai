from __future__ import annotations

import asyncio
import inspect
import random
import re
from dataclasses import dataclass, field
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
        if logger is not None:
            logger.write(
                {
                    "event": "node",
                    "generation": generation,
                    "node_index": node_index,
                    "sampled_previous_outputs": list(samples),
                    "raw_output": result.raw_output,
                    "normalized_output": result.normalized_output,
                    "error": result.error,
                }
            )
        return result

    return await asyncio.gather(*(run_node(index) for index in range(settings.node_count)))
