# Voicely — Design Spec

> A personal, native macOS voice-to-text app (a Wispr Flow-style dictation tool).
> Status: **approved design, pre-implementation.** Date: June 21 2026.
> Evidence base: [`docs/research/2026-06-21-research-findings.md`](../research/2026-06-21-research-findings.md).
> Target: **Apple M3 Pro, 18 GB, macOS 26.5 (Tahoe)** — single-user, not for sale.

---

## 1. What it is

A menu-bar app that lives quietly in the corner. Press a hotkey anywhere → speak → and polished text lands at your cursor in whatever app is focused — Slack, Notes, the browser, your editor. Speech recognition runs **entirely on-device**; with cleanup on, only the *text* (never audio) touches the network, via your OpenRouter account.

**Design tenets**
1. **Invisible until summoned** — no main window, no dock icon; a status icon + a small recording HUD are the whole UI.
2. **On-device by default** — audio never leaves the Mac.
3. **Fast enough to trust** — target **< 1.5 s** from key-release to inserted text for a normal sentence.
4. **Never lose a transcript** — every failure path falls back to "it's on your clipboard."
5. **Stand on giants' shoulders** — copy proven patterns from the MIT-licensed Pindrop + Hex rather than reinventing the hard native parts.

---

## 2. Architecture — four components + shell

```
                          ┌─────────────────────────────────────────────┐
                          │                 AppCoordinator                │
                          │      (owns state machine + wiring)            │
                          └───────────────────────┬─────────────────────┘
        hotkey events          audio              │            final text
   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
   │   CAPTURE    │──▶│  TRANSCRIBE  │──▶│    REFINE    │──▶│    INSERT    │
   │ CGEventTap + │   │ Parakeet/    │   │ OpenRouter   │   │ paste→AX→    │
   │ AVAudioEngine│   │ WhisperKit/  │   │ cleanup LLM  │   │ copy-only    │
   │              │   │ AppleSpeech  │   │ (+vocab)     │   │              │
   └──────────────┘   └──────────────┘   └──────────────┘   └──────────────┘
            │                                   │                    │
            └──────────────┬────────────────────┴────────────────────┘
                  ┌────────┴─────────┐   ┌──────────────┐
                  │  Menu-bar item   │   │  Floating HUD │   (state indicators)
                  │  (NSStatusItem)  │   │  (NSPanel)    │
                  └──────────────────┘   └──────────────┘
                  ┌──────────────────────────────────────┐
                  │  Settings · Vocabulary · Preferences  │
                  └──────────────────────────────────────┘
```

Each component is a Swift type behind a protocol so it can be unit-tested in isolation and swapped (e.g. transcription engines).

