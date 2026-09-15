import unittest


class CliTests(unittest.TestCase):
    def test_parser_accepts_prompt_and_runtime_overrides(self):
        from swarm.swarm import build_parser

        args = build_parser().parse_args(
            [
                "--prompt",
                "問い",
                "--generations",
                "3",
                "--readout-interval",
                "2",
                "--nodes",
                "7",
                "--seed",
                "12",
                "--log",
                "logs/example.jsonl",
                "--ollama-url",
                "http://localhost:11434",
            ]
        )

        self.assertEqual(args.prompt, "問い")
        self.assertEqual(args.generations, 3)
        self.assertEqual(args.readout_interval, 2)
        self.assertEqual(args.nodes, 7)
        self.assertEqual(args.seed, 12)
        self.assertEqual(args.log, "logs/example.jsonl")
        self.assertEqual(args.ollama_url, "http://localhost:11434")

    def test_parser_supports_prompt_file(self):
        from swarm.swarm import build_parser

        args = build_parser().parse_args(["--prompt-file", "question.txt"])

        self.assertEqual(args.prompt_file, "question.txt")


if __name__ == "__main__":
    unittest.main()
