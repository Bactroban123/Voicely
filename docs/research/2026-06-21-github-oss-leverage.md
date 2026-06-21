# Research: github-oss-leverage

I now have verified, decision-grade data across all six domains. Here's my synthesis.

---

# Voicely — What to build on from GitHub (verified June 2026)

All facts below were verified by reading the live repos / model cards this session. Star counts and dates are current.

## TIER 1 — Highest leverage (borrow code directly, this week)

### 1. Whispree — your architectural twin, MIT, copy liberally
**https://github.com/Arsture/whispree** · ~112★ · **MIT** · Swift 95% · active (v0.1.15, Jun 11 2026)
This is the closest match to Voicely's *exact* stack: native macOS menu-bar Swift app, **WhisperKit (CoreML+ANE) local STT**, LLM post-processing, global hotkey, smart text insertion that holds cursor position across window switches, custom dictionaries with iCloud sync. Because it's MIT and uses the same WhisperKit path you already run, you can lift modules wholesale.
**Take:** the WhisperKit integration wrapper, the FIFO STT→LLM queue manager (parallel transcribe + clean), cursor-preserving text insertion, the "Can I Run" hardware-capability detection, domain word-set dictionary sync. Maps 1:1 onto Voicely's transcribe→cleanup→insert pipeline.

### 2. VoiceInk — the market-leading FOSS dictation app, study don't copy (GPLv3)
**https://github.com/Beingpax/VoiceInk** · **5.3k★** · **GPL-3.0** · Swift 99.7% · very active (v1.79, May 23 2026, 124 releases)
The reference implementation and your real benchmark. Same Parakeet path as you (**FluidAudio**), plus whisper.cpp, context-aware mode switching, intelligent app detection, personal dictionary. **GPLv3 is the catch** — you cannot copy its code into a closed-source paid product. Use it to study patterns and UX, and crucially to **read its `Package.swift` for the proven dependency set**: it ships Sparkle (updates), **KeyboardShortcuts** (sindresorhus), **LaunchAtLogin**, and **SelectedTextKit** (read selected text for context). Adopt those *libraries* (each is MIT/permissive) rather than VoiceInk's own source.

### 3. The macOS distribution toolkit — adopt all four (permissive)
- **Sparkle** — auto-update: **https://github.com/sparkle-project/Sparkle** · ~7k★ · MIT-style. Sparkle 2 supports sandboxing + SwiftUI. The standard; wire it to a static appcast XML on your marketing site's CDN. *Note: Sparkle needs a Developer-ID-signed app for EdDSA validation to be meaningful — your current self-signed cert blocks frictionless updates; budget for a $99/yr Apple Developer account.*
- **KeyboardShortcuts** (sindresorhus) — **https://github.com/sindresorhus/KeyboardShortcuts** · ~2.8k★ · MIT. SwiftUI `Recorder` view + UserDefaults persistence + system-conflict warnings. Replace any hand-rolled hotkey-recorder UI with this; keep your CGEventTap for the actual capture.
- **LaunchAtLogin-Modern** (sindresorhus) · MIT — one-line "start at login."
- **DMG + notarize:** **https://github.com/create-dmg/create-dmg** (styled DMG) plus **https://github.com/indygreg/apple-code-sign-action** (rcodesign — signs/notarizes/staples, *runs on Linux runners* so CI is cheap). Alternative all-in-one: **insidegui/dmgdist**. Wire into GitHub Actions for one-command signed releases.

---

## TIER 2 — The translation engine (this is the hard architectural decision)

