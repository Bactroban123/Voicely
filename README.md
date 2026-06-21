# Voicely

**Speak any language. Type it in another. Privately, on your device.**

The private, bilingual dictation app for people who think in two languages. Hold a
hotkey, speak English or Hebrew, and clean (or translated) text lands at your cursor
in any app. Speech recognition runs **entirely on-device** — your audio never leaves
the Mac. Native, not Electron.

```
hold hotkey → speak (EN / עברית) → on-device transcribe → AI clean / translate → insert at cursor
```

## What makes it different (vs Wispr Flow)
1. **On-device + private** — no screenshots, no audio upload.
2. **English ⇄ Hebrew translation** — no other system-wide dictation app does it.
3. **Best-in-class Hebrew** (ivrit.ai, planned) · **native, not Electron** · **offline-reliable**.

## Status
A working macOS app (dictation, EN+HE, translation modes, AI cleanup presets,
snippets, custom vocabulary, icy "Frostpane" UI) plus a marketing/sales site and a
full commercial plan. Cross-platform (iOS/Windows/Android) is scaffolded, not built.
See **[docs/STATUS.md](docs/STATUS.md)** for the honest what's-done / what's-next, and
**[docs/plans/2026-06-21-voicely-master-strategy.md](docs/plans/2026-06-21-voicely-master-strategy.md)** for the plan.

## Build & run
```bash
./scripts/install.sh                 # build + sign + install to /Applications
open /Applications/Voicely.app
./scripts/make-dmg.sh                # → dist/Voicely.dmg (installer)
cd VoicelyCore && swift test         # pure-logic tests (92 checks)
```

macOS 14+ · Apple Silicon · requires Microphone, Accessibility, Input Monitoring.

## Layout
```
App/             the macOS app (Capture · Transcribe · Refine · Insert · UI · Settings)
VoicelyCore/     pure, tested logic (Swift package)
site/            icy marketing + sales landing page (static, deployable)
platforms/       cross-platform scaffold + plan (iOS / Windows / Android)
scripts/         install · make-dmg · make-signing-identity · verify
docs/            plans · research · specs · STATUS
```

Built on the MIT-licensed [Pindrop](https://github.com/watzon/pindrop) +
[Hex](https://github.com/kitlangton/Hex), with
[WhisperKit](https://github.com/argmaxinc/WhisperKit) and
[FluidAudio](https://github.com/FluidInference/FluidAudio).

© 2026 Voicely. Free unlimited dictation; Pro $8/mo · $60/yr · $99 lifetime.
