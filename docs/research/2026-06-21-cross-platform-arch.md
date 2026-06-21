# Research: cross-platform-arch

I now have decision-grade coverage across all four platforms, the cross-platform stack question, translation, and payments. Here's the complete report.

---

# Voicely Cross-Platform Architecture — Decision-Grade Report (June 2026)

## TL;DR — the strategy

**Do NOT pick one cross-platform stack for all four targets. Use a tiered approach split by where the OS *lets* you do dictation:**

- **macOS + Windows (the real product): native-ish desktop via Tauri 2 + Rust shared core.** This is where "type anywhere" actually works, and where Wispr Flow lives. Your existing macOS Swift app is a sunk asset — keep it shipping while you build the Rust core, then either keep Swift on Mac or fold Mac into Tauri.
- **iOS: native Swift, custom-keyboard + share-extension app — accept it can never be true system-wide dictation.** Apple structurally forbids it. Reuse your existing Swift/WhisperKit code.
- **Android: native Kotlin IME (input method) — this one genuinely works system-wide.** Android is the *only* mobile OS where you can be a real "voice keyboard."

The honest headline: **Voicely is a desktop product with mobile companions.** The "best dictation app, better than Wispr Flow" claim is won on macOS/Windows. Mobile is table-stakes parity, not where you beat anyone.

