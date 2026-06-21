"""
Pure, cross-platform logic for My Beautiful Wife — no audio, keyboard, tray or GUI
imports, so it runs (and is unit-tested) on any OS, including the macOS dev box and
the Windows CI runner. main.py owns the platform I/O and calls into here.
"""

from __future__ import annotations

import base64
import io
import json
import os
import wave

import numpy as np
import requests

OPENROUTER_BASE = "https://openrouter.ai/api/v1"
APP_TITLE = "My Beautiful Wife"
SAMPLE_RATE = 16000
MIN_SECONDS = 0.3  # ignore accidental sub-0.3s taps

DEFAULT_CONFIG = {
    "openrouter_key": "",
    "hotkey": "ctrl+alt+space",
    "transcribe_model": "openai/whisper-1",
    "cleanup": True,
    "cleanup_model": "google/gemini-2.5-flash-lite",
    "language": "",  # "" = auto-detect
}

CLEANUP_SYSTEM = (
    "You are a dictation cleanup engine. Return a corrected version of the SAME "
    "text: fix punctuation, capitalization and obvious spacing, remove filler words "
    "('um', 'uh', false starts). Do NOT translate, answer, add, or summarize. "
    "Preserve the speaker's language and meaning. Output ONLY the cleaned text."
)


# ------------------------------------------------------------------ config

def load_config(path: str) -> dict:
    cfg = dict(DEFAULT_CONFIG)
    try:
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict):
                cfg.update(data)
    except Exception:
        pass  # corrupt/unreadable → safe defaults
    return cfg


def save_config(cfg: dict, path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)


# ------------------------------------------------------------------ audio → wav

def build_wav(frames_int16, sample_rate: int = SAMPLE_RATE) -> bytes:
    """Encode mono int16 PCM samples to WAV bytes. Returns b'' if empty/too short."""
    if frames_int16 is None:
        return b""
    arr = np.asarray(frames_int16).reshape(-1).astype("<i2")
    if arr.shape[0] < int(sample_rate * MIN_SECONDS):
        return b""
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(arr.tobytes())
    return buf.getvalue()


# ------------------------------------------------------------------ openrouter

def request_headers(cfg: dict) -> dict:
    return {
        "Authorization": f"Bearer {cfg['openrouter_key']}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://github.com/Bactroban123/Voicely",
        "X-Title": APP_TITLE,
    }


def transcribe_body(wav_bytes: bytes, cfg: dict) -> dict:
    body = {
        "model": cfg["transcribe_model"],
        "input_audio": {
            "data": base64.b64encode(wav_bytes).decode("ascii"),
            "format": "wav",
        },
    }
    if cfg.get("language"):
        body["language"] = cfg["language"]
    return body


def cleanup_body(text: str, cfg: dict) -> dict:
    return {
        "model": cfg["cleanup_model"],
        "messages": [
            {"role": "system", "content": CLEANUP_SYSTEM},
            {"role": "user", "content": text},
        ],
        "temperature": 0.1,
        "max_tokens": 1000,
    }


def parse_transcription(payload: dict) -> str:
    return (payload.get("text") or "").strip()


def parse_chat(payload: dict) -> str:
    return (payload["choices"][0]["message"]["content"] or "").strip()


def transcribe(wav_bytes: bytes, cfg: dict, post=None) -> str:
    """POST audio to OpenRouter, return text. `post` is injectable for tests."""
    post = post or requests.post
    r = post(
        f"{OPENROUTER_BASE}/audio/transcriptions",
        headers=request_headers(cfg),
        json=transcribe_body(wav_bytes, cfg),
        timeout=120,
    )
    r.raise_for_status()
    return parse_transcription(r.json())


def cleanup(text: str, cfg: dict, post=None) -> str:
    """Best-effort cleanup. Returns the raw text on any error (never raises)."""
    if not text:
        return text
    post = post or requests.post
    try:
        r = post(
            f"{OPENROUTER_BASE}/chat/completions",
            headers=request_headers(cfg),
            json=cleanup_body(text, cfg),
            timeout=60,
        )
        r.raise_for_status()
        return parse_chat(r.json()) or text
    except Exception:
        return text
