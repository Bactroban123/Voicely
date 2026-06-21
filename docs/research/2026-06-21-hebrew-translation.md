# Research: hebrew-translation

I have comprehensive, decision-grade data across all engines. Here is the final research report.

---

# Voicely English↔Hebrew Translation: Engine Research & Recommendation

## TL;DR recommendation

Build a **"Translate mode"** that is **decoupled from transcription**: Voicely already transcribes in the spoken language (Whisper/Parakeet). Add a **target-language picker**, then route the transcript through a **2-tier MT stack**:

- **macOS/iOS primary: Apple Translation framework** — free, fully on-device/offline, Hebrew↔English officially supported, RTL handled. One caveat (below): it requires a SwiftUI host view, which is solvable in a menu-bar app.
- **Cross-platform + cloud fallback + "best quality" toggle: LLM translation via your existing OpenRouter pipeline** (you already call OpenRouter for cleanup — translation is the same call with a different system prompt). Use **Gemini 2.x/3 Flash or GPT-class** for Hebrew. This is the single highest-quality option for Hebrew and reuses infrastructure you already ship.
- **Windows/Android/fully-offline open-source path: NLLB-200 distilled-600M via CTranslate2** (int8), with **Opus-MT en-he/he-en** as a lighter fallback.

Do **not** try to use Whisper's `translate` task — it only goes X→English (confirmed below), so it cannot do English→Hebrew at all and gives you no target-language control.

---

## 1. Whisper `translate` task — confirmed one-way limitation

