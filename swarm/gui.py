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
    ExperimentCancelled,
    ExperimentResult,
    OllamaClient,
    Settings,
    run_experiment,
)


def settings_from_gui_values(values: dict[str, str]) -> tuple[Settings, int | None]:
    seed_text = values.get("seed", "").strip()
    seed = int(seed_text) if seed_text else None
    readout_limit = values.get("readout_max_chars", "").strip()
    finalizer_limit = values.get("finalizer_max_chars", "").strip()
    settings = Settings(
        model=values["model"].strip() or "qwen3:0.6b",
        node_count=int(values["nodes"]),
        max_generations=int(values["generations"]),
        readout_interval=int(values["readout_interval"]),
        ollama_url=values["ollama_url"].strip() or "http://127.0.0.1:11434",
        readout_max_chars=int(readout_limit) if readout_limit else None,
        finalizer_max_chars=int(finalizer_limit) if finalizer_limit else None,
    )
    return settings, seed


def connection_status_text(info: dict[str, Any] | None = None, error: str | None = None) -> str:
    if error:
        return f"接続失敗: {error}"
    version = (info or {}).get("version", "connected")
    return f"接続OK: Ollama {version}"


def format_generation(generation: int, outputs: list[str]) -> str:
    values = "\n".join(f"Node {index}: {output or '(空)'}" for index, output in enumerate(outputs, 1))
    return f"Generation {generation}\n{values}"


