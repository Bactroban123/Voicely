"""
My Beautiful Wife — a private voice-to-text tray app for Windows.

Press the hotkey (default Ctrl+Alt+Space) to start listening, speak, press it
again to stop. The audio is transcribed (and optionally cleaned up) through the
OpenRouter API, and the text is typed wherever the cursor is.

Everything is intentionally simple and defensive: it should never crash, and any
problem shows up as a tray notification and in the log file. The OpenRouter key
lives only in this PC's user folder (never in the code).
"""

from __future__ import annotations

import base64
import io
import json
import logging
import os
import threading
import time
import traceback
import wave

import numpy as np
import requests
import sounddevice as sd
import pyperclip
import keyboard
import pystray
from PIL import Image, ImageDraw

APP_NAME = "My Beautiful Wife"
APP_DIR = os.path.join(os.environ.get("APPDATA", os.path.expanduser("~")), "MyBeautifulWife")
CONFIG_PATH = os.path.join(APP_DIR, "config.json")
LOG_PATH = os.path.join(APP_DIR, "log.txt")

OPENROUTER_BASE = "https://openrouter.ai/api/v1"
SAMPLE_RATE = 16000

DEFAULT_CONFIG = {
    "openrouter_key": "",
    "hotkey": "ctrl+alt+space",
    "transcribe_model": "openai/whisper-1",
    "cleanup": True,
    "cleanup_model": "google/gemini-2.5-flash-lite",
    "language": "",  # "" = auto-detect; or "en", "he", etc.
}

os.makedirs(APP_DIR, exist_ok=True)
logging.basicConfig(
    filename=LOG_PATH,
    level=logging.INFO,
    format="%(asctime)s  %(levelname)s  %(message)s",
)
log = logging.getLogger(APP_NAME)


# --------------------------------------------------------------------------- config

def load_config() -> dict:
    cfg = dict(DEFAULT_CONFIG)
    try:
        if os.path.exists(CONFIG_PATH):
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                cfg.update(json.load(f))
    except Exception:
        log.exception("failed to read config; using defaults")
    return cfg


def save_config(cfg: dict) -> None:
    try:
        with open(CONFIG_PATH, "w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=2)
    except Exception:
        log.exception("failed to write config")


def ask_for_key(current: str = "") -> str | None:
    """Tiny Tk dialog to paste the OpenRouter key. Returns the key or None."""
    try:
        import tkinter as tk
        from tkinter import simpledialog

        root = tk.Tk()
        root.withdraw()
        root.attributes("-topmost", True)
        value = simpledialog.askstring(
            APP_NAME,
            "Paste your OpenRouter API key (starts with sk-or-):",
            initialvalue=current,
            parent=root,
        )
        root.destroy()
        if value:
            return value.strip()
    except Exception:
        log.exception("key dialog failed")
    return None


# --------------------------------------------------------------------------- audio

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
            samplerate=SAMPLE_RATE, channels=1, dtype="int16", callback=callback
        )
        self._stream.start()

    def stop(self) -> bytes:
        """Stop and return a 16 kHz mono WAV as bytes (empty if nothing/too short)."""
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
        audio = np.concatenate(frames, axis=0)
        if audio.shape[0] < SAMPLE_RATE * 0.3:  # < 0.3s, ignore
            return b""
        buf = io.BytesIO()
        with wave.open(buf, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)  # int16
            wf.setframerate(SAMPLE_RATE)
            wf.writeframes(audio.tobytes())
        return buf.getvalue()


# --------------------------------------------------------------------------- openrouter

def transcribe(wav_bytes: bytes, cfg: dict) -> str:
    b64 = base64.b64encode(wav_bytes).decode("ascii")
    body = {
        "model": cfg["transcribe_model"],
        "input_audio": {"data": b64, "format": "wav"},
    }
    if cfg.get("language"):
        body["language"] = cfg["language"]
    r = requests.post(
        f"{OPENROUTER_BASE}/audio/transcriptions",
        headers={
            "Authorization": f"Bearer {cfg['openrouter_key']}",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://github.com/Bactroban123/Voicely",
            "X-Title": APP_NAME,
        },
        json=body,
        timeout=120,
    )
    r.raise_for_status()
    return (r.json().get("text") or "").strip()


