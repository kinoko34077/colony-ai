import asyncio
import random
import unittest


class SwarmCoreTests(unittest.TestCase):
    def test_settings_have_instruction_defaults(self):
        from swarm.swarm import Settings

        settings = Settings()

        self.assertEqual(settings.model, "qwen3:0.6b")
        self.assertEqual(settings.node_count, 100)
        self.assertEqual(settings.sample_min, 1)
        self.assertEqual(settings.sample_max, 4)
        self.assertEqual(settings.max_output_chars, 30)
        self.assertEqual(settings.readout_interval, 5)
        self.assertEqual(settings.max_generations, 100)
        self.assertEqual(settings.temperature, 0.8)
        self.assertEqual(settings.num_predict, 24)
        self.assertEqual(settings.num_ctx, 2048)
        self.assertFalse(settings.think)

    def test_build_node_prompt_always_contains_full_original_prompt(self):
        from swarm.swarm import build_node_prompt

        prompt = build_node_prompt("元の問い\n全文", ["断片A", "断片B"])

        self.assertIn("【元の問い】\n元の問い\n全文", prompt)
        self.assertIn("【前世代から取得した断片】\n断片A\n断片B", prompt)

    def test_first_generation_prompt_has_no_fake_previous_fragment(self):
        from swarm.swarm import build_node_prompt

        prompt = build_node_prompt("問い", [])

        self.assertEqual(prompt, "【元の問い】\n問い")

    def test_sample_previous_is_bounded_without_replacement_and_reproducible(self):
        from swarm.swarm import sample_previous

        previous = ["a", "b", "c", "d", "e"]
        first = sample_previous(previous, random.Random(7), 1, 4)
        second = sample_previous(previous, random.Random(7), 1, 4)

        self.assertEqual(first, second)
        self.assertGreaterEqual(len(first), 1)
        self.assertLessEqual(len(first), 4)
        self.assertEqual(len(first), len(set(first)))
        self.assertTrue(set(first).issubset(previous))
        self.assertEqual(sample_previous(["only"], random.Random(1), 1, 4), ["only"])

    def test_normalize_output_keeps_one_short_meaning_unit(self):
        from swarm.swarm import normalize_output

        self.assertEqual(normalize_output("  - 需要不足が主因\n補足説明", 30), "需要不足が主因")
        self.assertEqual(normalize_output("これはとても長い出力です", 8), "これはとても長い")
        self.assertEqual(normalize_output("   ", 30), "")

    def test_run_generation_gives_every_node_the_same_previous_snapshot(self):
        from swarm.swarm import Settings, run_generation

        settings = Settings(node_count=4)
        previous = ["前世代A", "前世代B", "前世代C"]
        seen = []

        async def fake_generator(node_index, prompt, samples, generation):
            seen.append((node_index, prompt, tuple(samples)))
            return f"ノード{node_index}"

        results = asyncio.run(
            run_generation(
                "元の問い",
                previous,
                settings,
                fake_generator,
                random.Random(11),
                generation=2,
            )
        )

        self.assertEqual(len(results), 4)
        self.assertEqual([result.normalized_output for result in results], ["ノード0", "ノード1", "ノード2", "ノード3"])
        self.assertEqual(previous, ["前世代A", "前世代B", "前世代C"])
        self.assertEqual(len(seen), 4)
        for _, prompt, samples in seen:
            self.assertIn("【元の問い】\n元の問い", prompt)
            self.assertTrue(set(samples).issubset(set(previous)))
            self.assertNotIn("ノード0", prompt)

    def test_run_generation_converts_single_node_failure_to_empty_result(self):
        from swarm.swarm import Settings, run_generation

        async def failing_generator(node_index, prompt, samples, generation):
            if node_index == 1:
                raise RuntimeError("one node failed")
            return "正常出力"

        results = asyncio.run(
            run_generation(
                "問い",
                [],
                Settings(node_count=3),
                failing_generator,
                random.Random(1),
                generation=1,
            )
        )

        self.assertEqual([result.normalized_output for result in results], ["正常出力", "", "正常出力"])
        self.assertEqual(results[1].error, "one node failed")


if __name__ == "__main__":
    unittest.main()