Your wedge vs Wispr Flow is concrete and verifiable: **Wispr Flow is cloud-only with no offline mode — voice data leaves the device every session** ([Weesper](https://weesperneonflow.ai/en/blog/2026-02-09-wispr-flow-review-cloud-dictation-2026/), [getvoibe](https://www.getvoibe.com/resources/wispr-flow-review/)). Voicely is on-device/private. Lead with that.

---

## Per-platform architecture (the 5 hard parts)

### 1. macOS — *you already have this; it's the strongest platform*

| Concern | Recommendation |
|---|---|
| **On-device STT** | Keep **WhisperKit** (now part of `argmaxinc/argmax-oss-swift` v1.0.0, May 2026 — CoreML/ANE, MIT) for Hebrew + multilingual; keep **FluidAudio/Parakeet TDT-0.6b-v3 CoreML** for fast English (≈110× real-time on M4 Pro, 2.1% WER LibriSpeech). **Critical:** Parakeet v3 covers 25 *European* languages — **Hebrew is NOT included**, so Whisper stays mandatory for your Hebrew story. |
| **Global activation** | Keep CGEventTap (what you have). It's the correct API. |
| **System-wide insertion** | Keep clipboard-paste + Accessibility. The reliable production pattern (used by OpenLess, superwhisper) is: AXUIElement to find focused element → clipboard + Cmd-V → copy-only fallback. CGEvent Cmd-V has gotten flaky in recent macOS; keep the AX fallback path. |
| **Menu-bar presence** | `NSStatusItem` (you have it). |
| **Permissions** | Microphone + Accessibility at launch (you have it). |

**Sources:** [argmax-oss-swift](https://github.com/argmaxinc/WhisperKit), [FluidAudio](https://github.com/FluidInference/FluidAudio), [parakeet-tdt-0.6b-v3-coreml](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml), [OpenLess](https://github.com/Open-Less/openless).

### 2. Windows — *the biggest growth surface; fully feasible*

| Concern | Recommendation |
|---|---|
| **On-device STT** | **whisper.cpp via `whisper-rs`** (Rust binding) for cross-platform parity with macOS Whisper. Add **sherpa-onnx** as the fast English path — benchmarks show sherpa-onnx is dramatically faster than whisper.cpp on some targets, and it runs Parakeet/NeMo models on Windows where FluidAudio (CoreML) can't. |
| **Global activation** | Win32 `RegisterHotKey` / low-level keyboard hook (`rdev` crate handles this cross-platform). |
| **System-wide insertion** | **Win32 `SendInput`** (via the `enigo` crate) for keystroke injection, with clipboard-paste fallback. This is the proven path — every Windows dictation tool below uses it. |
| **Tray presence** | Tauri tray plugin / Win32 `Shell_NotifyIcon`. |
| **Permissions** | Microphone consent prompt; no special elevation needed for SendInput. |

**Real repos to copy from (all do exactly this):** [Handy](https://github.com/cjpais/Handy) (Tauri+Rust+whisper-rs+`rdev`+`cpal`+`vad-rs`, MIT, the category leader), [whisperi](https://github.com/xarthurx/whisperi) (Tauri, SendInput, pastes into terminals), [Dictum](https://github.com/painteau/Dictum) (Rust, `enigo`/SendInput), [EasyDictate](https://github.com/charleslukowski/easydictate) (C#/Whisper.net for the .NET-curious).

### 3. iOS — *be brutally honest: no true system-wide dictation exists*

This is the hard constraint and you must design around it, not fight it:

- **iOS custom keyboard extensions have NO microphone access** — confirmed in Apple's own docs and unchanged in 2026 ([Apple App Extension Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html), [intent/Medium](https://medium.com/@inFullMobile/limitations-of-custom-ios-keyboards-3be88dfb694)). Keyboard extensions are also memory-capped (~70 MB) — too small to host Whisper large-v3.
- The **only** workaround is the "Full Access keyboard + main-app handoff" / **share-sheet** pattern: the keyboard opens the main app (or App Group shared container) to record, the main app runs STT, and the result is committed back to the field. This is what every iOS dictation app actually does ([fluidvox](https://www.fluidvox.com/best-voice-typing-apps-iphone-2026), [voicekeyboardpro](https://voicekeyboardpro.com/blog/iphone-voice-to-text.html)).

**What's actually possible on iOS:**
1. **Main-app dictation** — full WhisperKit power inside Voicely's own app (this is real and great).
2. **Custom keyboard** that, on tapping the mic, jumps to the main app to record, then types the result back via the App Group + `textDocumentProxy.insertText`. There's a perceptible app-switch — accept it.
3. **Share Sheet extension** — "share to Voicely → speak → get text back."
4. **Note:** Apple is shipping system-wide dictation itself in OS-level updates, narrowing this further ([TechBuzz](https://www.techbuzz.ai/articles/apple-takes-aim-at-wispr-flow-with-systemwide-dictation)). Don't over-invest in iOS.

**STT:** WhisperKit in the main app. Memory cap means the *keyboard extension itself* can never host the model.

### 4. Android — *the bright spot: real system-wide voice keyboard*

Android's `InputMethodService` (IME) framework is the opposite of iOS — **your keyboard runs system-wide, gets microphone access, and commits text into any focused field** via `InputConnection.commitText()` ([Android docs](https://developer.android.com/develop/ui/views/touch-and-input/creating-input-method), [InputMethodService](https://developer.android.com/reference/android/inputmethodservice/InputMethodService)). This is exactly how 2026 AI keyboards like Dictaboard work ([droid-life](https://www.droid-life.com/2026/01/29/dictaboard-ai-keyboard-android/)).

| Concern | Recommendation |
|---|---|
| **On-device STT** | **sherpa-onnx** (k2-fsa) — Android-first, runs Whisper + Parakeet/NeMo via ONNX Runtime, 12 language bindings, explicitly built for embedded/Android. Fastest option on Android per the 16-model benchmark. Fallback: `whisper.cpp` JNI. |
| **Global activation** | Build a real **IME** (`InputMethodService`) with a mic button = your "hotkey." Optionally an `AccessibilityService` for a floating global trigger. |
| **System-wide insertion** | `InputConnection.commitText()` — native, reliable, no clipboard hacks. |
| **Background presence** | Foreground service for the IME. |
| **Permissions** | `RECORD_AUDIO`; user enables the keyboard in system settings (one-time). |

**Sources:** [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx), [offline STT benchmark (16 models)](https://voiceping.net/en/blog/research-offline-speech-transcription-benchmark/).

---

## The big decision: native-per-platform vs one cross-platform stack

**Recommendation: Tauri 2 + a shared Rust core for the desktop product; native Swift/Kotlin shells for mobile.** Reasoning:

**Why not "one stack to rule all four":**
- **Flutter / KMP / React Native cannot give you the platform-specific native plumbing** that *is* the product — CGEventTap, AXUIElement, SendInput, IME `InputConnection`, keyboard extensions. In a dictation app, ~70% of the hard work is exactly the OS-native glue these frameworks abstract away from you. You'd be writing platform channels for everything anyway.
- **Tauri 2 does support all 5 targets** (macOS/Windows/Linux/iOS/Android from one codebase, [Tauri 2](https://v2.tauri.app/)) and its global-shortcut plugin works on desktop — but its mobile webview model adds no value for a keyboard/IME, where you need pure-native UI and OS hooks. The audio plugins exist ([tauri-plugin-audio-recorder](https://github.com/brenogonzaga/tauri-plugin-audio-recorder)) but a Tauri webview can't *be* an Android IME or an iOS keyboard extension.

**The shared-core plan (what's actually shared vs platform-specific):**

| Layer | Shared? | How |
|---|---|---|
| STT inference, VAD, audio resampling, model management | ✅ **Shared Rust core** | `whisper-rs` + `sherpa-onnx` + `vad-rs` + `rubato`, compiled per target. On Apple, optionally bridge to WhisperKit/CoreML for ANE speed. |
| AI cleanup (Clean/Polish/Prompt), OpenRouter calls, custom vocab, snippets, translation orchestration | ✅ **Shared Rust core** | Pure logic — your highest-value, most-reused code. |
| License/auth/sync client | ✅ Shared Rust | |
| Global hotkey / activation | ⚠️ **Platform-specific** | `rdev`/CGEventTap (desktop), IME mic (Android), keyboard-ext (iOS) |
| Text insertion | ⚠️ **Platform-specific** | AX+paste (mac), SendInput (win), `commitText` (Android), `textDocumentProxy` (iOS) |
| Menu-bar/tray/IME UI | ⚠️ **Platform-specific** | Native each |

**Concrete stack:**
- **Desktop (macOS + Windows + Linux free):** **Tauri 2 + Rust core + React/Tailwind UI**, modeled directly on **Handy** (cjpais/Handy — the proven MIT reference: Tauri, `whisper-rs`, `rdev`, `cpal`, `vad-rs`, multi-platform). For the "bright icy intellectual" UI, the webview gives you full design control with CSS, which is far easier than SwiftUI/Compose to make pixel-beautiful.
  - *Migration note:* keep shipping your existing Swift macOS app as v1. Build the Rust core as a library first (it's the shared asset). Then decide: keep Swift on Mac (best ANE/WhisperKit integration) and Tauri on Windows, **or** unify Mac into Tauri once the core is proven. Either way the Rust core is reused.
- **iOS:** **native Swift**, reuse your WhisperKit code + the `argmax-oss-swift` SDK. Main-app dictation + Full-Access keyboard handoff + share extension.
- **Android:** **native Kotlin IME** wrapping the shared Rust core via JNI (sherpa-onnx). This is a fresh build but mechanically well-trodden.

**Why this beats Flutter/KMP-everything:** you write the valuable logic once (Rust), you get native OS hooks where they matter, and you get a CSS-grade beautiful desktop UI. KMP would be the alternative if you were UI-light and Android-heavy, but your product is desktop-first and design-forward — Tauri+Rust wins.

### Realistic build-effort estimate (from a working macOS base)

| Platform | Effort | Notes |
|---|---|---|
| **Extract shared Rust core** | ~3–5 weeks | STT/VAD/cleanup/translation as a reusable lib. Highest leverage. |
| **Windows (Tauri)** | ~4–6 weeks | Mostly assembling Handy-pattern pieces + your core + UI. Lowest risk, highest ROI. |
| **macOS (keep Swift OR re-Tauri)** | 0 (keep) / ~3–4 wks (port) | Keep Swift unless you want one codebase. |
| **Android IME** | ~6–9 weeks | New IME + JNI + sherpa-onnx + UI. Genuinely useful. |
| **iOS** | ~5–7 weeks | App + keyboard-ext + share-ext. Reuses Swift/WhisperKit. Inherently limited UX. |

Ship order: **Windows → Android → iOS.** Windows is where you take Wispr Flow's market with an offline story.

---

## (b) English↔Hebrew TRANSLATION

Two viable on-device paths:

1. **Cascaded Whisper → NLLB** (most flexible): Whisper transcribes (Hebrew model: **`ivrit-ai/whisper-large-v3-turbo-ct2`**, SOTA Hebrew, [ivrit-ai](https://huggingface.co/ivrit-ai)) → **NLLB-200** translates He↔En on-device. Slower, larger, but modular and runs everywhere via ONNX/CT2.
2. **SeamlessM4T v2** (Meta, unified speech-translation): outperforms Whisper+NLLB on FLEURS S2TT (26.6 vs ~20.4 BLEU) and is far more noise-robust ([HF](https://huggingface.co/facebook/seamless-m4t-v2-large), [ionio](https://www.ionio.ai/blog/exploring-speech-to-speech-translation-with-seamlessm4t-v2)). **Medium variant (~311M speech encoder)** is the mobile-friendly one; Large is 2.3B — desktop-only.

**Recommendation:** Ship cascaded **Whisper(ivrit-ai)→NLLB** first (modular, reuses your Whisper pipeline, Hebrew-strong). Evaluate SeamlessM4T-Medium as a v2 "translate mode" toggle. Note: for *premium* Hebrew accuracy, cloud **Soniox** hits 1.25% WER vs OpenAI's 3.24% ([Soniox](https://soniox.com/compare/soniox-vs-openai/hebrew)) — offer it as an optional cloud tier, but keep on-device as the default/privacy story.

---

## (d) Payments / licensing

For a paid desktop+mobile app sold worldwide, **use a Merchant-of-Record** (handles global sales tax/VAT — essential since you're selling from a Wyoming/foreign entity into many jurisdictions):

- **Recommended: Polar** (4% + $0.40, MoR, developer-first, license-key management) **or Paddle/Lemon Squeezy** (5% + $0.50, MoR, mature license keys + offline activation). Lemon Squeezy works but indie sentiment has soured post-Stripe-acquisition; Paddle is the safe incumbent; **Polar is the modern pick** ([fintechspecs](https://fintechspecs.com/blog/stripe-vs-paddle-vs-lemon-squeezy-vs-polar-merchant-of-record-b2b-saas/), [buildmvpfast](https://www.buildmvpfast.com/blog/lemon-squeezy-vs-polar-paddle-merchant-of-record-2026)).
- **App Store reality:** iOS/Android *must* use Apple/Google IAP (30%/15%) for in-app purchases — sell mobile via IAP, sell desktop via the MoR with cross-platform license keys. Plain Stripe only if you want to own tax compliance yourself (don't, at your stage).
- Architecture: license key + periodic online activation check, with offline grace period (Paddle/Polar both support this).

---

## Reference projects to clone the architecture from

- **[cjpais/Handy](https://github.com/cjpais/Handy)** — your desktop blueprint (Tauri+Rust+whisper-rs, MIT). Copy this.
- **[xarthurx/whisperi](https://github.com/xarthurx/whisperi)**, **[painteau/Dictum](https://github.com/painteau/Dictum)** — Windows SendInput patterns.
- **[Open-Less/openless](https://github.com/Open-Less/openless)** — mac+win paste/AX insertion.
- **[k2-fsa/sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)** — Android/Windows STT engine.
- **[primaprashant/awesome-voice-typing](https://github.com/primaprashant/awesome-voice-typing)** — curated list across all 5 OSes; mine it.
- **[moona3k/macparakeet](https://github.com/moona3k/macparakeet)** — Parakeet system-wide mac dictation reference.

**Sources:** [WhisperKit/argmax-oss-swift](https://github.com/argmaxinc/WhisperKit) · [FluidAudio](https://github.com/FluidInference/FluidAudio) · [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) · [Handy](https://github.com/cjpais/Handy) · [Tauri 2](https://v2.tauri.app/) · [Android IME docs](https://developer.android.com/develop/ui/views/touch-and-input/creating-input-method) · [iOS Custom Keyboard limits](https://medium.com/@inFullMobile/limitations-of-custom-ios-keyboards-3be88dfb694) · [Apple keyboard open-access](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard) · [Offline STT benchmark](https://voiceping.net/en/blog/research-offline-speech-transcription-benchmark/) · [SeamlessM4T v2](https://huggingface.co/facebook/seamless-m4t-v2-large) · [ivrit-ai Hebrew](https://huggingface.co/ivrit-ai) · [Soniox Hebrew](https://soniox.com/compare/soniox-vs-openai/hebrew) · [Wispr Flow cloud-only](https://weesperneonflow.ai/en/blog/2026-02-09-wispr-flow-review-cloud-dictation-2026/) · [MoR comparison](https://fintechspecs.com/blog/stripe-vs-paddle-vs-lemon-squeezy-vs-polar-merchant-of-record-b2b-saas/) · [KMP vs Flutter 2026](https://volpis.com/blog/is-kotlin-multiplatform-production-ready/)