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
1. **On-device + private** — your audio never leaves the Mac; no screenshots, no
   audio upload. (Transcript text goes out only if you turn on AI cleanup, with
   zero-retention headers. Wispr's own docs describe collecting screenshots,
   on-screen text and IDE variable names.)
2. **English ⇄ Hebrew translation** — no other system-wide dictation app does it.
3. **Best-in-class Hebrew** (ivrit.ai, planned) · **native, not Electron** · **offline-reliable**.

## Status
A working macOS app (dictation, EN+HE, translation modes, AI cleanup presets,
snippets, custom vocabulary, meeting notes, icy "Frostpane" UI) plus a
marketing/sales site and a full commercial plan.

**macOS is the only shipping platform.** iOS and Android are unbuilt scaffolds.
`windows/` is a **prototype that is deliberately not shipped**: it transcribes in
the cloud (it uploads your audio to OpenRouter), which contradicts point 1 above,
so it can't carry the Voicely name until it transcribes on-device. It shipped by
mistake on v0.2.0 and was pulled on 2026-07-16.
See **[docs/STATUS.md](docs/STATUS.md)** for the honest what's-done / what's-next, and
**[docs/plans/2026-06-21-voicely-master-strategy.md](docs/plans/2026-06-21-voicely-master-strategy.md)** for the plan.

## Build & run
```bash
./scripts/install.sh                 # build + sign + install to /Applications
open /Applications/Voicely.app
./scripts/make-dmg.sh                # → dist/Voicely.dmg (installer)
cd VoicelyCore && swift test         # pure-logic tests
```

macOS 14+ · Apple Silicon · requires Microphone, Accessibility, Input Monitoring.

## Layout
```
App/             the macOS app (Capture · Transcribe · Refine · Insert · UI · Settings)
VoicelyCore/     pure, tested logic (Swift package)
site/            icy marketing + sales landing page (static, deployable)
platforms/       cross-platform scaffold + plan (iOS / Windows / Android)
scripts/         install · make-dmg · make-signing-identity
docs/            plans · research · specs · STATUS
```

Built on the MIT-licensed [Pindrop](https://github.com/watzon/pindrop) +
[Hex](https://github.com/kitlangton/Hex), with
[WhisperKit](https://github.com/argmaxinc/WhisperKit) and
[FluidAudio](https://github.com/FluidInference/FluidAudio).

© 2026 Voicely. Free unlimited dictation; Pro $8/mo · $60/yr · $99 lifetime.