**Critical finding that changes your plan:** Whisper and **WhisperKit only translate X→English** — the decoder was never trained for any other target. Confirmed by Argmax (WhisperKit issue #108: "Whisper doesn't support any target language other than English"). So:
- **Hebrew→English translation: free.** Just call WhisperKit/whisper.cpp with `task=translate`. You already have the model.
- **English→Hebrew: needs a separate NMT model.** Whisper cannot do it.

### 4. OPUS-MT (Helsinki-NLP) — the EN↔HE translation models, Apache-2.0
- **https://huggingface.co/Helsinki-NLP/opus-mt-en-he** — verified to exist, **Apache-2.0**, BLEU **40.1** / chrF 0.609 on Tatoeba (genuinely usable quality for EN→HE).
- **https://huggingface.co/Helsinki-NLP/opus-mt-tc-big-he-en** — the larger HE→EN model if you want better-than-Whisper quality in that direction too.

### 5. CTranslate2 — the runtime to ship those models on-device
**https://github.com/OpenNMT/CTranslate2** · ~3.7k★ · **MIT** · C++/Python. Convert OPUS-MT with one command (`ct2-transformers-converter --model Helsinki-NLP/opus-mt-en-he --output_dir ...`), int8-quantize to ~40–80MB, run on CPU. This is the standard offline-NMT path. **Mapping:** add a thin Swift bridge to the CTranslate2 C++ lib; pipeline becomes `Whisper(transcribe) → [if translate mode] OPUS-MT via CTranslate2 → insert`.

### 6. sherpa-onnx — the cross-platform STT spine (strategic, see Tier 3)
**https://github.com/k2-fsa/sherpa-onnx** · **13.1k★** · **Apache-2.0** · very active (releases Jun 18 2026). On-device STT/TTS/VAD with **prebuilt native bindings for Swift (iOS+macOS), Kotlin/Java (Android), and C# (Windows)** — the *only* engine here that covers all four of your target platforms with one API. It does **not** do translation (pair it with OPUS-MT/CTranslate2). If you commit to true cross-platform, sherpa-onnx is the unifying STT layer so you don't reimplement transcription per-OS.

---

## TIER 3 — Cross-platform clients (macOS is native; the other 3 are greenfield)

Reality check: **no single repo gives you mac+iOS+Android+Windows.** Two realistic paths:

**Path A — Native per platform (best UX, what VoiceInk/Voicely already do on Mac):**
- **iOS:** reuse your Swift/WhisperKit core directly; or sherpa-onnx ios-swiftui examples. (iOS can't do system-wide insertion — ship as a custom keyboard extension instead.)
- **Android:** fork a working Whisper IME. Best candidates, all GitHub: **woheller69/whisperIME** (system-wide `RecognitionService`), **alex-vt/WhisperInput** (offline voice keyboard), **j3soon/whisper-to-input** (mixed-language). These solve the Android global-input problem (IME) you'd otherwise spend weeks on. Swap their engine for sherpa-onnx to share models with desktop.
- **Windows:** **xarthurx/whisperi** (Tauri 2, Windows dictation, transcribe+clean+paste) — fork as your Windows shell.

**Path B — One Tauri codebase for all desktop (fastest to "cross-platform" checkbox):**
- **OpenWhispr** — **https://github.com/OpenWhispr/openwhispr** · **3.9k★** · **MIT** · Electron + React 19 + TS + Tailwind v4. Already ships **macOS/Windows/Linux** installers, local (Whisper+Parakeet) + cloud BYOK (GPT-5/Claude/Gemini/Groq), diarization, MCP. The single highest-leverage *cross-platform* fork if you'd accept Electron over native. **Downside:** Electron loses the native "bright icy" polish you want on Mac — keep your Swift app as the flagship, use OpenWhispr as the Windows/Linux beachhead.
- **adityamiskin/hermes** — Tauri 2, React+shadcn, multi-backend STT (whisper-rs/faster-whisper/cloud), tray + global hotkey + overlay pill. MIT-ish, but ~0★ and early (v0.1.5) — borrow patterns, don't depend on it.
- **Tauri is desktop-only** — it does **not** target Android for this use case, so Path B still needs a native Android IME.

---

## TIER 4 — Sell it (payments + licensing)

### 7. Licensing backend — two options, pick by control vs. speed
- **Lemon Squeezy License API** (fastest, merchant-of-record handles VAT/tax): docs at https://docs.lemonsqueezy.com/api/license-api — `POST /v1/licenses/{validate,activate,deactivate}`. Sample integration: **https://github.com/Popinek/lemonsqueezyLicense** (MIT, Flask + CLI). Hard-code your `product_id`/`store_id` in the client check (their docs explicitly warn about this). Best for a solo founder who wants zero tax/compliance work.
- **Keygen CE** (self-hosted, more control, Fair Source→Apache after 2yr): **https://github.com/keygen-sh/keygen-api**. The proven money path is their official **https://github.com/keygen-sh/example-stripe-integration** (Node.js): `Stripe Checkout → webhook → Keygen creates license → email key`. Set `authenticationStrategy: "LICENSE"` so desktop machine-activation works.

### 8. Marketing site + checkout — official Next.js SaaS starter
**https://github.com/nextjs/saas-starter** · **15.9k★** · **MIT** · Next.js 16 + Stripe + Drizzle/Postgres + shadcn/ui. Ships pricing page wired to **Stripe Checkout**, Customer Portal, auth, dashboard, animated marketing landing. You already run this exact stack on Collabo.ink, so it's a zero-learning-curve sales site. Add the license-key webhook (from #7) on top of its existing `checkout.session.completed` handler. *For one-time license sales rather than subscriptions, switch its Checkout mode to `payment` and generate a key on the webhook.*

---

## Ranked build order (highest leverage first)
1. **Whispree (MIT)** — lift WhisperKit pipeline + insertion into Voicely now.
2. **Sparkle + KeyboardShortcuts + LaunchAtLogin + create-dmg/rcodesign** — productionize Mac distribution this week (get a Developer ID first).
3. **OPUS-MT `en-he` + CTranslate2** — the *only* way to ship English→Hebrew; this is your headline differentiator vs. Wispr Flow.
4. **Next.js saas-starter + Lemon Squeezy License API** — fastest path to actually charging money.
5. **sherpa-onnx** — adopt as the shared STT engine *if and when* you commit to Android/Windows, so models are portable.
6. **OpenWhispr (Electron) or whisperi (Tauri)** for Windows; **woheller69/whisperIME** fork for Android — only after the Mac flagship + payments are live.

**Two warnings to act on:** (a) VoiceInk is **GPLv3** — study it, copy libraries it uses, but do not paste its source into your paid closed app. (b) Your **self-signed cert blocks Sparkle auto-updates and notarization** — a $99/yr Apple Developer ID is a prerequisite for shipping Tier-1 distribution.

### Sources
- https://github.com/Arsture/whispree
- https://github.com/Beingpax/VoiceInk
- https://github.com/sparkle-project/Sparkle
- https://github.com/sindresorhus/KeyboardShortcuts
- https://github.com/create-dmg/create-dmg
- https://github.com/indygreg/apple-code-sign-action
- https://huggingface.co/Helsinki-NLP/opus-mt-en-he
- https://huggingface.co/Helsinki-NLP/opus-mt-tc-big-he-en
- https://github.com/OpenNMT/CTranslate2
- https://github.com/k2-fsa/sherpa-onnx
- https://github.com/OpenWhispr/openwhispr
- https://github.com/adityamiskin/hermes
- https://github.com/xarthurx/whisperi
- https://github.com/woheller69/whisperIME
- https://github.com/alex-vt/WhisperInput
- https://github.com/j3soon/whisper-to-input
- https://github.com/argmaxinc/WhisperKit/issues/108
- https://docs.lemonsqueezy.com/api/license-api
- https://github.com/Popinek/lemonsqueezyLicense
- https://github.com/keygen-sh/keygen-api
- https://github.com/keygen-sh/example-stripe-integration
- https://github.com/nextjs/saas-starter