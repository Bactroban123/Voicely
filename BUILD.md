# Voicely — Build & Status

## Status (June 21 2026): full app built, installed, awaiting first-run permissions

| Layer | Status |
|---|---|
| Research / Spec / Plan / Design | ✅ `docs/`, `PRODUCT.md`, `DESIGN.md` |
| VoicelyCore (pure logic) | ✅ 74 checks; `swift test` = 36 XCTest, 0 failures |
| Phase 0 scaffold (menu-bar app) | ✅ builds |
| Phase 1 hotkey + mic + permissions | ✅ builds |
| Phase 2+3 on-device transcription + paste | ✅ builds |
| Phase 4 AI cleanup (OpenRouter) | ✅ builds |
| Phase 5 HUD + Settings + launch-at-login | ✅ builds |
| **Installed** | ✅ `/Applications/Voicely.app` (ad-hoc signed) |
| First-run permissions + real dictation test | ⏳ needs the user (TCC grants + model download) |

Xcode 26.5 is installed and active; `xcodebuild` and `swift test` work.

## Build / install / test

```bash
cd VoicelyCore && swift test          # pure-logic suite (36 tests)
./scripts/install.sh                   # build + ad-hoc sign + install to /Applications
open /Applications/Voicely.app         # launch (menu-bar icon appears)
```

### First-run permissions (one time)
Voicely needs three macOS permissions. On launch it requests all three:
1. **Microphone** — click Allow on the prompt.
2. **Accessibility** (to paste at the cursor) — System Settings ▸ Privacy & Security ▸ Accessibility ▸ turn **Voicely** on.
3. **Input Monitoring** (for the global hotkey) — System Settings ▸ Privacy & Security ▸ Input Monitoring ▸ turn **Voicely** on.

Accessibility + Input Monitoring take effect only after you **quit and reopen** Voicely.

### Using it
- Default hotkey **Right Option (⌥)**: tap to toggle recording, or hold to push-to-talk; `esc` cancels.
- First dictation downloads the Parakeet model (~hundreds of MB) — it lags once, then is fast.
- AI cleanup is **off** by default. Turn it on in Settings and paste your OpenRouter key to enable punctuation/filler cleanup + custom-vocabulary correction.

## Known limitations (next up)
- Signing is **ad-hoc** → permissions may need re-approval after each rebuild. A free Apple Development cert (sign into Xcode) gives a stable identity that avoids this.
- The transcription model picker wires **Parakeet (English/Multilingual)** today; Whisper + Apple Speech engines are the next engines to implement.
- Cleanup is non-streaming v1; streaming paste is a planned enhancement.

## Layout
```
docs/            research · specs · plans
PRODUCT.md DESIGN.md   product + visual identity
VoicelyCore/     pure logic (Swift package) — scripts/verify.sh, swift test
App/             the macOS app (Capture · Transcribe · Refine · Insert · UI · Settings)
project.yml      XcodeGen spec (regenerate: xcodegen generate)
scripts/install.sh   build + sign + install
```
