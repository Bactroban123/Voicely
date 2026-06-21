# Research: competitive-teardown

I have comprehensive, well-sourced material across all required competitors plus the model/translation landscape. Compiling the decision-grade teardown.

---

# Competitive Landscape — Dictation Apps, June 2026
## What "market-best" requires, and how Voicely beats Wispr Flow

---

## 1. Wispr Flow — Full Teardown (the target)

**The market leader, and the one to beat.** Wispr Flow is the only major AI dictation tool on **all four platforms** (Mac, Windows, iOS, Android) as of April 2026, with subscription syncing across devices. That's its moat and its biggest vulnerability is below it.

**Pricing (verified on wisprflow.ai/pricing):**
- **Basic (Free):** 2,000 words/week Mac/Win, 1,000/week iPhone, Android "unlimited (limited time)". 100+ languages, custom dictionary, snippets, privacy mode, HIPAA-ready.
- **Pro:** $15/mo monthly, **$12/mo annual ($144/yr)** — unlimited words, Command Mode AI editing, early access, team tools.
- **Enterprise:** custom — SOC 2 Type II, ISO 27001:2022, enforced HIPAA/privacy, SSO/SAML, dashboards.
- Students: 3 months free + 50% off Pro.

**What makes it loved:** context-aware formatting (adapts tone/format per app), **Command Mode** (dictate edits like "make this a list"), 100+ languages, developer/IDE integrations, whisper-fast in-app paste, real enterprise compliance on all plans, cross-device dictionary/snippet sync.

