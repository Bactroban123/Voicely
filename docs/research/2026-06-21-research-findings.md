# Voicely — Research Findings

> Consolidated output of a 5-agent research sweep, June 21 2026.
> Target machine: **Apple M3 Pro, 18 GB RAM, macOS 26.5 (Tahoe)**.
> All claims verified against official docs / live GitHub / model cards (sources per section).
> This document is the evidence base for [`docs/specs/2026-06-21-voicely-design.md`](../specs/2026-06-21-voicely-design.md).

---

## 0. Headline decisions

| Decision | Choice | Why |
|---|---|---|
| **STT engine (default)** | **FluidAudio + Parakeet TDT v2 (English)** | Best accuracy (~6% WER) *and* fastest measured (~80 ms mic-to-text); Swift-native; Apache-2.0 |
| **STT engine (alternates)** | Apple SpeechAnalyzer (zero-download, 26+), Parakeet v3 (multilingual), WhisperKit large-v3-turbo (max languages + STT-level custom vocab) | Exposed in a manual model picker |
| **App stack** | Native Swift, **AppKit `NSStatusItem`** shell + SwiftUI content | Dynamic state icon needs AppKit control; `MenuBarExtra` too thin |
| **Hotkey** | **CGEventTap** + a pure tap/hold state machine | Only path that gives key-up + press-duration for tap-vs-hold |
| **Text insertion** | **Clipboard paste-and-restore** (default) → AX insert → copy-only fallback | Universal compatibility; never lose the transcript |
| **HUD** | Non-activating `NSPanel`, `canBecomeKey = false` | Must not steal focus or insertion breaks |
| **AI cleanup** | **OpenRouter `google/gemini-2.5-flash-lite`**, temp 0.1, thinking off, streaming, `sort:latency`, `zdr:true` | ~0.29 s TTFT, <$1/mo at heavy use |
| **Build from** | **Pindrop** (MIT) + **Hex** (MIT) | Both ~1:1 with our spec, permissive license = copy code |
| **Packaging** | Non-sandboxed, ad-hoc/stable-identity signing, no notarization, `SMAppService` launch-at-login | Sandbox blocks the Accessibility API our core feature needs |

---

## 1. On-device speech-to-text engine

### Comparison

