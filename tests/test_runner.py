import asyncio
import json
import tempfile
import unittest
from pathlib import Path


class FakeClient:
    def __init__(self):
        self.calls = []
        self.node_number = 0

    async def generate(self, system_prompt, user_prompt, settings, max_chars=None):
        self.calls.append((system_prompt, user_prompt, max_chars))
        if "直近5世代分" in system_prompt:
            return type("Response", (), {"content": "観測された変化", "metadata": {"eval_count": 3}})()
        if "観測記録全体" in system_prompt:
            return type("Response", (), {"content": "最終回答", "metadata": {"eval_count": 4}})()
        self.node_number += 1
        return type("Response", (), {"content": f"ノード{self.node_number}", "metadata": {"eval_count": 1}})()


class MemoryLogger:
    def __init__(self):
        self.events = []

    def write(self, event):
        self.events.append(event)


class RunnerTests(unittest.TestCase):
    def test_run_experiment_transitions_generations_and_keeps_readout_out_of_node_prompts(self):
        from swarm.swarm import Settings, run_experiment

        client = FakeClient()
        with tempfile.TemporaryDirectory() as directory:
            result = asyncio.run(
                run_experiment(
                    "元の問い",
                    Settings(node_count=2, max_generations=3, readout_interval=2),
                    client,
                    Path(directory) / "run.jsonl",
                    seed=7,
                )
            )

        self.assertEqual(len(result.generations), 3)
        self.assertEqual([len(g) for g in result.generations], [2, 2, 2])
        self.assertEqual(len(result.readouts), 1)
        self.assertEqual(result.final_answer, "最終回答")
        node_prompts = [user for system, user, _ in client.calls if "観測記録全体" not in system and "直近5世代分" not in system]
        self.assertTrue(node_prompts)
        self.assertTrue(all("観測された変化" not in prompt for prompt in node_prompts))

    def test_finalizer_receives_original_prompt_and_all_readouts(self):
        from swarm.swarm import Settings, run_experiment

        client = FakeClient()
        with tempfile.TemporaryDirectory() as directory:
            asyncio.run(
                run_experiment(
                    "問いを保持",
                    Settings(node_count=1, max_generations=4, readout_interval=2),
                    client,
                    Path(directory) / "run.jsonl",
                    seed=1,
                )
            )

        finalizer_calls = [call for call in client.calls if "観測記録全体" in call[0]]
        self.assertEqual(len(finalizer_calls), 1)
        self.assertIn("問いを保持", finalizer_calls[0][1])
        self.assertEqual(finalizer_calls[0][1].count("観測された変化"), 2)

    def test_jsonl_contains_run_node_readout_finalizer_and_completion_events(self):
        from swarm.swarm import Settings, run_experiment

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "run.jsonl"
            asyncio.run(run_experiment("問い", Settings(node_count=1, max_generations=1, readout_interval=1), FakeClient(), path, seed=3))
            events = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]

        self.assertEqual(events[0]["event"], "run")
        self.assertIn("node", {event["event"] for event in events})
        self.assertIn("readout", {event["event"] for event in events})
        self.assertIn("finalizer", {event["event"] for event in events})
        self.assertEqual(events[-1]["event"], "complete")


if __name__ == "__main__":
    unittest.main()