Whisper's `--task translate` only ever produces **English** output (any non-English source → English). It cannot translate English→Hebrew, and offers no arbitrary target language. The `large-v3-turbo` model you run is additionally **not trained for the translate task at all** — turbo is ASR-only. So Whisper stays your **transcription** engine; translation must be a separate stage.
Sources: [openai/whisper README](https://github.com/openai/whisper), [whisper-large-v3 model card](https://huggingface.co/openai/whisper-large-v3), [discussion #649](https://github.com/openai/whisper/discussions/649).

The architecture is therefore always: **transcribe (spoken lang) → translate (to chosen target)**. Apple's new `SpeechAnalyzer`/`SpeechTranscriber` (macOS/iOS 26) is also transcription-only — there is **no native on-device speech-*translation* module**; the locale just sets the transcription language, not a translation target. So no shortcut there either.
Sources: [WWDC25 session 277](https://developer.apple.com/videos/play/wwdc2025/277/), [SpeechAnalyzer guide](https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide).

---

## 2. Engine-by-engine comparison

| Engine | On-device | Hebrew↔EN | Quality (Hebrew) | Latency | Size / cost | License | Platforms |
|---|---|---|---|---|---|---|---|
| **Apple Translation framework** | ✅ offline | ✅ both ways, official | Good (system MT, weaker than top LLMs on idiom) | ~instant, local | Free; downloadable lang pack | Apple system API | macOS 15+/iOS 18+ only |
| **OpenRouter LLM** (Gemini Flash / GPT) | ❌ cloud | ✅ both ways | **Best** for Hebrew (context, niqqud-aware, RTL) | ~0.3–1.5 s | ~pennies/1k chars | commercial API | all platforms |
| **NLLB-200 distilled-600M (CTranslate2 int8)** | ✅ offline | ✅ both ways | Good, solid on Hebrew (well-resourced pair) | ~50–300 ms/sentence on M3 | ~600 MB fp32 → ~300 MB int8; ~3 GB RAM fp32 | CC-BY-NC-4.0 ⚠️ **non-commercial** | all (C/C++/Python; Swift via bridge) |
| **Opus-MT en-he / he-en (Marian/CTranslate2)** | ✅ offline | ✅ (two separate models) | Moderate; he-en has known nonsense cases | very fast, small | ~75–300 MB each | **MIT / CC-BY-4.0** (commercial-OK) | all |
| **MADLAD-400** | ✅ offline | ✅ | ≈NLLB on Hebrew, bigger | slower | 3B+ params, heavy | Apache-2.0 (commercial-OK) | all (overkill for HE) |
| **DeepL API** | ❌ cloud | ✅ (added Jun 2025) | High, but **Pro-only** for Hebrew | ~0.3 s | $5.49/mo + $25/M chars (free tier 500k/mo) | commercial | all |
| **Google Cloud Translation** | ❌ cloud | ✅ | Good | ~0.3 s | $20/M chars (500k/mo free) | commercial | all |

Sources: [Apple Translate languages incl. Hebrew + RTL](https://en.wikipedia.org/wiki/Translate_(Apple)), [iOS 26 on-device translation guide](https://www.iphonedevelopers.co.uk/2025/07/ios-on-device-translation-swift-multilingual-ui.html), [NLLB-200-distilled-600M CTranslate2](https://huggingface.co/entai2965/nllb-200-distilled-600M-ctranslate2), [Opus-MT en-he](https://huggingface.co/Helsinki-NLP/opus-mt-en-he) + [he-en quality issue #88](https://github.com/Helsinki-NLP/Opus-MT/issues/88), [MADLAD-400 vs NLLB](https://insiderllm.com/guides/best-local-llms-translation/), [DeepL Hebrew launch (Pro-only)](https://www.deepl.com/en/blog/vietnamese-thai-hebrew-launch), [DeepL pricing](https://langbly.com/blog/deepl-api-pricing-guide), [Google Translation pricing](https://cloud.google.com/translate/pricing).

---

## 3. The Apple framework gotcha (and the fix) — most important integration note

`TranslationSession` **cannot be instantiated directly**. The only way to get a session is from a **SwiftUI view** via the `.translationTask` modifier; the session is tied to that view's lifetime and dies if the view disappears. The framework also presents a download sheet for missing language packs and **does not run in the Simulator**.
Sources: [Swift Translation API deep-dive](https://www.polpiella.dev/swift-translation-api/), [translationTask docs](https://developer.apple.com/documentation/swiftui/view/translationtask(source:target:action:)), [TranslationSession docs](https://developer.apple.com/documentation/translation/translationsession).

**For a menu-bar app this is solvable but not free:** host a **persistent, zero-size hidden SwiftUI view** (via `NSHostingView`/`NSHostingController`) that lives for the app's lifetime and carries the `.translationTask` modifier; drive it with a `TranslationSession.Configuration` and bridge results back with an `async` continuation. Keep the host alive (don't tie it to a popover that closes) so the session persists. Use `LanguageAvailability.status()` to check `.installed` vs `.supported` and `prepareTranslation()` to pre-download the Hebrew pack on first run so users don't hit the sheet mid-dictation.
Source: [NSHostingView](https://developer.apple.com/documentation/swiftui/nshostingview).

This is the cleanest **on-device, free, offline, App-Store-safe** option for your Mac/iOS builds — worth the wrapper work.

---

## 4. Hebrew-specific quality notes

- **Hebrew is mid-resource**, so engine choice matters more than for, say, French. **LLMs (Gemini/GPT via OpenRouter) clearly lead** on Hebrew idiom, register, and mixed EN/HE code-switching — common in Israeli speech. They also handle **niqqud** sensibly (omit it in output unless asked) and won't garble **RTL**.
- **Opus-MT he-en** has documented cases of producing nonsensical output ([issue #88](https://github.com/Helsinki-NLP/Opus-MT/issues/88)) — acceptable as a tiny offline fallback but not as the primary Hebrew engine.
- **NLLB-200** is more robust than Opus-MT on Hebrew but its license is **CC-BY-NC (non-commercial)** — a real blocker since you intend to **sell Voicely**. Use NLLB only for a free tier, or pick **Opus-MT (MIT/CC-BY) or MADLAD-400 (Apache-2.0)** for the commercial offline path.
- **RTL handling**: insert the translated Hebrew with proper directionality. When pasting into the cursor, Hebrew output is RTL — your text-insertion layer should not force LTR. Apple's framework and the OS handle bidi correctly; for raw model output you may want to wrap with Unicode RLM/`\u200F` only if a target app misrenders.

---

## 5. Concrete recommendation for Voicely

1. **macOS + iOS (your shipping platforms):** Apple Translation framework as default (free, offline, Hebrew official, RTL-safe), wrapped via a persistent hidden `NSHostingView`. Pre-download the HE pack on first launch.
2. **"Best quality" toggle + cloud fallback + Windows/Android:** OpenRouter LLM translation — reuse your existing cleanup pipeline; for Hebrew prefer **Gemini Flash (3.x)** or a GPT-class model. One API, all platforms, top Hebrew quality, pay-as-you-go fits your token economy. ([OpenRouter models](https://openrouter.ai/models))
3. **Fully-offline cross-platform (Windows/Android), commercial-safe:** **Opus-MT en-he/he-en** (MIT/CC-BY) or **MADLAD-400** (Apache-2.0) compiled with **CTranslate2 int8**. Avoid NLLB in paid builds due to its **non-commercial** license.
4. **Optional premium cloud:** DeepL (Hebrew is **Pro-only**) or Google Cloud Translation if you want a non-LLM deterministic option — but the OpenRouter LLM path already covers this better for Hebrew.

**Specific repos/models to pull:**
- `Helsinki-NLP/opus-mt-en-he`, `Helsinki-NLP/opus-mt-tc-big-he-en` (HuggingFace)
- `entai2965/nllb-200-distilled-600M-ctranslate2` (HuggingFace; NC license — free tier only)
- `OpenNMT/CTranslate2` (GitHub) for the offline runtime
- Apple: `Translation` + `LanguageAvailability` + `.translationTask` (system framework)

**Key risk to flag:** the Apple-framework SwiftUI-host requirement is the only non-trivial engineering bit; everything else is config + an OpenRouter prompt. Validate the hidden-host approach early on macOS 26 (it won't run in Simulator, must test on the M3).

Sources: [Whisper repo](https://github.com/openai/whisper) · [Apple Translation/TranslationSession](https://developer.apple.com/documentation/translation/translationsession) · [Swift Translation API constraints](https://www.polpiella.dev/swift-translation-api/) · [WWDC25 SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/) · [DeepL Hebrew (Pro-only)](https://www.deepl.com/en/blog/vietnamese-thai-hebrew-launch) · [NLLB CTranslate2](https://huggingface.co/entai2965/nllb-200-distilled-600M-ctranslate2) · [Opus-MT en-he](https://huggingface.co/Helsinki-NLP/opus-mt-en-he) · [MADLAD vs NLLB](https://insiderllm.com/guides/best-local-llms-translation/) · [Google Translation pricing](https://cloud.google.com/translate/pricing)