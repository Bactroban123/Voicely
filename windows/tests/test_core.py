import base64
import io
import json
import wave

import numpy as np
import pytest
import requests

import core


# ---------------------------------------------------------------- helpers

class FakeResp:
    def __init__(self, payload, raise_exc=None):
        self._payload = payload
        self._raise = raise_exc

    def json(self):
        return self._payload

    def raise_for_status(self):
        if self._raise:
            raise self._raise


def recorder(seconds, rate=core.SAMPLE_RATE):
    n = int(rate * seconds)
    t = np.linspace(0, seconds, n, endpoint=False)
    return (np.sin(2 * np.pi * 220 * t) * 12000).astype(np.int16).reshape(-1, 1)


def sample_cfg(**over):
    cfg = dict(core.DEFAULT_CONFIG)
    cfg["openrouter_key"] = "sk-or-test"
    cfg.update(over)
    return cfg


# ---------------------------------------------------------------- config

def test_load_config_missing_returns_defaults(tmp_path):
    cfg = core.load_config(str(tmp_path / "nope.json"))
    assert cfg == core.DEFAULT_CONFIG
    assert cfg is not core.DEFAULT_CONFIG  # a copy, not the shared dict


def test_load_config_merges_partial(tmp_path):
    p = tmp_path / "config.json"
    p.write_text(json.dumps({"openrouter_key": "sk-or-abc", "hotkey": "f9"}))
    cfg = core.load_config(str(p))
    assert cfg["openrouter_key"] == "sk-or-abc"
    assert cfg["hotkey"] == "f9"
    assert cfg["transcribe_model"] == core.DEFAULT_CONFIG["transcribe_model"]  # default kept


def test_load_config_corrupt_returns_defaults(tmp_path):
    p = tmp_path / "config.json"
    p.write_text("{ this is not json ")
    assert core.load_config(str(p)) == core.DEFAULT_CONFIG


def test_save_then_load_roundtrip(tmp_path):
    p = str(tmp_path / "sub" / "config.json")  # nested dir is created
    core.save_config(sample_cfg(language="he"), p)
    cfg = core.load_config(p)
    assert cfg["openrouter_key"] == "sk-or-test"
    assert cfg["language"] == "he"


# ---------------------------------------------------------------- wav

def test_build_wav_is_valid_and_roundtrips():
    wav = core.build_wav(recorder(1.0))
    assert wav[:4] == b"RIFF" and wav[8:12] == b"WAVE"
    with wave.open(io.BytesIO(wav), "rb") as wf:
        assert wf.getnchannels() == 1
        assert wf.getsampwidth() == 2
        assert wf.getframerate() == core.SAMPLE_RATE
        assert wf.getnframes() == core.SAMPLE_RATE  # 1 second


def test_build_wav_too_short_is_empty():
    assert core.build_wav(recorder(0.1)) == b""


def test_build_wav_empty_inputs():
    assert core.build_wav(None) == b""
    assert core.build_wav(np.zeros((0, 1), dtype=np.int16)) == b""


def test_build_wav_accepts_flat_or_2d():
    flat = core.build_wav(recorder(1.0).reshape(-1))
    twod = core.build_wav(recorder(1.0))
    assert flat == twod and len(flat) > 1000


# ---------------------------------------------------------------- request building

def test_transcribe_body_encodes_audio_base64():
    body = core.transcribe_body(b"\x00\x01\x02\x03", sample_cfg())
    assert body["model"] == "openai/whisper-1"
    assert body["input_audio"]["format"] == "wav"
    assert base64.b64decode(body["input_audio"]["data"]) == b"\x00\x01\x02\x03"


def test_transcribe_body_language_optional():
    assert "language" not in core.transcribe_body(b"x", sample_cfg(language=""))
    assert core.transcribe_body(b"x", sample_cfg(language="he"))["language"] == "he"


def test_headers_carry_bearer_key():
    h = core.request_headers(sample_cfg(openrouter_key="sk-or-xyz"))
    assert h["Authorization"] == "Bearer sk-or-xyz"
    assert h["Content-Type"] == "application/json"


def test_cleanup_body_shape():
    body = core.cleanup_body("hello", sample_cfg())
    assert body["model"] == core.DEFAULT_CONFIG["cleanup_model"]
    assert body["messages"][0]["role"] == "system"
    assert body["messages"][1] == {"role": "user", "content": "hello"}
    assert body["temperature"] == 0.1


# ---------------------------------------------------------------- cleanup modes

def test_default_mode_is_clean():
    assert core.DEFAULT_CONFIG["cleanup_mode"] == "clean"
    assert core.system_for_mode("clean") == core.CLEANUP_SYSTEM


def test_unknown_mode_falls_back_to_clean():
    assert core.system_for_mode("nope") == core.CLEANUP_SYSTEM


def test_translate_modes_target_and_source():
    assert "fluent English" in core.system_for_mode("translate-en")
    assert "Thai" in core.system_for_mode("translate-th")
    th_en = core.system_for_mode("translate-th-en")
    assert "spoken Thai" in th_en
    assert "fluent English" in th_en
    assert "ครับ" in th_en  # Thai politeness-particle guidance


def test_cleanup_body_uses_selected_mode():
    body = core.cleanup_body("สวัสดี", sample_cfg(cleanup_mode="translate-th-en"))
    assert "spoken Thai" in body["messages"][0]["content"]


# ---------------------------------------------------------------- parsing

def test_parse_transcription_trims():
    assert core.parse_transcription({"text": "  hi there \n"}) == "hi there"
    assert core.parse_transcription({}) == ""


def test_parse_chat_extracts_content():
    payload = {"choices": [{"message": {"content": " cleaned. "}}]}
    assert core.parse_chat(payload) == "cleaned."


# ---------------------------------------------------------------- transcribe / cleanup (network mocked)

def test_transcribe_posts_and_parses():
    seen = {}

    def fake_post(url, headers=None, json=None, timeout=None):
        seen["url"], seen["json"], seen["headers"] = url, json, headers
        return FakeResp({"text": "  hello world  "})

    out = core.transcribe(b"audio", sample_cfg(), post=fake_post)
    assert out == "hello world"
    assert seen["url"].endswith("/audio/transcriptions")
    assert seen["json"]["model"] == "openai/whisper-1"
    assert seen["headers"]["Authorization"] == "Bearer sk-or-test"


def test_transcribe_propagates_http_error():
    err = requests.HTTPError("401")

    def fake_post(*a, **k):
        return FakeResp({}, raise_exc=err)

    with pytest.raises(requests.HTTPError):
        core.transcribe(b"audio", sample_cfg(), post=fake_post)


def test_cleanup_returns_cleaned_text():
    def fake_post(url, headers=None, json=None, timeout=None):
        assert url.endswith("/chat/completions")
        return FakeResp({"choices": [{"message": {"content": "Hello, world."}}]})

    assert core.cleanup("um hello world", sample_cfg(), post=fake_post) == "Hello, world."


def test_cleanup_falls_back_to_raw_on_error():
    def fake_post(*a, **k):
        raise requests.ConnectionError("offline")

    assert core.cleanup("raw text", sample_cfg(), post=fake_post) == "raw text"


def test_cleanup_empty_text_passthrough():
    assert core.cleanup("", sample_cfg(), post=lambda *a, **k: 1 / 0) == ""
