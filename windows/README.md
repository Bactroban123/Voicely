# Voicely — Windows voice-to-text

A tiny, private tray app: press a hotkey, speak, press again, and your words are
typed wherever the cursor is. Transcription (and optional cleanup) runs through an
OpenRouter API key. No account, no cloud screenshots, nothing salesy.

## For the person installing it

1. Download **`VoicelySetup.exe`** from the
   [Releases page](https://github.com/Bactroban123/Voicely/releases).
2. Run it. If Windows SmartScreen warns ("Windows protected your PC"), click
   **More info → Run anyway** (it's unsigned, that's expected).
3. Launch **Voicely** from the Start menu or desktop — it lives in the system tray
   (bottom-right) as a small waveform icon.
4. On first run it asks for your **OpenRouter API key** — paste it once.
5. Press **Ctrl+Alt+Space**, speak, press it again. The text types itself.

Right-click the tray icon for: set the key, open the log folder, quit.
The icon turns red while listening.

## How it works

```
hotkey → record mic → OpenRouter Whisper → optional AI cleanup → paste at cursor
```

- The key is stored only in `%APPDATA%\Voicely\config.json` on your PC.
- Logs: `%APPDATA%\Voicely\log.txt`.
- Config options you can edit by hand: `hotkey`, `transcribe_model`, `cleanup` (true/false),
  `cleanup_model`, `language` ("" = auto-detect).

## Building the installer (done by CI)

This is built on a GitHub Actions **Windows** runner
(see `.github/workflows/windows.yml`) because a Windows `.exe` can't be produced on
macOS. Push a tag like `v0.2.0` and it produces `VoicelySetup.exe` as a release
asset + artifact alongside the macOS DMG.

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
