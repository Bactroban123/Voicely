# Voicely — Master Strategy

> Synthesized from a 6-agent research sweep (web + GitHub), June 21 2026.
> Raw reports in [`docs/research/`](../research/). This is the commercial plan.

I now have full grounding. The codebase already has: the transcribe→clean→insert pipeline, the engine catalog (Parakeet/Whisper/Apple), cleanup modes including translate-EN/translate-HE stubs, and a locked "warm amber" design system — which directly conflicts with the research's "icy Frostpane" proposal. That conflict is a real decision I need to make. I have everything I need to write the master strategy.

# VOICELY — MASTER STRATEGY

*Synthesized from six research reports + the live codebase at `/Users/admin/Documents/Claude/Projects/Voicely`. This supersedes the "not for sale / single-user" framing in the repo's current `PRODUCT.md` and `README.md` — Voicely is now a commercial product. Where research and existing code conflict, the call is stated explicitly.*

---

## 0. The one-sentence thesis

> **Voicely is the private, bilingual dictation app for people who think in two languages.** On-device by default, system-wide, and the only dictation app that does real English⇄Hebrew. Wispr Flow sends your screen to the cloud; Voicely never leaves your Mac.

The market has split into "cloud + AI features" (Wispr, Willow, Aqua) and "on-device + privacy" (Superwhisper, MacWhisper, Apple). **Nobody owns both at once, and nobody does system-wide EN⇄HE.** That intersection is empty and defensible. Voicely already sits in it — the pipeline is built. The job now is to sharpen the wedge and ship it for sale.

---

## 1. Positioning + killer differentiators vs Wispr Flow

**Positioning line (site H1):** *"Speak any language. Type it in another. Privately, on your device."*
**Download button:** `Download for Mac` + a quiet `also iOS · Windows · Android`.

**The 4 killer differentiators (ranked, each a verifiable contrast):**

