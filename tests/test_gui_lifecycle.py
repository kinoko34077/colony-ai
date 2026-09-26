import asyncio
import json
import tempfile
import unittest
from pathlib import Path


class FastClient:
    async def generate(self, system_prompt, user_prompt, settings, max_chars=None):
        from swarm.swarm import GenerationResponse

        return GenerationResponse(content="短文")


class FakeRoot:
    def __init__(self):
        self.after_calls = []

    def after(self, delay, callback, *args):
        self.after_calls.append((delay, callback, args))


class FakeText:
    def __init__(self, yview=(0.0, 1.0)):
        self._yview = yview
        self.text = ""
        self.state = "disabled"
        self.see_calls = 0

    def yview(self):
        return self._yview

    def configure(self, **kwargs):
        if "state" in kwargs:
            self.state = kwargs["state"]

    def insert(self, index, text):
        self.text += text

    def delete(self, start, end):
        self.text = ""

    def see(self, index):
        self.see_calls += 1


class FakeControl:
    def __init__(self):
        self.state = "normal"

    def configure(self, **kwargs):
        if "state" in kwargs:
            self.state = kwargs["state"]


class GuiLifecycleTests(unittest.TestCase):
    def test_run_experiment_cancels_at_generation_boundary_and_logs_cancelled(self):
        from swarm.swarm import ExperimentCancelled, Settings, run_experiment

        cancel_requested = False

        def on_event(event):
            nonlocal cancel_requested
            if event.get("event") == "generation":
                cancel_requested = True

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cancel.jsonl"
            with self.assertRaises(ExperimentCancelled):
                asyncio.run(
                    run_experiment(
                        "問い",
                        Settings(node_count=2, max_generations=3, readout_interval=3),
                        FastClient(),
                        path,
                        event_callback=on_event,
                        cancel_requested=lambda: cancel_requested,
                    )
                )
            events = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]

        self.assertEqual(len([event for event in events if event["event"] == "node"]), 2)
        self.assertEqual(events[-1]["event"], "cancelled")
        self.assertNotIn("finalizer", {event["event"] for event in events})
        self.assertNotIn("complete", {event["event"] for event in events})

    def test_node_events_do_not_queue_one_tk_callback_per_node(self):
        from swarm.gui import SwarmGui

        gui = SwarmGui.__new__(SwarmGui)
        gui.root = FakeRoot()
        gui._handle_event = lambda event: None

        for node_index in range(100):
            gui._queue_event({"event": "node", "generation": 1, "node_index": node_index})
        gui._queue_event({"event": "generation", "generation": 1, "outputs": ["x"] * 100})

        self.assertEqual(len(gui.root.after_calls), 1)
        self.assertEqual(gui.root.after_calls[0][2][0]["event"], "generation")

    def test_live_append_only_follows_when_user_is_at_bottom(self):
        from swarm.gui import SwarmGui

        gui = SwarmGui.__new__(SwarmGui)
        scrolled_back = FakeText((0.1, 0.7))
        at_bottom = FakeText((0.3, 1.0))

        gui._append_text(scrolled_back, "Generation 1")
        gui._append_text(at_bottom, "Generation 1")

        self.assertEqual(scrolled_back.text, "Generation 1")
        self.assertEqual(scrolled_back.see_calls, 0)
        self.assertEqual(at_bottom.see_calls, 1)

    def test_running_state_freezes_captured_configuration_and_enables_stop(self):
        from swarm.gui import SwarmGui

        gui = SwarmGui.__new__(SwarmGui)
        gui.config_widgets = [FakeControl(), FakeControl(), FakeControl()]
        gui.start_button = FakeControl()
        gui.check_button = FakeControl()
        gui.stop_button = FakeControl()

        gui._set_running_state(True)
        self.assertTrue(all(widget.state == "disabled" for widget in gui.config_widgets))
        self.assertEqual(gui.start_button.state, "disabled")
        self.assertEqual(gui.check_button.state, "disabled")
        self.assertEqual(gui.stop_button.state, "normal")

        gui._set_running_state(False)
        self.assertTrue(all(widget.state == "normal" for widget in gui.config_widgets))
        self.assertEqual(gui.start_button.state, "normal")
        self.assertEqual(gui.check_button.state, "normal")
        self.assertEqual(gui.stop_button.state, "disabled")


if __name__ == "__main__":
    unittest.main()
