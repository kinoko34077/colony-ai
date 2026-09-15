from __future__ import annotations

import asyncio
import threading
from datetime import datetime
from pathlib import Path
from typing import Any

from .swarm import (
    FINALIZER_SYSTEM_PROMPT,
    NODE_SYSTEM_PROMPT,
    READOUT_SYSTEM_PROMPT,
    ExperimentResult,
    OllamaClient,
    Settings,
    run_experiment,
)


def settings_from_gui_values(values: dict[str, str]) -> tuple[Settings, int | None]:
    seed_text = values.get("seed", "").strip()
    seed = int(seed_text) if seed_text else None
    settings = Settings(
        model=values["model"].strip() or "qwen3:0.6b",
        node_count=int(values["nodes"]),
        max_generations=int(values["generations"]),
        readout_interval=int(values["readout_interval"]),
        ollama_url=values["ollama_url"].strip() or "http://127.0.0.1:11434",
    )
    return settings, seed


def connection_status_text(info: dict[str, Any] | None = None, error: str | None = None) -> str:
    if error:
        return f"接続失敗: {error}"
    version = (info or {}).get("version", "connected")
    return f"接続OK: Ollama {version}"


def format_generations(generations: list[list[str]]) -> str:
    sections = []
    for generation, outputs in enumerate(generations, 1):
        values = "\n".join(f"Node {index}: {output or '(空)'}" for index, output in enumerate(outputs, 1))
        sections.append(f"Generation {generation}\n{values}")
    return "\n\n".join(sections)


def format_readouts(readouts: list[str]) -> str:
    return "\n\n".join(f"Readout #{index}\n{readout}" for index, readout in enumerate(readouts, 1))


def format_result(generations: list[list[str]], readouts: list[str], final_answer: str, log_path: str) -> dict[str, str]:
    return {
        "generations": format_generations(generations),
        "readouts": format_readouts(readouts),
        "final": f"{final_answer}\n\nLog: {log_path}",
    }


