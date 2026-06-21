# My Beautiful Wife — Windows voice-to-text

A tiny, private tray app: press a hotkey, speak, press again, and your words are
typed wherever the cursor is. Transcription (and optional cleanup) runs through an
OpenRouter API key. No account, no cloud screenshots, nothing salesy.

## For the person installing it
1. Download **`MyBeautifulWifeSetup.exe`** from the
   [Releases page](https://github.com/Bactroban123/Voicely/releases).
2. Run it. If Windows SmartScreen warns ("Windows protected your PC"), click
   **More info → Run anyway** (it's unsigned, that's expected).
3. Launch **My Beautiful Wife** (it lives in the system tray, bottom-right, as a heart).
4. On first run it asks for the **OpenRouter API key** — paste it once.
5. Press **Ctrl+Alt+Space**, speak, press it again. The text types itself.

Right-click the tray heart for: set the key, open the log folder, quit.
The icon turns **red while listening**.

## How it works
`hotkey → record mic → OpenRouter /audio/transcriptions (Whisper) → optional cleanup → paste at cursor`

- The key is stored only in `%APPDATA%\MyBeautifulWife\config.json` on that PC.
- Logs: `%APPDATA%\MyBeautifulWife\log.txt`.
- Config options: `hotkey`, `transcribe_model`, `cleanup` (true/false), `cleanup_model`, `language` ("" = auto).

## Building the installer (done by CI, not on a Mac)
This is built on a GitHub Actions **Windows** runner (see
`.github/workflows/windows-mbw.yml`) because a Windows `.exe` can't be produced on
macOS. Push a tag `mbw-v1` (or run the workflow manually) and it produces
`MyBeautifulWifeSetup.exe` as a release asset + artifact.

To build locally on a Windows machine instead:
```bat
cd windows
pip install -r app\requirements.txt pyinstaller
python app\gen_icon.py
pyinstaller --noconfirm --onefile --windowed --name MyBeautifulWife --icon app\icon.ico --collect-all sounddevice app\main.py
:: then compile installer.iss with Inno Setup (ISCC.exe)
```
