"""
Voicely — voice-to-text tray app for Windows.

Press the hotkey (default Ctrl+Alt+Space) to start listening, speak, press it
again to stop. The audio is transcribed (and optionally cleaned up) through the
OpenRouter API, and the text is typed wherever the cursor is.

This file owns the platform I/O (audio, global hotkey, clipboard, tray, dialogs).
All the pure logic lives in core.py and is unit-tested.
"""

from __future__ import annotations

import logging
import os
import threading
import time
import traceback

import numpy as np
import requests
import sounddevice as sd
import pyperclip
import keyboard
import pystray
from PIL import Image, ImageDraw

import core

APP_NAME = core.APP_TITLE
APP_DIR = os.path.join(os.environ.get("APPDATA", os.path.expanduser("~")), "Voicely")
CONFIG_PATH = os.path.join(APP_DIR, "config.json")
LOG_PATH = os.path.join(APP_DIR, "log.txt")

os.makedirs(APP_DIR, exist_ok=True)
logging.basicConfig(filename=LOG_PATH, level=logging.INFO,
                    format="%(asctime)s  %(levelname)s  %(message)s")
log = logging.getLogger(APP_NAME)


def ask_for_key(current: str = "") -> str | None:
    """Tiny Tk dialog to paste the OpenRouter key. Returns the key or None."""
    try:
        import tkinter as tk
        from tkinter import simpledialog

        root = tk.Tk()
        root.withdraw()
        root.attributes("-topmost", True)
        value = simpledialog.askstring(
            APP_NAME, "Paste your OpenRouter API key (starts with sk-or-):",
            initialvalue=current, parent=root,
        )
        root.destroy()
        if value:
            return value.strip()
    except Exception:
        log.exception("key dialog failed")
    return None


class Recorder:
    def __init__(self):
        self._frames: list[np.ndarray] = []
        self._stream: sd.InputStream | None = None
        self._lock = threading.Lock()

    def start(self) -> None:
        with self._lock:
            self._frames = []

        def callback(indata, frames, time_info, status):
            if status:
                log.warning("audio status: %s", status)
            with self._lock:
                self._frames.append(indata.copy())

        self._stream = sd.InputStream(
            samplerate=core.SAMPLE_RATE, channels=1, dtype="int16", callback=callback)
        self._stream.start()

    def stop(self) -> bytes:
        if self._stream is not None:
            try:
                self._stream.stop()
                self._stream.close()
            except Exception:
                log.exception("error closing stream")
            self._stream = None
        with self._lock:
            frames = list(self._frames)
            self._frames = []
        if not frames:
            return b""
        return core.build_wav(np.concatenate(frames, axis=0))


def type_text(text: str) -> None:
    """Paste text at the cursor via the clipboard (handles Unicode/Hebrew)."""
    if not text:
        return
    previous = None
    try:
        previous = pyperclip.paste()
    except Exception:
        pass
    try:
        pyperclip.copy(text)
        time.sleep(0.05)
        keyboard.send("ctrl+v")
        time.sleep(0.15)
    finally:
        if previous is not None:
            try:
                pyperclip.copy(previous)
            except Exception:
                pass


def make_icon(recording: bool) -> Image.Image:
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    color = (226, 75, 74, 255) if recording else (34, 211, 238, 255)  # red / icy cyan
    d.ellipse((14, 16, 34, 36), fill=color)
    d.ellipse((30, 16, 50, 36), fill=color)
    d.polygon([(16, 30), (48, 30), (32, 52)], fill=color)
    return img