1. **Truly on-device, truly private — the headline.** Wispr captures *screenshots of your active window every few seconds* and ships them to third-party AI servers; Privacy Mode is OFF by default and a user who flagged it was *banned* ([embertype](https://embertype.com/blog/the-day-wispr-flow-banned-a-user/), [VocAI](https://vocai.net/blog/wispr-flow-review-privacy-2026/)). Voicely's audio never leaves the Mac. Free to claim — you already have it.

2. **English⇄Hebrew live translation — the category-definer.** No system-wide dictation rival does it. Speak Hebrew, English lands at the cursor (and vice-versa). This is the "iPhone moment": not a better dictation app, a *bilingual* one. Owns Israel + the Hebrew diaspora, a market Wispr treats as "1 of 100+ languages." The `translate-en`/`translate-he` cleanup modes are already stubbed in `CleanupModes.swift` — wire them to a real engine (§3).

3. **Best-in-class Hebrew via ivrit.ai.** Swap generic Whisper-Hebrew for ivrit.ai's `whisper-large-v3-turbo-ct2` / v2-d4 (3,300+ Hebrew hours, SoTA WER, Interspeech 2025 — [ivrit-ai on HF](https://huggingface.co/ivrit-ai)). Instantly the **best Hebrew dictation on any platform**. Add as a 5th option in `ModelCatalog.transcription`.

4. **Native, not Electron — won't freeze your editor, won't eat 800MB idle.** Wispr's Windows app is Electron: ~800MB RAM, 8% CPU *idle*, freezes VS Code/Notepad++ ([Voibe](https://www.getvoibe.com/resources/wispr-flow-review/)). Voicely is native Swift on Mac (CGEventTap, no Electron) and will be Rust-native on Windows. This is a real ad, and it doubles as the **developer/"vibe-coding" wedge** where Aqua is winning and Wispr is weak — a code-aware vocab + a "Prompt" mode tuned for Claude Code/Cursor (the `prompt` mode already exists).

**Reliability as a 5th, soft point:** Wispr logged 75+ outages since Dec 2025 ([Voibe](https://www.getvoibe.com/resources/is-wispr-flow-reliable/)); no cloud = no dictation. Voicely works offline. Say it.

**Pricing as positioning:** the market clusters at $144/yr. Voicely's on-device model = ~$0 marginal cost, so we **undercut on subscription AND offer a lifetime license Wispr refuses to** (§4). That margin structure is a moat cloud rivals can't copy.

---

## 2. Cross-platform architecture — THE DECISION

**Decision: tiered-by-OS, not one-stack-for-all. Voicely is a desktop product with mobile companions.** The "best dictation app" claim is won on macOS/Windows, where "type anywhere" actually works. Mobile is parity, not where we beat anyone.

**Reject** Flutter/KMP/React-Native-everything: ~70% of a dictation app's hard work *is* the OS-native glue (CGEventTap, AXUIElement, SendInput, IME `InputConnection`, keyboard extensions) that those frameworks abstract away. You'd write platform channels for everything regardless.

### Shared core
**Two-tier core, by reality:**
- **Today (Mac v1):** keep the existing **Swift `VoicelyCore` package** — pipeline, cleanup, vocab, snippets, hotkey processor are already built and tested (74 checks). Do not throw this away to chase a Rust rewrite before v1 ships.
- **When Windows/Android land (v3):** extract a **shared Rust core** (STT inference, VAD, resampling, AI-cleanup orchestration, translation routing, license client) compiled per target. Model it on **[cjpais/Handy](https://github.com/cjpais/Handy)** (Tauri + Rust + `whisper-rs` + `rdev` + `cpal` + `vad-rs`, MIT — the proven reference). The Swift core's *logic* ports cleanly; the value is reused, not the language.

### Per-platform engine + insertion choices

| Platform | Shell | STT engine | Insertion | Status |
|---|---|---|---|---|
| **macOS** | Native Swift menu-bar (have it) | Parakeet TDT (FluidAudio, English) + WhisperKit (Hebrew/multi) + Apple Speech | AX-first + clipboard Cmd-V + copy-only fallback (have it) | **v1 — ~80% built** |
| **iOS** | Native Swift app + Full-Access keyboard + share-ext | WhisperKit in **main app only** (keyboard ext is mic-blocked + ~70MB capped) | `textDocumentProxy.insertText` after app-handoff | v2 |
| **Windows** | **Tauri 2 + Rust** (Handy pattern) | `whisper-rs` + `sherpa-onnx` (fast English path) | Win32 `SendInput` via `enigo` + clipboard fallback | v3 |
| **Android** | **Native Kotlin IME** (`InputMethodService`) | `sherpa-onnx` (Android-first ONNX) via JNI | `InputConnection.commitText()` — native, reliable | v3 |

**The honest iOS constraint, designed-around not fought:** iOS keyboard extensions have **no mic access** and are memory-capped — confirmed unchanged in 2026 ([Apple App-Extension Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html)). The only pattern is "Full-Access keyboard taps mic → bounces to main app to record → types result back via App Group." There's a perceptible app-switch. Accept it. Apple is also shipping system-wide dictation itself ([TechBuzz](https://www.techbuzz.ai/articles/apple-takes-aim-at-wispr-flow-with-systemwide-dictation)) — **do not over-invest in iOS.** Android is the bright spot: a real system-wide voice keyboard genuinely works.

### Honest effort estimates (from the working Mac base)

| Work | Effort | Note |
|---|---|---|
| **Finish Mac v1** (Xcode build, translation wire-up, ivrit.ai, distribution, licensing) | **~4–6 weeks** | Highest ROI. Most of it exists. |
| Extract shared Rust core | ~3–5 wks | Only when going cross-platform |
| Windows (Tauri/Handy pattern) | ~4–6 wks | Lowest-risk new platform |
| Android IME | ~6–9 wks | Genuinely useful; greenfield |
| iOS (app + keyboard + share ext) | ~5–7 wks | Reuses Swift/WhisperKit; inherently limited UX |

**Ship order: Mac → iOS → Windows → Android.** (Mac first because it's nearly done and is where you out-private Wispr; iOS second because it reuses Swift and serves the bilingual mobile user; Windows/Android are the growth surface but greenfield.)

---

## 3. EN⇄HE translation — THE DECISION

**Architecture rule (non-negotiable):** translation is **a separate stage from transcription**. Whisper's `translate` task is **X→English only** and `large-v3-turbo` isn't trained for it at all ([whisper #649](https://github.com/openai/whisper/discussions/649)). Apple's `SpeechAnalyzer` is transcription-only. So the pipeline is always: **transcribe (spoken lang) → translate (chosen target) → insert.** This fits the existing `translate-en` / `translate-he` cleanup modes exactly — they're a routing decision after transcription.

**Decision: a 2-tier "Translate mode," on-device-first.**

1. **macOS/iOS default — Apple Translation framework.** Free, fully on-device/offline, Hebrew⇄English officially supported, RTL handled, App-Store-safe. This is the privacy-consistent default.
   - **The one gotcha (build it early):** `TranslationSession` can't be instantiated directly — it only comes from a SwiftUI view's `.translationTask` modifier. In a menu-bar app, host a **persistent zero-size hidden `NSHostingView`** that lives for the app's lifetime, drive it with `TranslationSession.Configuration`, bridge results via an async continuation. Use `LanguageAvailability.status()` + `prepareTranslation()` to **pre-download the Hebrew pack on first run** so users never hit the download sheet mid-dictation. It does **not** run in Simulator — validate on the M3 hardware. ([Swift Translation API deep-dive](https://www.polpiella.dev/swift-translation-api/))

2. **"Best quality" toggle + Windows/Android — OpenRouter LLM.** Voicely *already calls OpenRouter for cleanup* — translation is the identical call with a different system prompt. **LLMs lead clearly on Hebrew** (idiom, register, niqqud sense, EN/HE code-switching common in Israeli speech). Use **Gemini Flash (3.x)** or GPT-class. One API, all platforms, top Hebrew quality, fits the pay-as-you-go model. This is a near-free add given the existing pipeline.

3. **Fully-offline cross-platform fallback (Windows/Android, commercial-safe) — Opus-MT en-he/he-en** (Helsinki-NLP, **MIT/CC-BY**) via **CTranslate2 int8** (~40–80MB). **Avoid NLLB-200 in paid builds — it's CC-BY-NC (non-commercial), a real licensing blocker.** MADLAD-400 (Apache-2.0) is the heavier alternative.

**Why not SeamlessM4T as primary:** elegant (unified speech-translation, strong BLEU) but the Large model is 2.3B/desktop-only and it duplicates a pipeline you already have. Keep it as a possible v2+ "translate mode" experiment, not the shipping path.

**Hebrew quality note for transcription side:** pair translation with the ivrit.ai Hebrew model (§1.3) so the *source* Hebrew transcript is SoTA before it's translated or inserted. Handle RTL on insertion — don't force LTR; wrap with U+200F (RLM) only if a target app misrenders.

---

## 4. Monetization — THE DECISION

**Model: hybrid "subscription OR lifetime," with a genuinely generous free tier.** The on-device architecture means ~$0 marginal cost (only OpenRouter cleanup costs pennies), giving pricing freedom Wispr structurally lacks. Use it as a weapon.

| Tier | Price | Includes |
|---|---|---|
| **Free** | $0 | **Unlimited** on-device dictation (Wispr caps free at 2,000 words/week — this is the single best growth lever), EN+HE transcription, basic insertion. No translation, no AI cleanup, no custom vocab/snippets. |
| **Pro (sub)** | **$8/mo or $60/yr** | Translation (EN⇄HE), all cleanup modes (Clean/Polish/Prompt), custom vocabulary, snippets, priority models. |
| **Pro (lifetime)** | **$99 one-time** | Same Pro, perpetual, 1yr updates included. **Desktop-direct only** (license key). |

Rationale: undercut Wispr ($15/mo, $144/yr — [pricing](https://wisprflow.ai/pricing)), match Superwhisper ($8.49/mo), and add the lifetime option Wispr refuses — the sharpest pitch to the privacy crowd who hate cloud subscriptions.

### The exact stack

- **Desktop license sales — Polar.sh** (merchant-of-record: handles global VAT/sales tax; **open-source; native license keys** with `/activate` (device-limit) + `/validate` + offline grace). Fees 5%+50¢, buy-down available. The modern indie pick. **Avoid Lemon Squeezy** (Stripe acquired it; development stalled). Paddle is the fallback if you outgrow Polar but has no native keys. ([Polar MoR docs](https://polar.sh/docs/merchant-of-record/introduction), [license keys](https://polar.sh/docs/features/benefits/license-keys))
- **Mobile billing — RevenueCat** (wraps StoreKit 2 + Google Play Billing; cross-platform entitlements so Pro is Pro everywhere; **free under $2,500/mo MTR, then 1%**). iOS/Android subscriptions **must** use Apple/Google IAP. Lifetime stays desktop-only.
- **Marketing + checkout site — Next.js (App Router) on Vercel + Polar Checkout.** Reuse the exact Collabo stack. Buy button → Polar Checkout → webhook → store license + email installer links. Auto-update feeds (Sparkle appcast / Velopack) served from Vercel static or R2.

### Path to first paid download — per platform

**macOS (do this first, fastest revenue):**
1. [Human] Apple Developer Program **$99/yr**; create Developer ID Application + Installer certs; app-specific password for notarytool.
2. [Auto/CI] `codesign` (hardened runtime) → **[create-dmg](https://github.com/create-dmg/create-dmg)** → `notarytool submit --wait` → `stapler staple`.
3. [Auto] Embed **Sparkle 2**, generate EdDSA keys, publish appcast.xml.
4. [Human] Polar account + "Voicely Pro" product (lifetime $99 + sub).
5. [Auto] Vercel landing + Polar Checkout + webhook gating Pro on a valid license (`/validate`). **→ first paid download.**

**Windows:** [Human] Azure paid sub + **Azure Artifact Signing $9.99/mo** (SmartScreen-trusted, no $300+ EV token; *individual signup currently US/CA only* — else an OV cert via the entity). [Auto] **Velopack** installer+delta updates, signed. [Human] free **Microsoft Store** account (registration is free as of 2026) + **winget** manifest + direct download. Same Polar license check.

**iOS:** [Human] same $99 Apple account; build keyboard-ext + main app; RevenueCat + App Store Connect subscription products. Nail the **Full-Access disclosure + privacy labels** — "on-device, nothing uploaded" is a review *asset*. **→ first mobile subscriber.**

**Android:** [Human] Google Play account **$25 once**; build IME; RevenueCat + Play Billing; laxer review.

**Cheapest credible fixed cost: ≈ $99/yr (Apple) + ~$10/mo (Azure) + $25 once (Google).** Everything else is revenue-share that scales only when earning (Polar 5%+50¢, RevenueCat free <$2.5K/mo, MS Store free, winget free, Vercel hobby).

**What needs the human:** every dev-account signup, identity/payment verification, cert issuance, store submission. **What's automatable:** all signing, notarization, DMG/installer builds, appcast/feed generation, webhook→license plumbing, CI release.

---

## 5. The icy design system — A DELIBERATE OVERRIDE

**There is a direct conflict to resolve.** The live repo's `DESIGN.md` locks a **warm amber** identity ("VU-meter glow… deliberately not the Siri-blue voice-app reflex"). The research proposes a cool **"Frostpane"** icy system. **Decision: adopt Frostpane for the commercial product, and retire warm amber.** Reasons: (a) amber was chosen for a private single-user tool with no market to differentiate against; (b) the commercial wedge is *privacy + bilingual + intellectual calm*, and a cool, Linear-grade palette signals that far better than warmth; (c) "icy intellectual" is a sharper anti-Wispr visual stance. Update `DESIGN.md` and `Frostpane.swift`/`Frostpane.css` together. *(This is the one place I'm overriding existing committed design — flag it for founder sign-off, since it's a locked decision being reversed.)*

### Consolidated tokens (13 names, light + dark, same names)
`bg #FBFDFE` (faint blue cast) · `surface #F3F7FA` · `surface-2 #E8EFF4` · `hairline` (0.5px) · `text #0E1A24` (deep slate, never #000) · `text-muted` · `accent #3AA8C9` (glacier, links/interactive) · `accent-strong #1B7C9E` (pressed/focus/text-on-wash) · `accent-wash #E6F4F8` (the only tinted fill — selection/hover) · `live #22D3EE` (electric cyan — **the loudest color in the system, used ONLY while capturing audio**) · `success` (muted teal-green) · `warn` (brass) · `danger` (terracotta, never fire-engine red). Dark base = deep slate `#0A1219`, not black.

### Type — bilingual by design
- **Latin UI/display: Geist** (geometric, Swiss-rational, free variable font, mono sibling). **Mono: Geist Mono** (timers, model names, hotkey glyphs, the dev/"vibe-coding" signal).
- **Hebrew: Heebo** (Geist has *no Hebrew coverage* — never let it fall to a system fallback, the registers clash). Stack: `font-family: "Geist", "Heebo", system-ui;` — browser auto-picks Heebo for Hebrew codepoints. SwiftUI: detect script per transcript, set font, and `.environment(\.layoutDirection, .rightToLeft)` for Hebrew blocks. (Alternates: Assistant, Rubik.)
- **Scale:** 8 steps, 1.2 ratio, weights **400/500/600 only (never 700)**: `11 mono-caption · 12 caption · 13 label · 15 body · 17 body-lg · 20 title · 26 display · 34 hero`. Tighten display/hero −0.01em; line-height 1.5 body / 1.15 display.

### Material — "icy without cheesy glass"
- **Glass is a HUD-only material, used once.** The floating recording HUD is the single frosted surface (macOS 26 `.glassEffect(.regular, in: .capsule)`; below 26 bridge `NSVisualEffectView` `.hudWindow`/`.behindWindow`). Per Apple: never stack glass on glass, tint only for meaning. **Everything else opaque** — solid `surface` fills, 0.5px hairlines, depth from shadow not blur (`0 1px 2px rgba(14,26,36,.06)` resting; `0 8px 30px rgba(0,0,0,.12)` HUD only). Icy comes from the cool palette + hairlines, not from blurring everything.
- **Motion:** 120ms micro / 200ms standard / 320ms entrance, `cubic-bezier(0.22,1,0.36,1)` ease-out-quart. The **live orb "breathes"** (1.6s scale 1.0→1.06 + glow on `#22D3EE`) — the *only* ambient animation; waveform reacts to real RMS. Cleanup cross-fades cyan→success-green. No springs, no parallax, no confetti.

### Per-surface direction
- **Floating HUD (the hero, ~90% of perceived product):** 340px frosted capsule, centered-bottom on hotkey-down, auto-positions above the caret. Left: state orb (idle mic → live cyan orb → green sparkles). Center: live waveform during capture / streaming transcript during cleanup. Right: mono pill (timer / `EN`·`עב`·auto / `AI`). Hebrew renders RTL inside the same pill. *Note: this replaces the existing dark warm-near-black capsule.*
- **Menu-bar:** monochrome template soundwave-in-a-pane glyph; tints to system color idle, **solid live-cyan when capturing** (the menu bar itself confirms recording). Click → small frosted popover (≤280px): Clean/Polish/Prompt 3-segment, language indicator (EN/עב/auto), last-transcript snippet, quiet gear → Settings.
- **Settings:** opaque, two-pane, classic Mac (NOT glass). Sidebar = system vibrancy. Cards: `surface` fill, 0.5px hairline, radius 12. Groups: Dictation · Languages (incl. translation direction) · AI Cleanup · Vocabulary · Snippets · Account/License. Accent only on active row + primary buttons. (The repo's existing four-group single-pane Settings maps cleanly onto this.)
- **Onboarding:** 4 calm full-window steps on cool `bg`: (1) Welcome + value line, (2) grant Mic + Accessibility with a live "test your hotkey" that shows the real HUD — *this doubles as the permission grant and is the conversion moment*, (3) pick languages + translation, (4) cleanup mode. Four hairline dots, active = `accent`.
- **Marketing hero:** deep-slate `#0A1219` washing to `#1B3540`; oversized frosted HUD floating center with a real waveform mid-capture + glowing live orb. Geist 34px one-line headline; mono kicker `on-device · english ⇄ עברית`. One `accent-strong` "Download for Mac" + quiet other-platforms line. Whitespace *is* the premium signal.

**Slop traps to ban:** glassmorphism everywhere · neon-cyan glow on *static* elements (reserved for live state only) · pure #000/#fff · rainbow/mesh/aurora backgrounds · generic Inter + default Hebrew fallback · over-animation · centered-three-identical-feature-cards + gradient CTA. North stars: **Linear** (palette discipline), **Arc/Raycast** (floating-command-surface craft), **Things 3** (opaque native-Mac restraint).

---

## 6. Highest-leverage GitHub repos → mapped to needs

| Need | Repo | License | How to use it |
|---|---|---|---|
| **Mac pipeline twin (lift code now)** | [Arsture/whispree](https://github.com/Arsture/whispree) | **MIT** | Same exact stack (Swift menu-bar + WhisperKit + LLM cleanup + cursor-preserving insertion). Lift the WhisperKit wrapper, FIFO STT→LLM queue, "Can I Run" HW detection, dictionary sync. |
| **Benchmark UX (study, don't copy)** | [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk) | **GPL-3.0 ⚠️** | The 5.3k★ FOSS leader. **Do NOT paste its source into a paid closed app.** Read its `Package.swift` for the proven dep set and adopt the *libraries* (all permissive). |
| **Mac distribution toolkit (adopt all)** | [Sparkle](https://github.com/sparkle-project/Sparkle) (updates), [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (hotkey-recorder UI), LaunchAtLogin-Modern, [create-dmg](https://github.com/create-dmg/create-dmg), [indygreg/apple-code-sign-action](https://github.com/indygreg/apple-code-sign-action) (rcodesign, runs on Linux CI) | MIT/permissive | One-command signed+notarized releases in GitHub Actions. **Sparkle EdDSA needs a Developer-ID-signed app — the current self-signed cert blocks this; the $99 Apple account is a prerequisite.** |
| **EN→HE translation models** | [Helsinki-NLP/opus-mt-en-he](https://huggingface.co/Helsinki-NLP/opus-mt-en-he) + [opus-mt-tc-big-he-en](https://huggingface.co/Helsinki-NLP/opus-mt-tc-big-he-en) | **Apache-2.0** | The commercial-safe offline EN↔HE path (BLEU ~40 en-he). Whisper can only do HE→EN; this is the *only* way to do EN→HE offline. |
| **Offline NMT runtime** | [OpenNMT/CTranslate2](https://github.com/OpenNMT/CTranslate2) | MIT | `ct2-transformers-converter` → int8 → ~40–80MB, CPU. Thin Swift bridge. |
| **Best Hebrew transcription** | [ivrit-ai on HF](https://huggingface.co/ivrit-ai) | (check model card) | SoTA Hebrew ASR — the differentiator. Add to `ModelCatalog`. |
| **Cross-platform STT spine (v3)** | [k2-fsa/sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) | Apache-2.0 | The *only* engine with native Swift+Kotlin+C# bindings — the shared STT layer for Windows+Android so models are portable. |
| **Windows shell (v3)** | [cjpais/Handy](https://github.com/cjpais/Handy) (primary blueprint), [xarthurx/whisperi](https://github.com/xarthurx/whisperi), [painteau/Dictum](https://github.com/painteau/Dictum) | MIT | Tauri+Rust+whisper-rs+SendInput. Copy Handy's architecture. |
| **Android IME (v3)** | [woheller69/whisperIME](https://github.com/woheller69/whisperIME) / [alex-vt/WhisperInput](https://github.com/alex-vt/WhisperInput) | (check) | Fork a working Whisper IME, swap engine for sherpa-onnx. Solves the global-input problem you'd otherwise spend weeks on. |
| **Marketing/checkout site** | [nextjs/saas-starter](https://github.com/nextjs/saas-starter) | MIT | Same stack you run on Collabo. Switch Checkout to `payment` mode for lifetime + add the Polar license webhook. |

**Build order (highest leverage first):** Whispree lift → Sparkle/KeyboardShortcuts/create-dmg/rcodesign (get Developer ID first) → opus-mt + CTranslate2 + ivrit.ai → Next.js site + Polar → then sherpa-onnx + Handy/whisperIME when committing to Windows/Android.

**Two acted-on warnings:** (a) VoiceInk is GPLv3 — study, don't paste. (b) The self-signed cert blocks Sparkle auto-updates *and* notarization — the $99 Apple Developer ID is a hard prerequisite for shipping.

---

## 7. Phased roadmap

### v1 — macOS, SELLABLE (~4–6 weeks). *Realistic: Mac first.*
The pipeline is ~80% built (transcribe→clean→insert, engine catalog, cleanup modes, tested core). v1 = finish + commercialize.
**Scope:** finish the Xcode app shell · wire `translate-en`/`translate-he` to **Apple Translation framework** (hidden-NSHostingView, pre-download HE pack) + OpenRouter "best quality" toggle · add **ivrit.ai** Hebrew model · adopt Sparkle + KeyboardShortcuts + LaunchAtLogin · re-skin to **Frostpane** (founder sign-off on the amber→icy reversal) · streaming insertion + Command/agentic in-place editing (match Wispr Command Mode) · Polar license gating · Next.js landing on Vercel.
**Differentiators live at v1:** on-device privacy, EN⇄HE translation, best Hebrew, native-not-Electron, offline reliability — **all four+ killers ship in v1.**
**Needs from the human:** Apple Developer Program **$99/yr** + Developer ID certs + app-specific password · **Polar.sh** account + product setup · domain/Vercel (reuse Collabo infra) · **OpenRouter API key** in env · validate the Apple-Translation hidden-host on the M3 (won't run in Simulator).
**Distribution:** direct DMG (Developer ID + notarized + Sparkle); skip Mac App Store at launch (sandbox fights CGEventTap/Accessibility, and direct = 0% Apple cut). Setapp later for incremental reach.

### v2 — iOS (~5–7 weeks).
**Scope:** native Swift app (full WhisperKit dictation) + Full-Access keyboard (mic-handoff to main app) + share-sheet extension. Apple Translation framework reused. RevenueCat subscriptions (no lifetime on mobile).
**Needs from the human:** same $99 Apple account · **RevenueCat** account + App Store Connect subscription products · nail Full-Access disclosure + privacy labels ("on-device, nothing uploaded" = review asset) · App Review submission.
**Caveat to set expectations:** iOS can never be true system-wide dictation, and Apple is shipping its own — this is a *companion*, not the flagship. Ship it for the bilingual mobile user, don't over-invest.

### v3 — Windows + Android (~10–15 weeks combined).
**Scope:** extract the **shared Rust core** (~3–5 wks), then **Windows** Tauri/Handy shell (whisper-rs + sherpa-onnx, SendInput) and **Android** Kotlin IME (sherpa-onnx via JNI, `commitText`). Offline EN⇄HE via Opus-MT + CTranslate2 here (no Apple framework); OpenRouter for premium. This is where you take Wispr's market with the offline + native (anti-Electron) story.
**Needs from the human:** **Azure** paid sub + **Azure Artifact Signing $9.99/mo** (or OV cert if outside US/CA) · free **Microsoft Store** account + **winget** submission · **Google Play** account **$25 once** · RevenueCat (already set up) for Android billing.

**Cumulative human cost across all phases:** Apple $99/yr · Azure ~$10/mo · Google $25 once · everything else revenue-share. **≈$99/yr + ~$10/mo to be on all four platforms.**

---

## Decisions log (the calls made, no hedging)
1. **Architecture:** tiered-by-OS, desktop-first. Keep Swift core for Mac v1; extract Rust core only at v3. **Reject** any single cross-platform framework.
2. **Translation:** separate stage from transcription. Apple Translation framework default (Mac/iOS), OpenRouter LLM for quality + Windows/Android, Opus-MT offline fallback. **Reject** NLLB (non-commercial) and Whisper-translate (English-only).
3. **Monetization:** free-unlimited-on-device + $8/mo·$60/yr + $99 lifetime. Polar (desktop) + RevenueCat (mobile). **Reject** Lemon Squeezy.
4. **Design:** **override the locked warm-amber identity → adopt icy "Frostpane."** Geist + Heebo bilingual type. Glass HUD-only. *(Founder sign-off requested — this reverses a committed lock.)*
5. **Ship order:** Mac → iOS → Windows → Android.

**Files this strategy will touch in the repo:** `/Users/admin/Documents/Claude/Projects/Voicely/PRODUCT.md` and `README.md` (remove "not for sale / single-user"), `/Users/admin/Documents/Claude/Projects/Voicely/DESIGN.md` (amber→Frostpane), `VoicelyCore/Sources/VoicelyCore/ModelCatalog.swift` (add ivrit.ai Hebrew), `CleanupModes.swift` (translate modes already present — wire to engine), plus new `App/Translate/`, `App/License/`, and `Frostpane.swift`/`Frostpane.css` token files.

**The single sentence that wins:** *Wispr Flow is a cloud service wearing a native-app costume. Voicely is on-device, bilingual, and native — that is the wedge, and it ships in v1 on Mac.*