| Engine | Best model | English WER | Speed (Apple Silicon) | Disk/RAM | Streaming | Swift/SPM | License | macOS 26 notes |
|---|---|---|---|---|---|---|---|---|
| **FluidAudio (Parakeet TDT CoreML)** | `parakeet-tdt-0.6b-v2` (EN) / `v3` (multi) | **6.05% / 6.32%** | **fastest** (~0.19 s sample on M4; ~80 ms dictation; 110–190× RTF) | ~0.6 B; ≥2 GB RAM | Yes (Silero VAD + EOU) | Easy (SPM) | **Apache 2.0** | macOS 14+; v2 English-only |
| **Apple SpeechAnalyzer / SpeechTranscriber** | OS-managed | ~14% (Argmax #); "no noticeable diff" real-world | fastest end-to-end (34 min in ~45 s) | 0 bundled (OS asset) | Yes | Trivial (native) | Apple (free) | **macOS 26+ only; no custom vocab; ~10 langs** |
| **WhisperKit** (`argmax-oss-swift`) | `large-v3-v20240930` turbo | ~7.4% | realtime by wide margin (slower than Parakeet) | turbo ~550 MB | Yes | Easy (SPM) | **MIT** | 100 langs + lang-detect + **custom vocab**; `prewarmModels()` |
| **whisper.cpp** | large-v3-turbo (Metal) | ~7.4% | ~4–6× RT turbo on M3 | turbo ~1.5 GB | Yes | Medium (C/C++) | MIT | More glue, no win over Parakeet |
| **MLX Whisper** | large-v3-turbo | ~7.4% | GPU not ANE | ~1.5 GB | Weak | Hard (Python-first) | MIT | **Disqualified** for a shipping Swift app |

### Decisions
- **Default: FluidAudio Parakeet TDT v2 (English-only)** — wins on accuracy *and* latency simultaneously, runs macOS 14+, battle-tested in VoiceInk + Spokenly.
- **Manual picker (4 options):**
  1. **Parakeet (English) — default** · ~6% WER, ~80 ms, ANE.
  2. **Apple Dictation (native)** · no download, macOS 26+, ~14% WER.
  3. **Parakeet (Multilingual)** · v3, 25 langs + Japanese.
  4. **Whisper Large-v3-Turbo** · ~550 MB, 100 langs, **only option with STT-level custom-vocabulary support**.
- **Custom vocabulary** is primarily applied in the **Refine (LLM) layer** (see §5), so it works with *any* STT engine — Whisper's STT-level vocab is a bonus, not a requirement.

### Audio pipeline
- **Format:** 16 kHz, mono, PCM **Float32** (universal for Whisper + Parakeet). Apple SpeechAnalyzer: query `bestAvailableAudioFormat` instead.
- **Capture:** `AVAudioEngine` mic tap renders at hardware rate (44.1/48 kHz); a tap can't force format. Use **`AVAudioConverter`** to downsample + downmix to 16 kHz mono Float32. FluidAudio ships an `AudioConversion` guide doing exactly this.
- **VAD / silence trim:** use FluidAudio's bundled **Silero VAD + EOU** model (produces "text appears the instant you stop" behavior).
- **Warm-loading (kill cold start):** init the model once at launch and keep it resident. FluidAudio: hold one `AsrManager`. WhisperKit: call `prewarmModels()`. Apple: keep `SpeechAnalyzer`/`SpeechTranscriber` alive + reserve asset via `AssetInventory`.
- **Batch vs stream:** Parakeet batch is fast enough (~0.5 s for a minute) to "transcribe on release" and still hit the <1.5 s budget; streaming is a Tier-1 enhancement.

### Caveats
- Apple SpeechAnalyzer API signatures (`SpeechAnalyzer(modules:)`, `SpeechTranscriber(locale:)`, `bestAvailableAudioFormat`, `AssetInventory`) are corroborated from WWDC25 session 277 + secondary writeups — **verify exact signatures in Xcode** (Apple doc pages are JS-rendered).
- WER numbers are from different test sets; treat as directional. Apple's practical quality may beat its 14% headline.
- WhisperKit repo renamed to **`argmaxinc/argmax-oss-swift`** (v1.0.0, May 2026).

**Sources:** [argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift) · [whisperkit-coreml HF](https://huggingface.co/argmaxinc/whisperkit-coreml) · [WhisperKit arXiv](https://arxiv.org/html/2507.10860v1) · [Apple+Argmax blog](https://www.argmaxinc.com/blog/apple-and-argmax) · [WWDC25 277](https://developer.apple.com/videos/play/wwdc2025/277/) · [SpeechAnalyzer docs](https://developer.apple.com/documentation/speech/speechanalyzer) · [MacStories hands-on](https://www.macstories.net/stories/hands-on-how-apples-new-speech-apis-outpace-whisper-for-lightning-fast-transcription/) · [FluidAudio](https://github.com/FluidInference/FluidAudio) · [FluidAudio AudioConversion guide](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Guides/AudioConversion.md) · [parakeet-tdt-0.6b-v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) · [whisper.cpp](https://github.com/ggml-org/whisper.cpp) · [mlx vs whisper.cpp bench](https://notes.billmill.org/dev_blog/2026/01/updated_my_mlx_whisper_vs._whisper.cpp_benchmark.html)

---

## 2. Global hotkey (tap-to-toggle + push-to-hold from one key)

### Approach comparison

| Approach | keyDown | **keyUp** | flagsChanged | Swallow | fn/Globe | Permission |
|---|---|---|---|---|---|---|
| **CGEventTap** | ✓ | **✓** | ✓ | ✓ (`nil`) | ✓ (`maskSecondaryFn`) | Input Monitoring (+ Accessibility) |
| NSEvent global monitor | ✓ | ✓ | ✓ | ✗ observe-only | limited | Input Monitoring |
| Carbon `RegisterEventHotKey` | ✓ (press) | **✗** | ✗ | n/a | ✗ | none |
| `KeyboardShortcuts` (SPM) | ✓ | ✓* | ✗ | n/a | ✗ | none |

\* KeyboardShortcuts surfaces `onKeyUp` but is built on Carbon under the hood — reliable for modifier *combos*, flaky for bare-key / modifier-only hold timing, and can't measure precise hold duration. **Use it for the recorder UI only, not the hold logic.**

### Recommended design — single CGEventTap state machine
- Tap on `.keyDown`, `.keyUp`, `.flagsChanged`; `CGEvent.tapCreate(tap:.cgSessionEventTap, place:.headInsertEventTap, options:.defaultTap, ...)` → `CFMachPortCreateRunLoopSource` → run loop → `CGEvent.tapEnable`.
- **Logic:** on keyDown record `t0` and start recording immediately (zero perceived lag for hold). On keyUp compute `dt`:
  - `dt < ~250 ms` → **TAP** → toggle (leave on if it was off; stop if already recording).
  - `dt ≥ ~250 ms` → **HOLD** → stop now (release).
- Ignore autorepeat keyDowns; return `nil` to swallow printable hotkeys (avoids stray char/beep).
- **fn/Globe** = `maskSecondaryFn` flag, not a keyDown — capture via `.flagsChanged`; warn it collides with system Dictation/emoji.
- **Modifier-only (e.g. double-tap Right-⌥):** no keyDown — diff flags for down/up; side via keyCode (L-⌥ 58 / R-⌥ 61); double-tap = custom timing.

### Secure Input pitfall
When any app calls `EnableSecureEventInput` (password fields, 1Password, secure terminals), **the system stops delivering events to all taps** — your hotkey silently won't fire. No workaround by design; detect and show a "paused (secure field)" state.

**This is the part to lift wholesale from Hex** (`HotKeyProcessor.swift`, MIT, unit-tested).

**Sources:** [CGEventTap vs NSEvent](https://levelup.gitconnected.com/swiftui-macos-detect-listen-to-global-key-events-two-ways-df19e565793d) · [EventTapper](https://github.com/usagimaru/EventTapper) · [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) · [alt-tab KeyboardEvents.swift](https://github.com/lwouis/alt-tab-macos/blob/master/src/logic/events/KeyboardEvents.swift) · [CGEventFlags](https://developer.apple.com/documentation/coregraphics/cgeventflags) · [openless](https://github.com/Open-Less/openless) · [TN2150 Secure Input](https://developer.apple.com/library/archive/technotes/tn2150/_index.html) · [KM Secure Input wiki](https://wiki.keyboardmaestro.com/assistance/Secure_Input_Problem)

---

## 3. System-wide text insertion at the cursor

### Method comparison
1. **Accessibility (`AXUIElement`)** — set `kAXSelectedTextAttribute` on focused element. *Excellent on native Cocoa*; **unreliable on Electron/Chromium** (Slack, VS Code — Electron bug #36337 mis-handles ranges) and many web fields. Best as a *first attempt*, not the only path.
2. **Clipboard paste-and-restore** — save pasteboard + `changeCount`, write text, synth ⌘V via CGEvent, restore after a delay. **Works essentially everywhere** (every text surface implements Paste). Downsides: momentary clipboard clobber, clipboard managers may capture it, some locked-down apps (Citrix/RDP, banking, password managers, EMR) block paste. **The most reliable default.**
3. **CGEvent Unicode typing** (`keyboardSetUnicodeString`) — no clipboard touch (privacy-nice) but **~20 char/event cap** → chunk + ~4 ms delays; can drop chars in fast Electron fields. Good **secondary/streaming** path.

### Recommended fallback chain (what real apps ship)
```
1. AX insertion (focused element)          ← native apps, clean
2. clipboard paste-and-restore (⌘V)        ← universal default
3. copy-only: leave on clipboard + toast   ← never lose the transcript
```
Pragmatic simplification many ship: **paste-first** (skip AX) → copy-only, because AX's Electron breakage isn't worth the complexity. Decide per QA of the apps you care about. For **streaming** insertion use Unicode typing or repeated small pastes.

> ⚠️ Insertion targets the *focused* element — so the HUD **must not** take focus (see §4).

**Sources:** [Electron #36337](https://github.com/electron/electron/issues/36337) · [AX selected text](https://macdevelopers.wordpress.com/2014/02/05/how-to-get-selected-text-and-its-coordinates-from-any-system-wide-application-using-accessibility-api/) · [Wispr "text not pasting"](https://docs.wisprflow.ai/articles/7971211038-fix-text-not-pasting-after-dictation) · [keyboardSetUnicodeString](https://developer.apple.com/documentation/coregraphics/cgevent/1456028-keyboardsetunicodestring)

---

## 4. App shell, HUD, settings, persistence

### Menu-bar shell — **`NSStatusItem` (AppKit) + SwiftUI content**
`MenuBarExtra` gives no access to the underlying status item / window, blocks the run loop while a `.menu` is open, and can't cleanly drive a dynamic state icon — all of which bite a stateful dictation app. `NSStatusItem.button.image` swaps the idle/listening/processing icon in one line; build menu/popover content in SwiftUI via `NSHostingView`. (If staying declarative, `MenuBarExtraAccess` shim is required — a tell the first-party API is too thin.)

### No dock icon
`LSUIElement = YES` in Info.plist (prevents launch flash) **and** `NSApp.setActivationPolicy(.accessory)` at runtime.

### Floating HUD — the hard part
Subclass `NSPanel`:
```
styleMask: [.nonactivatingPanel, .borderless]
override var canBecomeKey: Bool { false }   // pure indicator → never grabs caret
override var canBecomeMain: Bool { false }
level: .floating            // or .statusBar
collectionBehavior: [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
isFloatingPanel: true; backgroundColor: .clear
```
- `.nonactivatingPanel` is **the** flag that stops focus theft. **Never call `NSApp.activate`** near the HUD.
- Host SwiftUI via `NSHostingView`; present with `orderFront(nil)` / `orderFrontRegardless()` — **not** `makeKeyAndOrderFront`.
- Set `ignoresMouseEvents = true` if purely informational; `false` if it has a stop button.
- **Position:** near cursor (`NSEvent.mouseLocation`, mind the coord flip), bottom-center (`visibleFrame`), or anchored to the status button.
- **Lift Hex's `InvisibleWindow.swift`** (full-screen transparent non-activating panel) for this.

### Live waveform (cheap)
`AVAudioEngine.installTap` (**off main thread**; refresh input format after device change) → RMS per buffer (`20*log10(sqrt(mean(x²)))`) → publish on **MainActor** → draw with SwiftUI **`Canvas` + `TimelineView(.animation)`** (far cheaper than many animated Shapes).

### Settings — ⚠️ Tahoe gotcha
SwiftUI `Settings { }` scene is the goal, but **`openSettings` is broken on macOS 26 Tahoe** and `SettingsLink` is unreliable in menu-bar apps. Use the activation dance (`.regular` → show → `.accessory` on close) + the **SettingsAccess** package (`openSettingsLegacy()`) or a hidden `Window` scene as fallback. Budget time for this.

### Persistence
- **`UserDefaults` / `@AppStorage`** — toggles, hotkey, HUD position, selected model, launch-at-login flag.
- **JSON file in `~/Library/Application Support/Voicely/`** — custom vocabulary (`Codable`, human-readable, exportable).
- **Keychain** — the OpenRouter API key. Never in UserDefaults.

**Sources:** [Cindori menu bar](https://cindori.com/developer/hands-on-menu-bar) · [Multi.app NSStatusItem](https://multi.app/blog/pushing-the-limits-nsstatusitem) · [MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess) · [Fazm floating panel](https://fazm.ai/blog/swiftui-floating-panel) · [Cindori floating panel](https://cindori.com/developer/floating-panel) · [philz.blog nonactivating](https://philz.blog/nspanel-nonactivating-style-mask-flag/) · [Create with Swift waveform](https://www.createwithswift.com/creating-a-live-audio-waveform-in-swiftui/) · [Steinberger settings-from-menu-bar](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items) · [SettingsAccess](https://github.com/orchetect/SettingsAccess)

---

## 5. AI cleanup via OpenRouter

### Model choice
Cleanup is a **constrained rewrite** (~20–150 tok in/out). What matters: **TTFT** (dominates wall-clock at this length) and **instruction adherence**. A small fast model with **thinking disabled** wins.

| Role | Model slug | $ in / out (per 1M) | Note |
|---|---|---|---|
| **Default** | `google/gemini-2.5-flash-lite` | $0.10 / $0.40 | ~0.29 s TTFT, thinking off by default |
| Cheapest | `openai/gpt-5-nano` | $0.05 / $0.40 | lowest input price |
| Fastest | `…:nitro` open model (Groq/Cerebras) | varies | 500–2000 tok/s |
| Most accurate | `anthropic/claude-haiku-4.5` | $1 / $5 | strictest instruction discipline |

### Integration
`POST https://openrouter.ai/api/v1/chat/completions`, header `Authorization: Bearer …` (+ optional `HTTP-Referer`/`X-Title`). Request body:
```jsonc
{
  "model": "google/gemini-2.5-flash-lite",
  "messages": [...],
  "temperature": 0.1,
  "max_tokens": 400,
  "stream": true,
  "reasoning": { "enabled": false },
  "provider": { "sort": "latency", "data_collection": "deny", "zdr": true }
}
```
- `provider.sort:"latency"` prioritizes lowest TTFT. `:nitro`=throughput, `:floor`=price. Pin via `provider.order:["groq"]` + `allow_fallbacks:false`.
- **Privacy:** OpenRouter doesn't log content by default; `data_collection:"deny"` + `zdr:true` restrict to zero-retention providers — ship both **on by default** for dictation. (Trade-off: smaller pool, keep a fallback.)
- **Stream** so you can paste the head while the tail arrives → sub-second *feels* instant.

### System prompt (editor, not assistant)
Full text stored in spec §Refine. Key rules: fix punctuation/casing, strip fillers/false starts, light formatting, **apply custom-vocab correction map**, **never add/invent/answer/summarize**, return only cleaned text. Inject `{{CUSTOM_VOCABULARY}}` as a list (with known misheard variants when available — biggest accuracy lever). Temp 0.1, thinking off, raw transcript as the user message.

### Cost
~200 dictations/day (~6 k/mo): **≈ $0.38/mo** on the default, ≈ $0.28 on gpt-5-nano, ≈ $4.20 on Haiku. **Cost is a non-issue — optimize purely for latency + edit quality.**

**Sources:** [OpenRouter quickstart](https://openrouter.ai/docs/quickstart) · [provider routing](https://openrouter.ai/docs/guides/routing/provider-selection) · [latency best-practices](https://openrouter.ai/docs/guides/best-practices/latency-and-performance) · [ZDR](https://openrouter.ai/docs/guides/features/zdr) · [gemini-2.5-flash-lite](https://openrouter.ai/google/gemini-2.5-flash-lite) · [gpt-5-nano](https://openrouter.ai/openai/gpt-5-nano) · [claude-haiku-4.5](https://openrouter.ai/anthropic/claude-haiku-4.5)

---

## 6. Open-source apps to build from

| Rank | Repo | Stars | License | Role for Voicely |
|---|---|---|---|---|
| **1** | [watzon/pindrop](https://github.com/watzon/pindrop) | ~540 | **MIT** | The blueprint — ~1:1 with our spec (menu-bar, WhisperKit+Parakeet+Apple Speech behind one protocol, clipboard/AX insertion, AI cleanup, dictionary, HUD, onboarding). **Copy code freely.** |
| **2** | [kitlangton/Hex](https://github.com/kitlangton/Hex) | ~2.3 k | **MIT** | Cleanest, most *testable* core: pure `HotKeyProcessor` state machine (push-to-talk + double-tap-lock, unit-tested) + `InvisibleWindow` HUD + CGEvent key monitor. **Copy code freely.** |
| 3 | [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk) | ~5.3 k | **GPLv3** | Most feature-complete (notch recorder, warmup coordinator, multi-provider AI, power modes). **Read for patterns; don't copy code** unless Voicely stays GPL. |
| 4 | [argmax-oss-swift / WhisperKit](https://github.com/argmaxinc/WhisperKit) + [FluidAudio](https://github.com/FluidInference/FluidAudio) | ~6.2 k / — | MIT / Apache-2.0 | The engine deps. `WhisperAX` example shows mic streaming + model-download UI. |

### Component → reference map
| Component | Borrow from | Pattern |
|---|---|---|
| **Capture** | Hex `HotKeyProcessor.swift` + `KeyEventMonitorClient.swift` | Pure tested state machine fed by a CGEvent tap; Sauce for layout-correct keycodes |
| **Transcribe** | Pindrop `TranscriptionEngine` protocol + WhisperKit `WhisperAX` | Protocol over WhisperKit↔Parakeet↔AppleSpeech; `cpuAndNeuralEngine`; warm-load on idle |
| **Refine** | Pindrop `AIEnhancementService` + `BuiltInPresets` | OpenAI-compatible HTTP; **structured edit-list** prompt to avoid truncation; keys in Keychain |
| **Insert** | Pindrop `OutputManager` / Hex `PasteboardClient` | Snapshot clipboard → set → ⌘V → restore after delay + session-ownership guard; AppleScript menu-click fallback |
| **HUD** | Hex `InvisibleWindow.swift` | Full-screen transparent non-activating panel |
| **Perf** | VoiceInk `WhisperModelWarmupCoordinator` (concept only — GPL) | Transcribe a tiny bundled WAV on idle to pre-warm |

### License bottom line
MIT (Pindrop, Hex, WhisperKit) + Apache-2.0 (FluidAudio) = copy/modify freely with attribution, no copyleft → **these are the "copy code" sources**. GPLv3 (VoiceInk) / AGPL (vocamac) = study only (copyleft would force Voicely open if distributed; fine while it stays a private personal app). **Build on Pindrop + Hex.**

---

## 7. Permissions checklist

| Permission | TCC service | For | Check / request | Info.plist |
|---|---|---|---|---|
| **Microphone** | `kTCCServiceMicrophone` | capture audio | `AVCaptureDevice.authorizationStatus(for:.audio)` / `AVAudioApplication.requestRecordPermission` | **`NSMicrophoneUsageDescription`** (crash without it) |
| **Accessibility** | `kTCCServiceAccessibility` | ⌘V synthesis + AX insertion | `AXIsProcessTrusted()` / `AXIsProcessTrustedWithOptions([prompt:true])` | — (needs **quit+relaunch**) |
| **Input Monitoring** | `kTCCServiceListenEvent` | the CGEventTap listener | `CGPreflightListenEventAccess()` / `CGRequestListenEventAccess()` | — (needs **quit+relaunch**) |

- On Tahoe the Accessibility/Input-Monitoring prompts are **non-modal** — deep-link to System Settings yourself (`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` / `…?Privacy_ListenEvent` / `…?Privacy_Microphone`).
- Both need **quit-and-relaunch** to take effect → bake into onboarding.
- **TCC grants are keyed to the code signature** → use a **stable signing identity** or rebuilds drop permissions. Known Tahoe stale-cache bug after OS updates → re-check on lifecycle events.

---

## 8. Packaging (personal use)
- **Signing:** ad-hoc / free personal team, **stable identity** (avoids dropping TCC grants on rebuild). **No notarization** needed to run locally.
- **Sandbox: OFF** — App Sandbox blocks the Accessibility API our insertion depends on. (Sandbox only mandatory for Mac App Store, which we don't target.)
- **Hardened Runtime: on** (hygiene); entitlement `com.apple.security.device.audio-input = YES`.
- **Launch at login:** `SMAppService.mainApp.register()` (macOS 13+), wired to a Settings toggle; handle `.requiresApproval`.
- **Install:** drag `Voicely.app` to `/Applications`; first launch right-click→Open if Gatekeeper complains.

**Sources:** [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) · [audio-input entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input) · [Accessibility-in-sandbox forum](https://developer.apple.com/forums/thread/810677) · [rsms signing gist](https://gist.github.com/rsms/929c9c2fec231f0cf843a1a746a416f5)