class App:
    def __init__(self):
        self.cfg = core.load_config(CONFIG_PATH)
        self.recorder = Recorder()
        self.recording = False
        self.busy = False
        self.icon = pystray.Icon(APP_NAME, make_icon(False), APP_NAME, self._menu())

    MODE_LABELS = [
        ("clean", "Clean up"),
        ("translate-en", "Translate → English"),
        ("translate-th", "Translate → Thai"),
        ("translate-th-en", "Thai → English"),
    ]

    def _menu(self):
        return pystray.Menu(
            pystray.MenuItem(lambda i: self._status_text(), None, enabled=False),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Mode", self._mode_menu()),
            pystray.MenuItem("Set OpenRouter key…", self.on_set_key),
            pystray.MenuItem("Open log folder", self.on_open_folder),
            pystray.MenuItem("Quit", self.on_quit),
        )

    def _mode_menu(self):
        return pystray.Menu(*[
            pystray.MenuItem(
                label,
                self._make_set_mode(mode_id),
                checked=self._make_is_mode(mode_id),
                radio=True,
            )
            for mode_id, label in self.MODE_LABELS
        ])

    def _make_set_mode(self, mode_id):
        def handler(icon=None, item=None):
            self.cfg["cleanup_mode"] = mode_id
            if mode_id != "clean":
                self.cfg["cleanup"] = True  # translation runs through the cleanup step
            core.save_config(self.cfg, CONFIG_PATH)
            try:
                self.icon.update_menu()
            except Exception:
                pass
        return handler

    def _make_is_mode(self, mode_id):
        return lambda item: self.cfg.get("cleanup_mode", "clean") == mode_id

    def _status_text(self) -> str:
        hk = self.cfg.get("hotkey", "ctrl+alt+space")
        if self.recording:
            return "● Listening… (press hotkey to type)"
        if self.busy:
            return "… Working"
        return f"Ready — press {hk} to talk"

    def notify(self, msg: str) -> None:
        try:
            self.icon.notify(msg, APP_NAME)
        except Exception:
            pass

    def set_recording(self, value: bool) -> None:
        self.recording = value
        try:
            self.icon.icon = make_icon(value)
            self.icon.update_menu()
        except Exception:
            pass

    def on_hotkey(self) -> None:
        try:
            if self.busy:
                return
            if not self.recording:
                if not self.cfg.get("openrouter_key"):
                    self.notify("Set your OpenRouter key first (right-click the tray icon).")
                    return
                self.recorder.start()
                self.set_recording(True)
            else:
                self.set_recording(False)
                wav = self.recorder.stop()
                threading.Thread(target=self._process, args=(wav,), daemon=True).start()
        except Exception:
            log.exception("hotkey handler error")
            self.set_recording(False)

    def _process(self, wav: bytes) -> None:
        if not wav:
            return
        self.busy = True
        try:
            self.icon.update_menu()
        except Exception:
            pass
        try:
            text = core.transcribe(wav, self.cfg)
            # Run the cleanup/translate step when cleanup is on, or whenever a
            # translate mode is active (translation lives inside that step).
            if self.cfg.get("cleanup") or self.cfg.get("cleanup_mode", "clean") != "clean":
                text = core.cleanup(text, self.cfg)
            if text:
                type_text(text)
                log.info("typed %d chars", len(text))
            else:
                self.notify("Didn't catch that — try again.")
        except requests.HTTPError as e:
            code = getattr(getattr(e, "response", None), "status_code", "?")
            log.exception("HTTP error %s", code)
            if code == 401:
                self.notify("OpenRouter key was rejected. Set it again from the tray menu.")
            else:
                self.notify(f"Transcription failed (HTTP {code}). See log.")
        except Exception:
            log.exception("processing error")
            self.notify("Something went wrong. See the log folder.")
        finally:
            self.busy = False
            try:
                self.icon.update_menu()
            except Exception:
                pass

    def on_set_key(self, icon=None, item=None) -> None:
        def worker():
            key = ask_for_key(self.cfg.get("openrouter_key", ""))
            if key:
                self.cfg["openrouter_key"] = key
                core.save_config(self.cfg, CONFIG_PATH)
                self.notify("OpenRouter key saved.")
        threading.Thread(target=worker, daemon=True).start()

    def on_open_folder(self, icon=None, item=None) -> None:
        try:
            os.startfile(APP_DIR)  # type: ignore[attr-defined]
        except Exception:
            log.exception("open folder failed")

    def on_quit(self, icon=None, item=None) -> None:
        try:
            keyboard.unhook_all_hotkeys()
        except Exception:
            pass
        self.icon.stop()

    def run(self) -> None:
        if not self.cfg.get("openrouter_key"):
            key = ask_for_key()
            if key:
                self.cfg["openrouter_key"] = key
                core.save_config(self.cfg, CONFIG_PATH)
        try:
            keyboard.add_hotkey(self.cfg.get("hotkey", "ctrl+alt+space"), self.on_hotkey)
        except Exception:
            log.exception("failed to register hotkey")
        log.info("%s started", APP_NAME)
        # CI smoke mode: everything is constructed and wired; exit instead of
        # entering the blocking tray loop, so the frozen exe can be verified to
        # boot cleanly on a headless Windows runner.
        if os.environ.get("VOICELY_SMOKE"):
            log.info("SMOKE OK")
            return
        self.icon.run()


def main() -> None:
    try:
        App().run()
    except Exception:
        log.critical("fatal:\n%s", traceback.format_exc())


if __name__ == "__main__":
    main()
