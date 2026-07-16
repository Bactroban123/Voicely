# Voicely — Windows prototype (not shipped)

> **This is not a released app, and it can't be one as it stands.**
>
> Unlike the Mac app, **this transcribes in the cloud: it uploads your raw
> microphone audio to OpenRouter.** Voicely's central promise is the opposite —
> "your audio never leaves" — so shipping this under the Voicely name made the
> product's main claim untrue for whoever installed it.
>
> It went out attached to the v0.2.0 release by mistake and was **pulled on
> 2026-07-16** (3 people had downloaded it). Its build workflow is now
> manual-only and publishes nothing.
>
> **To ship it, it needs on-device transcription** — whisper.cpp / faster-whisper
> here, or the Tauri + Rust rewrite that `platforms/README.md` always intended
> for Windows. Until then, please don't restore the release step.

A tray app: press a hotkey, speak, press again, and your words are typed wherever
the cursor is. Transcription and optional cleanup both go through an OpenRouter
API key.

## What it does with your audio

```
hotkey → record mic → UPLOAD WAV to OpenRouter Whisper → optional AI cleanup → paste at cursor
```

That upload is the whole problem: the Mac app never does it (it transcribes
on-device with Parakeet/WhisperKit and only sends *text*, and only if you enable
AI cleanup).

- The key is stored only in `%APPDATA%\Voicely\config.json` on your PC.
- Logs: `%APPDATA%\Voicely\log.txt` (note: unbounded — it has no rotation, unlike
  the Mac app's).
- Config you can edit by hand: `hotkey`, `transcribe_model`, `cleanup` (true/false),
  `cleanup_model`, `language` ("" = auto-detect).
- Tray: right-click to set the key, open the log folder, or quit. The icon turns
  red while listening.

## Building it (manual only)

`.github/workflows/windows.yml` builds it on a GitHub Actions **Windows** runner
(a Windows `.exe` can't be produced on macOS). It runs **only** via
`workflow_dispatch` — no tag trigger, no release upload — and leaves the installer
as a CI artifact, which needs repo access to download and expires on its own.

To build locally on a Windows machine:

```bat
cd windows
pip install -r app\requirements.txt pyinstaller
python app\gen_icon.py
pyinstaller --noconfirm --onefile --windowed --name Voicely --icon app\icon.ico ^
  --collect-all sounddevice --collect-all pystray --collect-all pyperclip ^
  --hidden-import pystray._win32 --hidden-import PIL.ImageDraw app\main.py
:: then compile installer.iss with Inno Setup (ISCC.exe installer.iss)
```

## Known issues (beyond the cloud upload)

- **The hotkey callback does blocking work.** `on_hotkey` starts the audio stream
  synchronously inside the global keyboard hook. On Windows those hooks are
  system-wide and synchronous by design, so a slow start can lag input everywhere.
  The Mac app had exactly this bug and it froze other apps; it's fixed there and
  not here.
- **`max_tokens` is hardcoded** and `finish_reason` is never checked, so a long
  dictation is silently truncated mid-sentence. Also fixed on Mac, not here.
- **`log.txt` grows forever** — no rotation.
