# Voicely Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan phase-by-phase. Each phase below is a milestone that ships working, testable software; at execution time, expand each phase's tasks into bite-sized TDD steps (write failing test → watch it fail → minimal code → pass → commit). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A personal native-macOS menu-bar dictation app — press a configurable hotkey, speak, and on-device-transcribed + AI-cleaned text lands at the cursor in any app.

**Architecture:** Four protocol-bounded components (Capture → Transcribe → Refine → Insert) wired by an `AppCoordinator` state machine, plus an AppKit `NSStatusItem` shell and a focus-safe floating `NSPanel` HUD. On-device STT (FluidAudio/Parakeet default); cleanup via OpenRouter. Build by lifting MIT code from **Pindrop** + **Hex**.

**Tech Stack:** Swift 6 / SwiftUI + AppKit, Xcode 26, macOS 26 target (deploy 14+ where engines allow). SPM deps: `argmaxinc/argmax-oss-swift` (WhisperKit), `FluidInference/FluidAudio` (Parakeet), `sindresorhus/KeyboardShortcuts` (recorder UI), `orchetect/SettingsAccess` (Tahoe settings fix), `Clipy/Sauce` (keycodes). No sandbox.

**Spec:** [`docs/specs/2026-06-21-voicely-design.md`](../specs/2026-06-21-voicely-design.md) · **Research:** [`docs/research/2026-06-21-research-findings.md`](../research/2026-06-21-research-findings.md)

---

## File structure (target)

```
Voicely.xcodeproj
Voicely/
  VoicelyApp.swift              @main · scenes (Settings) · NSApplicationDelegate
  AppCoordinator.swift          owns AppState + wires the 4 components
  Models/
    AppState.swift              .idle/.recording/.locked/.processing + transitions
    VocabularyEntry.swift       Codable { term; variants:[String] }
    SettingsStore.swift         @AppStorage-backed prefs (models, toggles, hotkey)
  Capture/
    HotKeyProcessor.swift       PURE tap/hold/double-tap state machine (port Hex)
    KeyEventMonitor.swift       CGEventTap → KeyEvent stream
    AudioRecorder.swift         AVAudioEngine + AVAudioConverter → [Float] @16k mono
    AudioLevelMeter.swift       RMS per buffer → @Published levels (MainActor)
  Transcribe/
    TranscriptionEngine.swift   protocol { prewarm(); transcribe(_:) async throws -> String }
    ParakeetEngine.swift        FluidAudio AsrManager (DEFAULT)
    WhisperKitEngine.swift      WhisperKit large-v3-turbo
    AppleSpeechEngine.swift     SpeechAnalyzer/SpeechTranscriber (macOS 26+)
    ModelManager.swift          available models, download-on-demand, selection
  Refine/
    CleanupService.swift        OpenRouter streaming chat client
    CleanupPrompt.swift         system prompt + {{CUSTOM_VOCABULARY}} injection
    KeychainStore.swift         OpenRouter API key
  Insert/
    TextInserter.swift          fallback chain orchestrator
    ClipboardPaster.swift       snapshot → set → ⌘V → restore (+ownership guard)
    AXInserter.swift            optional kAXSelectedTextAttribute first-attempt
  Permissions/
    PermissionManager.swift     mic / accessibility / input-monitoring status+prompt
  UI/
    StatusBarController.swift   NSStatusItem + state-driven template icon + menu
    HUDPanel.swift              non-activating NSPanel (port Hex InvisibleWindow)
    HUDView.swift               SwiftUI Canvas waveform + state
    Settings/SettingsView.swift TabView shell
    Settings/GeneralTab.swift   hotkey recorder, launch-at-login
    Settings/ModelsTab.swift    transcription + cleanup model pickers
    Settings/CleanupTab.swift   toggle, OpenRouter key, privacy switches
    Settings/VocabularyTab.swift add/edit/import terms + variants
    Onboarding/PermissionsView.swift  guided grant + quit-relaunch
  Resources/
    Info.plist                  LSUIElement, NSMicrophoneUsageDescription
    Voicely.entitlements        sandbox=NO, audio-input=YES, hardened runtime
    warmup.wav                  tiny clip for model warmup-on-idle
VoicelyTests/
  HotKeyProcessorTests.swift  AppStateTests.swift  CleanupPromptTests.swift
  TextInserterTests.swift  VocabularyTests.swift  ModelManagerTests.swift
```

