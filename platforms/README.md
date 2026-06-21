# Voicely — Cross-platform scaffold

> Start-here for the non-Mac platforms. The architecture is **decided** (master
> strategy §2): **tiered-native, desktop-first** — reject one-size-fits-all
> frameworks because ~70% of a dictation app is OS-native glue (global hotkey,
> system-wide text insertion, IME/keyboard extensions) that frameworks abstract
> away anyway. Ship order: **Mac (done) → iOS → Windows → Android.**

These folders are intentionally empty except for this plan. Each is weeks of work;
none is built. The Mac app (`/App`, `/VoicelyCore`) is the working reference.

## Shared core
- **Now:** the Swift `VoicelyCore` package (pipeline, cleanup modes, vocab,
  snippets, hotkey state machine — 92 tests) is the Mac/iOS shared core.
- **v3:** extract a **Rust** core (STT inference, VAD, resample, cleanup
  orchestration, translation routing, license client) compiled per target.
  Blueprint: **[cjpais/Handy](https://github.com/cjpais/Handy)** (Tauri + Rust +
  `whisper-rs` + `rdev` + `cpal` + `vad-rs`, MIT). The Swift core's *logic* ports;
  reuse the design, not the language.

## `ios/` — v2 (reuses Swift + WhisperKit)
- Native SwiftUI app does full WhisperKit dictation; a **Full-Access keyboard
  extension** + **share-sheet extension** reach other apps.
- Hard constraint (unchanged in 2026): keyboard extensions have **no mic access**
  and are memory-capped → pattern is "keyboard taps mic → hands off to main app to
  record → types result back via App Group." A perceptible app-switch; accept it.
- Translation: reuse Apple Translation framework. Billing: **RevenueCat** (no
  lifetime on mobile). Apple is shipping its own system dictation — ship iOS as a
  *bilingual companion*, don't over-invest.

## `windows/` — v3 (lowest-risk new platform)
- **Tauri 2 + Rust**, copy the **Handy** architecture. STT: `whisper-rs` +
  `sherpa-onnx` (fast English). Insertion: Win32 `SendInput` via `enigo` +
  clipboard fallback. Updates: **Velopack**. Signing: **Azure Trusted/Artifact
  Signing** (~$10/mo, SmartScreen-trusted, no $300 EV token).
- This is where the **offline + native (anti-Electron)** story takes Wispr's market.

## `android/` — v3 (greenfield but genuinely system-wide)
- Native **Kotlin IME** (`InputMethodService`). STT: **sherpa-onnx** via JNI
  (Android-first ONNX). Insertion: `InputConnection.commitText()` — native, reliable.
- Fork a working Whisper IME ([woheller69/whisperIME](https://github.com/woheller69/whisperIME))
  and swap the engine for sherpa-onnx. Billing: RevenueCat + Play Billing.

## Translation (all non-Apple platforms)
- Premium: OpenRouter LLM (same call as Mac cleanup). Offline EN⇄HE:
  **Opus-MT** (Helsinki-NLP, Apache-2.0) via **CTranslate2** int8 (~40–80MB).
  **Avoid NLLB-200** (CC-BY-NC, non-commercial). Whisper alone can't do EN→HE.

## The shared STT spine for v3
**[k2-fsa/sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)** (Apache-2.0) is the
only engine with native Swift + Kotlin + C# bindings — use it as the portable STT
layer so models work across Windows + Android.

See [`../docs/plans/2026-06-21-voicely-master-strategy.md`](../docs/plans/2026-06-21-voicely-master-strategy.md) §2 for the full decision + effort estimates.