### 2.1 Capture — `HotKeyMonitor` + `AudioRecorder`
- **Hotkey:** a **CGEventTap** on `.keyDown`/`.keyUp`/`.flagsChanged` feeding a **pure tap/hold state machine** (lifted from Hex's `HotKeyProcessor`, MIT). Logic: start recording on key-down; on key-up, `dt < 250 ms` = **tap-to-toggle** (keep recording until next tap), `dt ≥ 250 ms` = **hold-to-talk** (stop on release). Ignore autorepeat; swallow printable hotkeys. `Esc` cancels.
- **Hotkey is user-configurable in-app** — a first-class recorder in Settings (`KeyboardShortcuts.Recorder` for capture UI; our CGEventTap drives the actual tap/hold logic). Ships with **Right-`⌥`** pre-filled as a sensible default, but the user sets whatever they want. fn/Globe is allowed with a "collides with system Dictation/emoji" warning.
- **Secure Input:** when a password field disables the tap, show a "paused (secure field)" state — unavoidable by OS design.
- **Audio:** `AVAudioEngine` mic tap (installed off-main) → `AVAudioConverter` → **16 kHz mono Float32**; FluidAudio's Silero VAD/EOU trims silence. RMS levels published to the HUD on the MainActor.

### 2.2 Transcribe — `TranscriptionEngine` protocol
- `func transcribe(_ samples: [Float]) async throws -> String`, plus `loadModel` / `prewarm`.
- Implementations: **`ParakeetEngine`** (FluidAudio — default), `WhisperKitEngine` (large-v3-turbo — max languages + STT vocab), `AppleSpeechEngine` (SpeechAnalyzer — zero-download, macOS 26+).
- **Default model: Parakeet TDT v2 (English).** Model **warm-loaded** at launch and kept resident (no per-dictation cold start).
- **Manual model picker** (the 4 options) lives in Settings; download-on-demand with progress.

### 2.3 Refine — `CleanupService`
- Sends raw transcript + the user's custom-vocabulary list to **OpenRouter** (`google/gemini-2.5-flash-lite` default), **streaming**, temp 0.1, thinking off, `provider:{sort:"latency", data_collection:"deny", zdr:true}`.
- **Toggleable**; on error/offline it **falls back to the raw transcript** (never blocks insertion).
- Custom vocabulary is applied *here* (works with any STT engine). Cleanup-model picker in Settings.
- System prompt: see §6.

### 2.4 Insert — `TextInserter`
- Fallback chain: **clipboard paste-and-restore (⌘V)** default → optional AX `kAXSelectedTextAttribute` first-attempt → **copy-only + toast** if paste is blocked. Restore the prior clipboard after a short delay; guard with a session-ownership token so a clipboard manager can't clobber.

### 2.5 Shell
- **Menu-bar:** `NSStatusItem` with a state-driven template icon (idle / listening / processing) + a small SwiftUI dropdown (start/stop, open Settings, recent transcript, quit).
- **HUD:** non-activating `NSPanel` (`canBecomeKey = false`, `.floating`, joins all Spaces incl. full-screen), SwiftUI `Canvas`+`TimelineView` waveform. **Never** calls `NSApp.activate` — focus must stay on the target app or insertion breaks. (Lift Hex's `InvisibleWindow`.)
- **No dock icon:** `LSUIElement = YES` + `setActivationPolicy(.accessory)`.
- **Settings:** SwiftUI `Settings` scene + the activation dance / `SettingsAccess` fallback (`openSettings` is broken on Tahoe).

---

## 3. The core loop (state machine)

```
 idle ──[hotkey down]──▶ recording ──[tap<250ms]──▶ recording(locked) ──[tap]──┐
   ▲                         │                                                  │
   │                         └──[hold release ≥250ms]──┐                        │
   │                                                    ▼                        ▼
   └──── insert ◀── refine ◀── transcribe ◀──────── stopping ◀──────────────────┘
                    (skip if cleanup off / on error → raw)
        Esc at any recording state → cancel → idle (no insert)
```
Each transition updates the menu-bar icon + HUD. Latency budget: capture stop → transcribe (~0.3–0.5 s) → refine (~0.3–0.7 s streamed) → insert. Streaming paste (Tier-1) makes refine feel instant.

---

## 4. Data & storage
- **`UserDefaults`/`@AppStorage`:** hotkey, selected transcription + cleanup models, cleanup on/off, HUD position, launch-at-login, privacy toggles.
- **`~/Library/Application Support/Voicely/vocabulary.json`:** custom vocab (`Codable`; term + optional misheard-variants; importable).
- **Keychain:** OpenRouter API key.
- **No audio is ever persisted.** Transcript history is **out of v1** (deferred).

---

## 5. Privacy posture
- Audio is processed on-device and discarded; never written to disk or network.
- Cleanup ON → only transcript text → OpenRouter with `data_collection:"deny"` + `zdr:true` (zero-retention routing). Cleanup OFF → **nothing leaves the Mac.**
- A clear, always-visible recording indicator (HUD + menu icon) and an instant kill (`Esc` / tap).

---

## 6. The cleanup system prompt (Refine)

```
You are a dictation cleanup engine. You receive a raw speech-to-text transcript and
return a corrected version of the SAME text. You are an editor, not an assistant.

RULES — follow exactly:
1. Fix capitalization, punctuation, and obvious spacing. Add sentence/paragraph
   breaks only where the speaker clearly paused or changed thought.
2. Remove filler words and false starts: "um", "uh", "er", filler "like",
   "you know", "I mean", repeated words, and abandoned half-sentences. Keep these
   words when they carry real meaning.
3. Apply light formatting only: turn an obvious spoken list into a list; convert
   spoken commands "new line"/"new paragraph"/"period"/"comma"/"question mark"
   into the actual formatting/punctuation, and do not print them as words.
4. Apply the custom vocabulary corrections below. When the transcript contains a
   clear misrecognition of a listed term (by sound or spelling), replace it with
   the correct term. Match case sensibly.
5. DO NOT add, invent, summarize, answer, explain, translate, or expand anything.
   Never introduce facts, names, or sentences the speaker did not say. Preserve the
   speaker's wording, meaning, tone, and language. If unsure, leave it unchanged.
6. If the transcript is already clean, return it unchanged.
7. Output ONLY the cleaned text. No preamble, quotes, markdown fences, or commentary.

CUSTOM VOCABULARY (correct misheard variants TO these exact spellings):
{{CUSTOM_VOCABULARY}}
```
Raw transcript goes in the **user** message. `{{CUSTOM_VOCABULARY}}` renders as a bullet list (with known misheard variants when available — the biggest accuracy lever).

---

## 7. Scope

**In (v1)**
- Push-to-talk **and** tap-to-toggle dictation, system-wide.
- On-device transcription (Parakeet default) with a **manual model picker**.
- AI cleanup via OpenRouter (toggleable, with a **manual model picker**), graceful raw-text fallback.
- Custom vocabulary (applied in Refine).
- Menu-bar item + floating HUD + Settings; launch-at-login; permission onboarding.

**Out (later — see research §2.3 backlog)**
- Transcription history · streaming paste · spoken-command edit mode · app-aware tone presets · per-app "power modes" · multi-language polish · snippets · cross-device sync.

**Non-goals:** file/meeting transcription, team features, a proprietary STT model, Mac App Store distribution.

---

## 8. Risks & mitigations
| Risk | Mitigation |
|---|---|
| Tahoe `openSettings` broken | SettingsAccess / hidden-window fallback (budgeted) |
| Paste blocked in locked-down apps | copy-only fallback + toast |
| Electron AX unreliable | paste-first default; AX only where QA'd |
| TCC grants dropped on rebuild | stable signing identity from day one |
| HUD steals focus → insertion breaks | non-activating panel, `canBecomeKey=false`, never `NSApp.activate` |
| Model cold-start lag | warm-load at launch; warmup-on-idle (Tier-1) |
| Apple SpeechAnalyzer API uncertainty | verify signatures in Xcode; Parakeet is the default regardless |

---

## 9. Build-from references (licensing-safe)
Copy from **Pindrop** (MIT) + **Hex** (MIT); add **WhisperKit** (MIT) + **FluidAudio** (Apache-2.0) as SPM deps; study **VoiceInk** (GPLv3) for patterns only. Component→file map in research §6.

---

## 10. Verification strategy
- **Unit tests** (pure logic, no system deps): the tap/hold state machine, the core app state machine, vocabulary rendering, cleanup-prompt assembly, the insert fallback selection.
- **Manual smoke** (the parts that need real OS): hotkey across apps, paste into Slack/VS Code/Notes/browser/terminal, permission onboarding + relaunch, HUD-focus non-theft, latency stopwatch.
- Definition of done for v1: dictate a sentence into 5 different apps with cleanup on, under the latency budget, with no focus theft and a working copy-only fallback.