**Per-phase execution rule:** every component file has a sibling test where logic is pure; system-coupled code (CGEventTap, AVAudioEngine, NSPanel, AX) is thin and verified by manual smoke (see each gate). TDD the pure parts; smoke the OS parts.

---

## Phase 0 — Scaffold & gates

**Outcome:** A signed, non-sandboxed agent app launches, shows a menu-bar icon, no dock icon, and `xcodebuild test` runs a (passing, trivial) unit test.

**Tasks**
- [ ] Create Xcode macOS App project `Voicely` (SwiftUI lifecycle) + `VoicelyTests` unit test target. Set deployment target, Swift 6.
- [ ] Add SPM deps (WhisperKit, FluidAudio, KeyboardShortcuts, SettingsAccess, Sauce). Confirm they resolve + build.
- [ ] `Info.plist`: `LSUIElement=YES`, `NSMicrophoneUsageDescription="Voicely needs the mic to transcribe your speech on-device."`
- [ ] `Voicely.entitlements`: App Sandbox **off**, `com.apple.security.device.audio-input=YES`; enable Hardened Runtime; set a **stable signing identity** (free personal team) — see research §7 (TCC grants die on identity change).
- [ ] `VoicelyApp.swift` + delegate: `NSApp.setActivationPolicy(.accessory)`; create the folder skeleton above (empty stubs).
- [ ] Trivial unit test (e.g. `AppState` default = `.idle`) to prove the test target runs.

**Gate:** `xcodebuild -scheme Voicely build test` succeeds; launching shows a placeholder status item, no dock icon; mic usage string present.

---

## Phase 1 — Capture (hotkey + audio)

**Outcome:** Pressing the (configurable) hotkey logs `start`/`stop` with correct **tap-vs-hold** classification, and produces a `[Float]` 16 kHz mono buffer; the hotkey is settable in a recorder UI; pure state machine is unit-tested.

**Lift from:** Hex `HotKeyProcessor.swift` (+ its tests) and `KeyEventMonitorClient.swift`; Sauce for layout-correct keycodes.

**Key interfaces**
```swift
enum HotKeyOutput { case startRecording, stopRecording, cancel, lockToggle }
struct HotKeyProcessor {                    // PURE — fully unit-tested
    mutating func process(_ e: KeyEvent, now: TimeInterval) -> HotKeyOutput?
}
final class KeyEventMonitor {               // CGEventTap → calls a closure with KeyEvent
    init(onEvent: @escaping (KeyEvent) -> Void)
    func start() throws                       // requires Input Monitoring
}
final class AudioRecorder {
    func start() throws                       // AVAudioEngine tap off-main
    func stop() -> [Float]                     // converted to 16k mono Float32
    var levels: AsyncStream<Float> { get }     // RMS for the HUD
}
```

**Tasks**
- [ ] Port `HotKeyProcessor` + port/translate its unit tests (tap<250ms→toggle, hold≥250ms→push-release, double-tap-lock, Esc-cancel, autorepeat ignored). **Tests first.**
- [ ] `KeyEventMonitor` via CGEventTap (`.cgSessionEventTap`/`.headInsertEventTap`/`.defaultTap`, keyDown+keyUp+flagsChanged) → feed processor. Handle fn (`maskSecondaryFn`) + modifier-only (keyCode for side).
- [ ] `AudioRecorder`: AVAudioEngine input tap (off main) → `AVAudioConverter` → 16k mono Float32; expose RMS `levels`. Refresh input format on device change.
- [ ] `PermissionManager` (Input Monitoring + Accessibility checks; deep-link to System Settings; detect Secure-Input pause).
- [ ] Hotkey recorder UI (`KeyboardShortcuts.Recorder`) bound to `SettingsStore`; default Right-⌥.

**Gate (manual smoke):** unit tests green; tap toggles, hold push-talks (logged); recorded buffer length matches speech; rebinding the hotkey in Settings takes effect; "secure field paused" state appears in a password field.

---

## Phase 2 — Transcribe

**Outcome:** Speak → correct **raw** transcript appears (logged / temporary HUD text) within the latency budget, using the warm-loaded default engine; model is switchable.

**Lift from:** Pindrop `TranscriptionEngine` protocol + engine files; WhisperKit `WhisperAX` example for streaming/model-download patterns.

