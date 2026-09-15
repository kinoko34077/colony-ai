import unittest


class GuiHelperTests(unittest.TestCase):
    def test_settings_from_gui_values_converts_text_fields(self):
        from swarm.gui import settings_from_gui_values

        settings, seed = settings_from_gui_values(
            {
                "model": "qwen3:0.6b",
                "nodes": "5",
                "generations": "2",
                "readout_interval": "2",
                "ollama_url": "http://localhost:11434",
                "seed": "7",
            }
        )

        self.assertEqual(settings.node_count, 5)
        self.assertEqual(settings.max_generations, 2)
        self.assertEqual(settings.readout_interval, 2)
        self.assertEqual(settings.model, "qwen3:0.6b")
        self.assertEqual(settings.ollama_url, "http://localhost:11434")
        self.assertEqual(seed, 7)

    def test_blank_seed_is_none(self):
        from swarm.gui import settings_from_gui_values

        _, seed = settings_from_gui_values(
            {"model": "qwen3:0.6b", "nodes": "1", "generations": "1", "readout_interval": "1", "ollama_url": "http://localhost:11434", "seed": ""}
        )

        self.assertIsNone(seed)

    def test_connection_status_and_result_are_compact(self):
        from swarm.gui import connection_status_text, format_result

        self.assertEqual(connection_status_text({"version": "0.33.3"}), "接続OK: Ollama 0.33.3")
        self.assertEqual(connection_status_text(error="offline"), "接続失敗: offline")
        self.assertIn("最終回答", format_result(["観測A"], "最終回答", "logs/run.jsonl"))
        self.assertIn("観測A", format_result(["観測A"], "最終回答", "logs/run.jsonl"))


if __name__ == "__main__":
    unittest.main()