def cleanup(text: str, cfg: dict) -> str:
    """Best-effort punctuation/filler cleanup. Returns raw text on any error."""
    try:
        system = (
            "You are a dictation cleanup engine. Return a corrected version of the "
            "SAME text: fix punctuation, capitalization and obvious spacing, remove "
            "filler words ('um', 'uh', false starts). Do NOT translate, answer, add, "
            "or summarize. Preserve the speaker's language and meaning. Output ONLY "
            "the cleaned text."
        )
        r = requests.post(
            f"{OPENROUTER_BASE}/chat/completions",
            headers={
                "Authorization": f"Bearer {cfg['openrouter_key']}",
                "Content-Type": "application/json",
                "HTTP-Referer": "https://github.com/Bactroban123/Voicely",
                "X-Title": APP_NAME,
            },
            json={
                "model": cfg["cleanup_model"],
                "messages": [
                    {"role": "system", "content": system},
                    {"role": "user", "content": text},
                ],
                "temperature": 0.1,
                "max_tokens": 1000,
            },
            timeout=60,
        )
        r.raise_for_status()
        out = (r.json()["choices"][0]["message"]["content"] or "").strip()
        return out or text
    except Exception:
        log.exception("cleanup failed; using raw transcript")
        return text


# --------------------------------------------------------------------------- typing

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


# --------------------------------------------------------------------------- icons

def make_icon(recording: bool) -> Image.Image:
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    color = (34, 211, 238, 255) if not recording else (226, 75, 74, 255)  # cyan / red
    # a small heart
    d.ellipse((14, 16, 34, 36), fill=color)
    d.ellipse((30, 16, 50, 36), fill=color)
    d.polygon([(16, 30), (48, 30), (32, 52)], fill=color)
    return img


# --------------------------------------------------------------------------- app

class App:
    def __init__(self):
        self.cfg = load_config()
        self.recorder = Recorder()
        self.recording = False
        self.busy = False
        self.icon = pystray.Icon(APP_NAME, make_icon(False), APP_NAME, self._menu())

    def _menu(self):
        return pystray.Menu(
            pystray.MenuItem(lambda i: self._status_text(), None, enabled=False),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Set OpenRouter key…", self.on_set_key),
            pystray.MenuItem("Open log folder", self.on_open_folder),
            pystray.MenuItem("Quit", self.on_quit),
        )

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

    # ---- hotkey

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
            text = transcribe(wav, self.cfg)
            if self.cfg.get("cleanup"):
                text = cleanup(text, self.cfg)
            if text:
                type_text(text)
                log.info("typed %d chars", len(text))
            else:
                self.notify("Didn't catch that — try again.")
        except requests.HTTPError as e:
            log.exception("HTTP error")
            code = getattr(e.response, "status_code", "?")
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

    # ---- menu actions

    def on_set_key(self, icon=None, item=None) -> None:
        def worker():
            key = ask_for_key(self.cfg.get("openrouter_key", ""))
            if key:
                self.cfg["openrouter_key"] = key
                save_config(self.cfg)
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

    # ---- run

    def run(self) -> None:
        if not self.cfg.get("openrouter_key"):
            key = ask_for_key()
            if key:
                self.cfg["openrouter_key"] = key
                save_config(self.cfg)
        try:
            keyboard.add_hotkey(self.cfg.get("hotkey", "ctrl+alt+space"), self.on_hotkey)
        except Exception:
            log.exception("failed to register hotkey")
        log.info("%s started", APP_NAME)
        self.icon.run()


def main() -> None:
    try:
        App().run()
    except Exception:
        log.critical("fatal:\n%s", traceback.format_exc())


if __name__ == "__main__":
    main()