**Key interfaces**
```swift
protocol TranscriptionEngine {
    func prewarm() async throws
    func transcribe(_ samples: [Float]) async throws -> String   // 16k mono Float32
}
struct ModelOption { let id: String; let title, detail: String; let kind: EngineKind }
final class ModelManager {                  // list / download(progress) / select / persist
    var available: [ModelOption] { get }
    func engine(for: ModelOption) async throws -> TranscriptionEngine
}
```

**Tasks**
- [ ] `TranscriptionEngine` protocol + `ParakeetEngine` (FluidAudio `AsrManager`, one resident instance, **prewarm at launch**). Default model = Parakeet TDT v2 (EN).
- [ ] `WhisperKitEngine` (`ModelComputeOptions(.cpuAndNeuralEngine)`, `prewarmModels()`) + `AppleSpeechEngine` (SpeechAnalyzer; **verify API signatures in Xcode** per research §1 caveat).
- [ ] `ModelManager` (the 4 picker options, download-on-demand with progress, selection persisted to `SettingsStore`). Unit-test the option list + selection logic.
- [ ] Wire Capture→Transcribe in `AppCoordinator`: stop recording → transcribe → log/show raw text.

**Gate (manual smoke):** a spoken sentence transcribes correctly; release→text under ~0.8 s for a sentence (Parakeet); switching to Whisper in Settings works; no per-dictation cold-start lag (warm load confirmed).

---

## Phase 3 — Insert (MVP end-to-end, no cleanup)

**Outcome:** Dictate → raw text lands **at the cursor** in Notes, Slack, VS Code, a browser field, and Terminal; blocked-paste apps fall back to copy-only + toast. This is the first usable build.

**Lift from:** Pindrop `OutputManager` / Hex `PasteboardClient` (snapshot/restore + ⌘V + AppleScript-menu fallback).

**Key interfaces**
```swift
enum InsertResult { case inserted, copiedOnly }
protocol TextInserter { func insert(_ text: String) async -> InsertResult }
final class ClipboardPaster: TextInserter { /* snapshot→set→⌘V→restore + ownership token */ }
final class AXInserter { func tryInsert(_ text: String) -> Bool }   // optional first attempt
```

**Tasks**
- [ ] `ClipboardPaster`: save pasteboard+`changeCount` → set string → synth ⌘V (CGEvent) → restore after delay; ownership-token guard. Unit-test the fallback-selection logic (mock pasteboard).
- [ ] `AXInserter` optional first-attempt (`kAXSelectedTextAttribute`); on failure cascade to paste.
- [ ] `TextInserter` orchestrator: AX → paste → copy-only (toast via `UserNotifications`/HUD). Make AX-first a setting (default paste-first).
- [ ] Wire Transcribe→Insert in `AppCoordinator`. Add a real (minimal) HUD stub so the user sees state.

**Gate (manual smoke):** dictate the same sentence into all 5 app types; verify focus is never stolen (insertion lands correctly); force a copy-only path (e.g. a password field) and confirm the toast + clipboard.

---

## Phase 4 — Refine (AI cleanup)

**Outcome:** Raw transcript becomes clean text via OpenRouter (streamed); custom vocabulary corrects jargon; cleanup is toggleable and **falls back to raw** when off/offline/errored.

**Lift from:** Pindrop `AIEnhancementService` + `BuiltInPresets` (structured prompt pattern). API per research §5.

**Key interfaces**
```swift
final class CleanupService {
    func clean(_ raw: String, vocabulary: [VocabularyEntry]) async throws -> AsyncStream<String>
}
enum CleanupPrompt { static func system(vocabulary: [VocabularyEntry]) -> String }  // §6 spec
final class KeychainStore { func openRouterKey() -> String?; func set(_:) }
```

**Tasks**
- [ ] `CleanupPrompt.system(vocabulary:)` builds the spec §6 prompt + renders `{{CUSTOM_VOCABULARY}}`. **Unit-test** the rendering (terms, variants, empty list). 
- [ ] `KeychainStore` for the OpenRouter key (never UserDefaults).
- [ ] `CleanupService`: POST `…/chat/completions`, `gemini-2.5-flash-lite`, temp 0.1, `reasoning.enabled=false`, `stream=true`, `provider:{sort:"latency",data_collection:"deny",zdr:true}`; parse SSE. Errors/offline → return raw unchanged.
- [ ] Cleanup-model picker (4 options) + toggle in Settings; wire Transcribe→Refine→Insert in coordinator.