def format_generations(generations: list[list[str]]) -> str:
    return "\n\n".join(format_generation(generation, outputs) for generation, outputs in enumerate(generations, 1))


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
        self.root.geometry("760x680")
        self.vars = {
            "model": tk.StringVar(value="qwen3:0.6b"),
            "nodes": tk.StringVar(value="100"),
            "generations": tk.StringVar(value="100"),
            "readout_interval": tk.StringVar(value="5"),
            "ollama_url": tk.StringVar(value="http://127.0.0.1:11434"),
            "seed": tk.StringVar(value=""),
            "readout_max_chars": tk.StringVar(value=""),
            "finalizer_max_chars": tk.StringVar(value=""),
        }
        self.status_var = tk.StringVar(value="未接続")
        self.prompt = tk.Text(self.root, height=5, width=80)
        self.generation_output = tk.Text(self.root, height=18, width=42, state="disabled", wrap="word")
        self.readout_output = tk.Text(self.root, height=18, width=42, state="disabled", wrap="word")
        self.final_output = tk.Text(self.root, height=7, width=90, state="disabled", wrap="word")
        self.system_prompts = {}
        self.config_widgets = [self.prompt]
        self.cancel_event = threading.Event()
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
            self.config_widgets.append(editor)
        notebook.grid(row=1, column=0, columnspan=6, sticky="nsew", padx=8, pady=4)

        labels = [("model", "モデル"), ("nodes", "ノード"), ("generations", "世代"), ("readout_interval", "Readout周期"), ("seed", "seed")]
        for column, (key, label) in enumerate(labels):
            ttk.Label(self.root, text=label).grid(row=2, column=column, sticky="w", padx=8)
            entry = ttk.Entry(self.root, textvariable=self.vars[key], width=16)
            entry.grid(row=3, column=column, padx=8, pady=4)
            self.config_widgets.append(entry)

        ttk.Label(self.root, text="Readout文字数上限").grid(row=4, column=0, sticky="w", padx=8)
        readout_limit_entry = ttk.Entry(self.root, textvariable=self.vars["readout_max_chars"], width=12)
        readout_limit_entry.grid(row=4, column=1, padx=8)
        self.config_widgets.append(readout_limit_entry)
        ttk.Label(self.root, text="Finalizer文字数上限").grid(row=4, column=2, sticky="w", padx=8)
        finalizer_limit_entry = ttk.Entry(self.root, textvariable=self.vars["finalizer_max_chars"], width=12)
        finalizer_limit_entry.grid(row=4, column=3, padx=8)
        self.config_widgets.append(finalizer_limit_entry)
        ttk.Label(self.root, text="空欄=制限なし").grid(row=4, column=4, sticky="w", padx=8)

        ttk.Label(self.root, text="Ollama URL").grid(row=5, column=0, sticky="w", padx=8)
        ollama_entry = ttk.Entry(self.root, textvariable=self.vars["ollama_url"], width=32)
        ollama_entry.grid(row=5, column=1, columnspan=2, sticky="w", padx=8)
        self.config_widgets.append(ollama_entry)
        ttk.Label(self.root, textvariable=self.status_var).grid(row=5, column=3, sticky="w", padx=8)

        action_frame = ttk.Frame(self.root)
        action_frame.grid(row=5, column=4, columnspan=2, sticky="e", padx=8, pady=6)
        self.start_button = ttk.Button(action_frame, text="実行", command=self.start)
        self.stop_button = ttk.Button(action_frame, text="停止", command=self.stop, state="disabled")
        self.check_button = ttk.Button(action_frame, text="接続確認", command=self.check_connection)
        self.start_button.pack(side="left", padx=2)
        self.stop_button.pack(side="left", padx=2)
        self.check_button.pack(side="left", padx=2)

        ttk.Label(self.root, text="各ノードの直接出力").grid(row=6, column=0, columnspan=3, sticky="w", padx=8)
        ttk.Label(self.root, text="5世代ごとの要約").grid(row=6, column=3, columnspan=3, sticky="w", padx=8)
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
        generation_frame.grid(row=7, column=0, columnspan=3, sticky="nsew", padx=8, pady=4)
        readout_frame.grid(row=7, column=3, columnspan=3, sticky="nsew", padx=8, pady=4)
        ttk.Label(self.root, text="最終的な出力").grid(row=8, column=0, columnspan=6, sticky="w", padx=8)
        final_frame = ttk.Frame(self.root)
        final_scroll = ttk.Scrollbar(final_frame, command=self.final_output.yview)
        self.final_output.configure(yscrollcommand=final_scroll.set)
        self.final_output.grid(row=0, column=0, sticky="nsew")
        final_scroll.grid(row=0, column=1, sticky="ns")
        final_frame.grid(row=9, column=0, columnspan=6, sticky="nsew", padx=8, pady=4)
        final_frame.grid_columnconfigure(0, weight=1)
        final_frame.grid_rowconfigure(0, weight=1)
        self.root.grid_columnconfigure(1, weight=1)
        self.root.grid_columnconfigure(3, weight=1)
        self.root.grid_rowconfigure(7, weight=1)
        self.root.grid_rowconfigure(9, weight=1)

    @staticmethod
    def _is_at_bottom(widget) -> bool:
        try:
            return widget.yview()[1] >= 0.999
        except Exception:
            return True

    def _set_text(self, widget, text: str) -> None:
        follow_latest = self._is_at_bottom(widget)
        widget.configure(state="normal")
        widget.delete("1.0", "end")
        widget.insert("end", text)
        if follow_latest:
            widget.see("end")
        widget.configure(state="disabled")

    def _append_text(self, widget, text: str) -> None:
        follow_latest = self._is_at_bottom(widget)
        widget.configure(state="normal")
        widget.insert("end", text)
        if follow_latest:
            widget.see("end")
        widget.configure(state="disabled")

    def _set_running_state(self, running: bool) -> None:
        config_state = "disabled" if running else "normal"
        for widget in self.config_widgets:
            widget.configure(state=config_state)
        self.start_button.configure(state="disabled" if running else "normal")
        self.check_button.configure(state="disabled" if running else "normal")
        self.stop_button.configure(state="normal" if running else "disabled")

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
        self.cancel_event.clear()
        self._set_running_state(True)
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
                        event_callback=self._queue_event,
                        node_system_prompt=system_prompts["node"],
                        readout_system_prompt=system_prompts["readout"],
                        finalizer_system_prompt=system_prompts["finalizer"],
                        cancel_requested=self.cancel_event.is_set,
                    )
                )
                self.root.after(0, self._finish, result, str(log_path))
            except ExperimentCancelled:
                self.root.after(0, self._cancelled, str(log_path))
            except Exception as exc:
                self.root.after(0, self._fail, str(exc))

        threading.Thread(target=worker, daemon=True).start()

    def stop(self) -> None:
        self.cancel_event.set()
        self.status_var.set("停止要求中... 現在の世代完了後に停止します")
        self.stop_button.configure(state="disabled")

    def _queue_event(self, event: dict[str, Any]) -> None:
        if event.get("event") == "node":
            return
        self.root.after(0, self._handle_event, event)

    def _handle_event(self, event: dict[str, Any]) -> None:
        event_type = event.get("event")
        if event_type == "generation":
            generation = int(event["generation"])
            outputs = list(event.get("outputs") or [])
            self.live_generations[generation] = {index: output for index, output in enumerate(outputs)}
            self._append_text(self.generation_output, format_generation(generation, outputs) + "\n\n")
        elif event_type == "readout":
            readout = event.get("readout", "")
            self.live_readouts.append(readout)
            self._append_text(self.readout_output, f"Readout #{len(self.live_readouts)}\n{readout}\n\n")
        elif event_type == "finalizer":
            self._set_text(self.final_output, event.get("final_answer", ""))

    def _finish(self, result: ExperimentResult, log_path: str) -> None:
        self.status_var.set("完了")
        rendered = format_result(result.generations, result.readouts, result.final_answer, log_path)
        self._set_text(self.generation_output, rendered["generations"])
        self._set_text(self.readout_output, rendered["readouts"])
        self._set_text(self.final_output, rendered["final"])
        self._set_running_state(False)

    def _cancelled(self, log_path: str) -> None:
        self.status_var.set("停止しました")
        self._append_text(self.final_output, f"\n\n停止済み\nLog: {log_path}")
        self._set_running_state(False)

    def _fail(self, message: str) -> None:
        self.status_var.set(f"実行失敗: {message}")
        self._set_running_state(False)


def main() -> int:
    app = SwarmGui()
    app.root.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