class SwarmGui:
    def __init__(self, root=None):
        import tkinter as tk
        from tkinter import ttk

        self.tk = tk
        self.root = root or tk.Tk()
        self.root.title("colony-ai")
        self.root.geometry("700x560")
        self.vars = {
            "model": tk.StringVar(value="qwen3:0.6b"),
            "nodes": tk.StringVar(value="100"),
            "generations": tk.StringVar(value="100"),
            "readout_interval": tk.StringVar(value="5"),
            "ollama_url": tk.StringVar(value="http://127.0.0.1:11434"),
            "seed": tk.StringVar(value=""),
        }
        self.status_var = tk.StringVar(value="未接続")
        self.prompt = tk.Text(self.root, height=5, width=80)
        self.generation_output = tk.Text(self.root, height=18, width=42, state="disabled", wrap="word")
        self.readout_output = tk.Text(self.root, height=18, width=42, state="disabled", wrap="word")
        self.final_output = tk.Text(self.root, height=7, width=90, state="disabled", wrap="word")
        self.system_prompts = {}
        self.start_button = ttk.Button(self.root, text="実行", command=self.start)
        self.check_button = ttk.Button(self.root, text="接続確認", command=self.check_connection)
        self.live_generations: dict[int, dict[int, str]] = {}
        self.live_readouts: list[str] = []
        self._build(ttk)

    def _build(self, ttk) -> None:
        ttk.Label(self.root, text="元の問い").grid(row=0, column=0, sticky="nw", padx=8, pady=6)
        self.prompt.grid(row=0, column=1, columnspan=5, sticky="nsew", padx=8, pady=6)
        notebook = ttk.Notebook(self.root)
        for key, label, default in (
            ("node", "ノード", NODE_SYSTEM_PROMPT),
            ("readout", "Readout", READOUT_SYSTEM_PROMPT),
            ("finalizer", "Finalizer", FINALIZER_SYSTEM_PROMPT),
        ):
            frame = ttk.Frame(notebook)
            editor = self.tk.Text(frame, height=4, width=80, wrap="word")
            editor.insert("1.0", default)
            editor.pack(fill="both", expand=True)
            notebook.add(frame, text=label)
            self.system_prompts[key] = editor
        notebook.grid(row=1, column=0, columnspan=6, sticky="nsew", padx=8, pady=4)
        labels = [("model", "モデル"), ("nodes", "ノード"), ("generations", "世代"), ("readout_interval", "Readout周期"), ("seed", "seed")]
        for column, (key, label) in enumerate(labels):
            ttk.Label(self.root, text=label).grid(row=2, column=column, sticky="w", padx=8)
            ttk.Entry(self.root, textvariable=self.vars[key], width=16).grid(row=3, column=column, padx=8, pady=4)
        ttk.Label(self.root, text="Ollama URL").grid(row=4, column=0, sticky="w", padx=8)
        ttk.Entry(self.root, textvariable=self.vars["ollama_url"], width=32).grid(row=4, column=1, columnspan=2, sticky="w", padx=8)
        ttk.Label(self.root, textvariable=self.status_var).grid(row=4, column=3, sticky="w", padx=8)
        self.check_button.grid(row=4, column=5, padx=8, pady=6)
        self.start_button.grid(row=4, column=4, padx=8, pady=6)
        ttk.Label(self.root, text="各ノードの直接出力").grid(row=5, column=0, columnspan=3, sticky="w", padx=8)
        ttk.Label(self.root, text="5世代ごとの要約").grid(row=5, column=3, columnspan=3, sticky="w", padx=8)
        generation_frame = ttk.Frame(self.root)
        readout_frame = ttk.Frame(self.root)
        generation_scroll = ttk.Scrollbar(generation_frame, command=self.generation_output.yview)
        readout_scroll = ttk.Scrollbar(readout_frame, command=self.readout_output.yview)
        self.generation_output.configure(yscrollcommand=generation_scroll.set)
        self.readout_output.configure(yscrollcommand=readout_scroll.set)
        self.generation_output.grid(row=0, column=0, sticky="nsew")
        generation_scroll.grid(row=0, column=1, sticky="ns")
        readout_scroll.grid(row=0, column=1, sticky="ns")
        self.readout_output.grid(row=0, column=0, sticky="nsew")
        for frame in (generation_frame, readout_frame):
            frame.grid_columnconfigure(0, weight=1)
            frame.grid_rowconfigure(0, weight=1)
        generation_frame.grid(row=6, column=0, columnspan=3, sticky="nsew", padx=8, pady=4)
        readout_frame.grid(row=6, column=3, columnspan=3, sticky="nsew", padx=8, pady=4)
        ttk.Label(self.root, text="最終的な出力").grid(row=7, column=0, columnspan=6, sticky="w", padx=8)
        final_frame = ttk.Frame(self.root)
        final_scroll = ttk.Scrollbar(final_frame, command=self.final_output.yview)
        self.final_output.configure(yscrollcommand=final_scroll.set)
        self.final_output.grid(row=0, column=0, sticky="nsew")
        final_scroll.grid(row=0, column=1, sticky="ns")
        final_frame.grid(row=8, column=0, columnspan=6, sticky="nsew", padx=8, pady=4)
        final_frame.grid_columnconfigure(0, weight=1)
        final_frame.grid_rowconfigure(0, weight=1)
        self.root.grid_columnconfigure(1, weight=1)
        self.root.grid_columnconfigure(3, weight=1)
        self.root.grid_rowconfigure(6, weight=1)
        self.root.grid_rowconfigure(8, weight=1)

    def _set_text(self, widget, text: str) -> None:
        widget.configure(state="normal")
        widget.delete("1.0", "end")
        widget.insert("end", text)
        widget.see("end")
        widget.configure(state="disabled")

    def check_connection(self) -> None:
        url = self.vars["ollama_url"].get().strip()
        self.status_var.set("接続確認中...")

        def worker() -> None:
            try:
                info = asyncio.run(OllamaClient(url).check_connection())
                self.root.after(0, self.status_var.set, connection_status_text(info))
            except Exception as exc:
                self.root.after(0, self.status_var.set, connection_status_text(error=str(exc)))

        threading.Thread(target=worker, daemon=True).start()

    def start(self) -> None:
        try:
            values = {key: variable.get() for key, variable in self.vars.items()}
            settings, seed = settings_from_gui_values(values)
            prompt = self.prompt.get("1.0", "end").strip()
            system_prompts = {key: editor.get("1.0", "end").strip() for key, editor in self.system_prompts.items()}
            if not prompt:
                raise ValueError("元の問いを入力してください")
        except (KeyError, ValueError) as exc:
            self.status_var.set(f"入力エラー: {exc}")
            return
        log_path = Path("logs") / ("gui-" + datetime.now().strftime("%Y%m%d-%H%M%S") + ".jsonl")
        self.start_button.configure(state="disabled")
        self.check_button.configure(state="disabled")
        self.live_generations = {}
        self.live_readouts = []
        self._set_text(self.generation_output, "")
        self._set_text(self.readout_output, "")
        self._set_text(self.final_output, "")

        def worker() -> None:
            try:
                result = asyncio.run(
                    run_experiment(
                        prompt,
                        settings,
                        OllamaClient(settings.ollama_url),
                        log_path,
                        seed=seed,
                        progress_callback=lambda message: self.root.after(0, self.status_var.set, message),
                        event_callback=lambda event: self.root.after(0, self._handle_event, event),
                        node_system_prompt=system_prompts["node"],
                        readout_system_prompt=system_prompts["readout"],
                        finalizer_system_prompt=system_prompts["finalizer"],
                    )
                )
                self.root.after(0, self._finish, result, str(log_path))
            except Exception as exc:
                self.root.after(0, self._fail, str(exc))

        threading.Thread(target=worker, daemon=True).start()

    def _handle_event(self, event: dict[str, Any]) -> None:
        event_type = event.get("event")
        if event_type == "node":
            generation = int(event["generation"])
            node_index = int(event["node_index"])
            self.live_generations.setdefault(generation, {})[node_index] = event.get("normalized_output", "")
            generations = []
            for number in sorted(self.live_generations):
                nodes = self.live_generations[number]
                generations.append([nodes[index] for index in sorted(nodes)])
            self._set_text(self.generation_output, format_generations(generations))
        elif event_type == "readout":
            self.live_readouts.append(event.get("readout", ""))
            self._set_text(self.readout_output, format_readouts(self.live_readouts))
        elif event_type == "finalizer":
            self._set_text(self.final_output, event.get("final_answer", ""))

    def _finish(self, result: ExperimentResult, log_path: str) -> None:
        self.status_var.set("完了")
        rendered = format_result(result.generations, result.readouts, result.final_answer, log_path)
        self._set_text(self.generation_output, rendered["generations"])
        self._set_text(self.readout_output, rendered["readouts"])
        self._set_text(self.final_output, rendered["final"])
        self.start_button.configure(state="normal")
        self.check_button.configure(state="normal")

    def _fail(self, message: str) -> None:
        self.status_var.set(f"実行失敗: {message}")
        self.start_button.configure(state="normal")
        self.check_button.configure(state="normal")


def main() -> int:
    app = SwarmGui()
    app.root.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