**Gate (manual smoke):** "um so like, send him the the thing tomorrow" → "Send him the thing tomorrow."; a vocab term ("Collabo") survives; toggle off → raw inserted; airplane-mode → raw inserted (no hang).

---

## Phase 5 — Shell & polish (the real UI)

**Outcome:** The full simple interface: state-driven menu-bar icon, focus-safe floating HUD with a live waveform, a complete Settings window, and guided permission onboarding. Launch-at-login works.

**Lift from:** Hex `InvisibleWindow.swift` (HUD panel). Interface visuals: see [`docs/specs/interface`](../specs/) (impeccable pass).

**Tasks**
- [ ] `StatusBarController` (`NSStatusItem`): template icons for idle/listening/processing; SwiftUI dropdown (start/stop, settings, quit).
- [ ] `HUDPanel` (non-activating `NSPanel`, `canBecomeKey=false`, `.floating`, all-Spaces+full-screen; `orderFrontRegardless`) hosting `HUDView`; **never** `NSApp.activate`. `HUDView` = `Canvas`+`TimelineView` waveform driven by `AudioRecorder.levels`.
- [ ] `SettingsView` TabView: General (hotkey recorder, launch-at-login via `SMAppService.mainApp`), Models (both pickers + download progress), Cleanup (toggle, key field, privacy switches), Vocabulary (add/edit/import + variants). Open via SettingsAccess (Tahoe `openSettings` fix).
- [ ] `Onboarding/PermissionsView`: guided mic + Accessibility + Input-Monitoring grant with deep-links and a "Quit & Reopen" button.
- [ ] `VocabularyView` persistence to `Application Support/Voicely/vocabulary.json`; unit-test load/save/import.

**Gate (manual smoke):** full round-trip with the real HUD; HUD shows over a full-screen app without stealing focus; every Settings control persists; toggling launch-at-login reflects in System Settings; first-run onboarding grants all three permissions.

---

## Phase 6 — Harden & install

**Outcome:** A stable app in `/Applications` you run daily.

**Tasks**
- [ ] Warmup-on-idle: transcribe bundled `warmup.wav` after launch to eliminate first-dictation lag (concept from VoiceInk; reimplement).
- [ ] Latency pass: measure release→insert; tune VAD/EOU + streaming paste if needed (streaming paste is the Tier-1 enhancement).
- [ ] Robustness: error toasts, missing-key handling, no-network handling, device-change handling, Secure-Input pause UX.
- [ ] Archive Release, sign with the stable identity, copy `Voicely.app` to `/Applications`; document first-launch (right-click→Open).
- [ ] Final smoke across the 5 app types + a week of dogfooding checklist.

**Gate:** daily-driver works: dictate into 5 apps with cleanup on, under the latency budget, no focus theft, working fallbacks, survives reboot (launch-at-login).

---

## How the agent team executes this (the "small team")

Per phase, via **subagent-driven-development**:
1. One subagent expands the phase into bite-sized TDD tasks and implements them, committing per task.
2. A second (reviewer) subagent verifies tests + the phase gate before moving on.
3. Phases are sequential (each builds on the last); within a phase, independent files (e.g. the three engines, the four Settings tabs) can be parallelized with `superpowers:dispatching-parallel-agents`, worktree-isolated if they'd touch the project file concurrently.
4. After Phase 3 (first usable build) and Phase 5 (full UI), pause for founder smoke-test on the real machine.

---

## Self-review (spec coverage)

| Spec requirement | Phase |
|---|---|
| Push-to-talk + tap-to-toggle, configurable hotkey | 1 |
| On-device STT, Parakeet default, manual model picker | 2 |
| Text insertion at cursor + fallbacks | 3 |
| AI cleanup via OpenRouter, toggle, raw fallback | 4 |
| Custom vocabulary (Refine layer) | 4 (+5 editor) |
| Menu-bar icon + focus-safe HUD + waveform | 5 |
| Settings (hotkey, models, cleanup+key, vocab, launch-at-login) | 5 |
| Privacy (zdr, no audio persisted) | 4 (routing) + 5 (switches) |
| Permissions onboarding, non-sandboxed, stable signing | 0 + 1 + 5 |
| Packaging / install / warmup | 6 |

No spec requirement is unassigned. No placeholders; interfaces named here match the spec.