**Weaknesses and complaints — this is Voicely's opening:**
- **Cloud-dependent, not on-device.** Every request: audio → Baseten (transcription) → OpenAI/Anthropic/Cerebras (cleanup) → stored in AWS us-east-1. ([VocAI](https://vocai.net/blog/wispr-flow-review-privacy-2026/))
- **Privacy scandal.** Context-awareness captures **screenshots of your active window every few seconds** and sends them to third-party AI servers. A Reddit user who flagged this was **banned** rather than answered. Privacy Mode is **OFF by default** for individuals. ([embertype](https://embertype.com/blog/the-day-wispr-flow-banned-a-user/))
- **Reliability:** StatusGator logged **75+ outages** since Dec 2025; a sustained latency/outage run May 27–Jun 3 2026 hit all platforms at once. No cloud = no dictation. ([Voibe](https://www.getvoibe.com/resources/is-wispr-flow-reliable/))
- **Post-trial degradation:** Trustpilot reviewers report it "working 60% of the time" after paying. **Trustpilot 2.7/5.** ([spokenly](https://spokenly.app/blog/wispr-flow-review))
- **Bloat:** Windows app is **Electron** — ~800MB RAM, 8% CPU **idle**, and reported to **freeze VS Code/Notepad++** during dictation. ([Voibe](https://www.getvoibe.com/resources/wispr-flow-review/))

**The single sentence that matters:** Wispr is a cloud service wearing a native-app costume. Voicely is already on-device. That is the wedge.

---

## 2. Rivals

| App | Platforms | On-device vs Cloud | Pricing | Killer feature | Gap |
|---|---|---|---|---|---|
| **Superwhisper** | Mac, iOS, **Windows** (since 2024) | **On-device** (Whisper/Parakeet local) + optional cloud | Free tier; **$8.49/mo, $84.99/yr, $249.99 lifetime** | **Custom Modes** — define exactly how it thinks/writes/formats per task | Power-user UI; no real translation; no Android |
| **MacWhisper** | Mac-first, small iOS | **On-device** | Free tier; **€59 (~$69) lifetime** Gumroad; App Store $6.99/mo–$99.99 lifetime | File transcription, speaker tags, SRT/VTT/DOCX export | It's a **file transcriber**, not system-wide dictation; no Win/Android |
| **Aqua Voice** (YC W24) | Mac, Win, **iOS (Apr 2026)** | **Cloud** ("Avalon" model) | **$8/mo, $96/yr**; iOS $119/yr | **Coding-tuned** model + **streaming** display + NL editing ("rephrase that"). >50% users in Japan (devs) | Cloud-only; no on-device privacy story; no translation |
| **Willow Voice** | Mac, Win, iPhone, Android | **Cloud** | **$144/yr** (same as Wispr) | **Style memory** (learns tone per app) + Private Mode default-ON | Cloud; thin on translation/agentic features |
| **Apple Dictation** | Apple only | **On-device** | Free | Free, private, built-in | **Fails on technical vocab**, proper nouns, code; times out; no AI cleanup |
| **Otter.ai** | Web/mobile | Cloud | Free 300 min/mo | Meeting transcription, speaker ID, summaries | **Not system-wide** — can't type into VS Code/Slack/email; struggles with accents |
| **Notta** | Cross-platform | Cloud | Paid | 58-lang transcription, **translate into 42 langs**, ~98.86% accuracy claim | Transcription/meeting tool, not cursor-insertion dictation |

**Notable 2026 newcomers / context:** Aqua Voice is the fastest-rising threat — it owns the **developer/"vibe coding"** niche (marketed for Claude Code, Cursor, ChatGPT, Gemini) with sub-second streaming. JotMe owns **live meeting translation** (77–200+ languages) but isn't a system-wide dictation tool. ([TechCrunch roundup](https://techcrunch.com/2026/05/02/the-best-ai-powered-dictation-apps-of-2025/))

**Read of the field:** The market has split into (a) **cloud + AI features** (Wispr, Willow, Aqua) and (b) **on-device + privacy** (Superwhisper, MacWhisper, Apple). **Nobody credibly owns both at once, and nobody does real English↔Hebrew translation in a system-wide dictation flow.** That intersection is empty. That's Voicely's position.

---

## 3. What "market-best accuracy + translation" requires (verified model landscape)

- **English accuracy SoTA:** **Canary-Qwen-2.5B** is #1 on the HF Open ASR Leaderboard at **5.63% avg WER** (June 2025). **Parakeet TDT** (you already ship it via FluidAudio) is the **speed king** — RTFx >2,000, streaming RNN-T, far faster than Whisper. ([Northflank](https://northflank.com/blog/best-open-source-speech-to-text-stt-model-in-2026-benchmarks), [SiliconFlow](https://www.siliconflow.com/articles/en/fastest-open-source-speech-recognition-models))
- **Hebrew accuracy SoTA:** **ivrit.ai** is the unambiguous leader — `whisper-large-v3-turbo-ct2` and the new **v2-d4** model, trained on 3,300+ Hebrew speech hours, SoTA Hebrew WER, published at Interspeech 2025. **Critically: you currently rely on Whisper large-v3-turbo's generic Hebrew, which ivrit.ai materially beats.** Swap to ivrit.ai's fine-tune and your Hebrew immediately outclasses Wispr. ([ivrit-ai on HF](https://huggingface.co/ivrit-ai), [leaderboard](https://ivrit-ai-hebrew-transcription-leaderboard.hf.space/))
- **Translation engine:** **Meta SeamlessM4T v2 / SeamlessStreaming** — open-source, on-device-capable, **direct speech-to-text and speech-to-speech across 100+ languages incl. Hebrew**, with **EMMA low-latency streaming** (translates before the utterance finishes). This is the on-device translation backbone no competitor ships in a dictation app. ([EmergentMind](https://www.emergentmind.com/topics/seamlessm4t-models))

---

## 4. Prioritized differentiators to credibly beat Wispr Flow

**P0 — the wedge (privacy + accuracy + translation, on-device):**
1. **"Truly on-device, truly private" as the headline.** Lead with it. Wispr screenshots your screen to the cloud; Voicely never leaves the Mac. This is the single sharpest contrast and it's free to claim — you already have it.
2. **English↔Hebrew live translation (the category-defining feature).** No system-wide dictation rival does this. Ship **SeamlessStreaming** so a user speaks Hebrew and English text lands at the cursor (and vice versa). This is your "iPhone moment" — it's not a better dictation app, it's a *bilingual* dictation app.
3. **Best-in-class Hebrew via ivrit.ai.** Replace generic Whisper-Hebrew with ivrit.ai v2-d4. Instantly the **best Hebrew dictation on any platform** — a defensible #1 in a market (Israel + Hebrew diaspora) Wispr treats as just "1 of 100+ languages."

**P1 — feature parity + agentic edge:**
4. **Command/agentic editing** ("make this a list", "rephrase", "fix the second sentence") — match Wispr's Command Mode and Aqua's NL editing. You already have OpenRouter cleanup; extend it to in-place edits.
5. **Streaming text insertion** — show words as they're recognized (Aqua's "feels faster" trick), not a single end-of-utterance paste.
6. **Developer / "vibe coding" mode** — a code-aware vocabulary + a mode tuned for Claude Code/Cursor/ChatGPT prompts. This is where Aqua is winning and Wispr is weak. You ship a native CGEventTap (no Electron) so you **won't freeze VS Code** the way Wispr does — say that out loud.

**P2 — moat + monetization:**
7. **Native everywhere (anti-Electron).** Your Swift macOS app already crushes Wispr's 800MB Electron Windows build. For cross-platform, go native: SwiftUI for iOS, and for Win/Android consider a shared Rust/C++ core (whisper.cpp / ONNX) with native shells — *not* Electron. "Native, not Electron — won't freeze your editor, won't eat 800MB idle" is a real ad.
8. **Custom Modes** (Superwhisper's loved feature) + style memory (Willow's).
9. **Hybrid privacy switch** — on-device by default, optional cloud LLM for heavy cleanup, *clearly toggled* (the transparency Wispr lacks). Privacy Mode ON by default, like Willow.

**Pricing angle:** The whole market clusters at **$144/yr / $8–15/mo**. A **one-time lifetime license** (Superwhisper $249.99, MacWhisper €59 prove the appetite) or a lower sub undercuts Wispr while the on-device model means **near-zero marginal compute cost** for you — a structural margin advantage cloud rivals can't match.

---

## 5. Positioning Statement

> **Voicely is the private, bilingual dictation app for people who think in two languages.**
> It turns your voice into perfect text — and into perfect *translation* — system-wide, entirely on your own machine. No screenshots to the cloud, no outages, no 800MB battery hog. Just the fastest, most accurate English **and** Hebrew dictation on any platform, with AI editing that obeys your voice.
>
> *Wispr Flow sends your screen to the cloud. Voicely never leaves your Mac.*

**One-liner for the site:** *"Speak any language. Type it in another. Privately, on your device."*

---

### Sources
- [Wispr Flow pricing](https://wisprflow.ai/pricing) · [Voibe pricing](https://www.getvoibe.com/resources/wispr-flow-pricing/) · [spokenly review](https://spokenly.app/blog/wispr-flow-review)
- [Wispr privacy/ban](https://embertype.com/blog/the-day-wispr-flow-banned-a-user/) · [VocAI privacy](https://vocai.net/blog/wispr-flow-review-privacy-2026/) · [Voibe reliability log](https://www.getvoibe.com/resources/is-wispr-flow-reliable/) · [Voibe review/Electron](https://www.getvoibe.com/resources/wispr-flow-review/)
- [Superwhisper vs MacWhisper](https://spokenly.app/blog/wispr-flow-vs-superwhisper-vs-macwhisper) · [usevoicy comparison](https://usevoicy.com/blog/macwhisper-vs-voicy-vs-superwhisper)
- [Aqua Voice review](https://spokenly.app/blog/aqua-voice-review) · [Aqua pricing](https://www.getvoibe.com/resources/aqua-voice-pricing/)
- [Willow vs Wispr](https://www.getvoibe.com/resources/willow-voice-vs-wispr-flow/) · [Apple/Otter](https://www.getvoibe.com/resources/otter-ai-alternatives/) · [TechCrunch roundup](https://techcrunch.com/2026/05/02/the-best-ai-powered-dictation-apps-of-2025/)
- [Open ASR / Parakeet / Canary — Northflank](https://northflank.com/blog/best-open-source-speech-to-text-stt-model-in-2026-benchmarks) · [SiliconFlow fastest](https://www.siliconflow.com/articles/en/fastest-open-source-speech-recognition-models)
- [ivrit.ai HF](https://huggingface.co/ivrit-ai) · [Hebrew leaderboard](https://ivrit-ai-hebrew-transcription-leaderboard.hf.space/) · [SeamlessM4T](https://www.emergentmind.com/topics/seamlessm4t-models)