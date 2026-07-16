# Task Cards — M2 Meeting Notes, 2026-07-16

Plan: `~/.claude/plans/voicely-is-causing-a-buzzing-pumpkin.md` (M2 section) + the M1.5 backlog's M2-reference section. Branch `claude/voicely-debug-features-35d40b`. Reviewer note: `OPENROUTER_API_KEY` absent → GLM red-team unavailable; each slice gets an independent fresh-Claude deep review and the PR is marked **single-model-reviewed**.

**Locked scope:** live capture (mic + system audio), macOS only, in-app + Markdown export. Manual start/stop from the menu bar (no calendar auto-detect). Deferred: diarization, Reminders/Obsidian-direct, live streaming transcript, Windows.

**Settled by the S1 spike (2026-07-16), before any code:**
- Core Audio process taps capture **real** system audio from an **unsigned** binary — 219,136 frames, peak amplitude 0.175 while audio played. **No Apple Developer ID needed**, which (with Sparkle dropped as personal-use) empties the backlog's BLOCKED tier.
- Tap delivers **48 kHz mono Float32** → must resample to the 16 kHz the ASR engines expect.
- ScreenCaptureKit is **not** needed. Good: its prompt says "record this computer's screen", which contradicts the privacy pitch.
- Context: the deleted prior prototype (see `Voicely-archive/`) was **mic-only** and never captured the other side. This slice is the reason the feature is worth building.

---

## Card M2-S1 — capture

- **Project:** voicely
- **Task:** Capture mic + system audio simultaneously to separate disk-backed tracks
- **Business goal:** The other side of the call is the whole point — a meeting recorder that only hears you is why the last attempt was abandoned
- **Tags:** audio, hot-path
- **Protocols bound:** 00, 07
- **Founder Gate:** no (nothing auto-sends; recording is user-initiated)
- **GLM red-team:** would be YES (concurrency + new system-level capture) → two independent fresh-Claude reviews instead
- **Risk level:** high — new OS surface, real-time callbacks, must not disturb dictation

### Scope
`App/Meetings/SystemAudioTap.swift` (process tap → private aggregate device → IOProc, teardown, device-change handling), `App/Meetings/MeetingRecorder.swift` (two tracks → 16 kHz mono CAF chunks, 5-min rotation, pause/resume), `App/Info.plist` (`NSAudioCaptureUsageDescription`), permission surfacing.

### Non-goals
No transcription (S2), no summary (S3), no UI beyond what's needed to drive a test (S4), no retention policy (S6). No diarization ever in v1 — two tracks give Me/Them for free.

### Files / areas not to touch
`App/Capture/AudioRecorder.swift`, `RecordingController`, `DictationSession`, `Pipeline` — the dictation vertical must not share a live object with meetings. `windows/`.

### Success metric
A 30–60 min dual-track recording with flat memory, where the system track contains the other participants and the mic track contains only the user.

### Verification plan
Gates (`swift test`, `xcodebuild`, `swiftlint --strict`). Spike-level: peak-amplitude assertions on both tracks (already proven for system audio). Manual: a real Zoom/Meet call; AirPods connected mid-recording; permission-denied path; Instruments for flat memory over 30+ min; **dictation must still work while a meeting records**.
