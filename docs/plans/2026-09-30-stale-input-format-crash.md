# Task Card — stale input format crash

- **Project:**            voicely
- **Task:**               Stop `installTap` aborting the app after an audio input device switch
- **Business goal:**      Voicely died mid-use on 2026-09-30 and stayed dead until relaunched
- **Tags:**               native, concurrency
- **Protocols bound:**    per bindings (concurrency)
- **Founder Gate:**       no (no auth/money/migrations/prod/DNS/keys)
- **GLM red-team:**       yes (concurrency) — OPENROUTER_API_KEY unset → single-model-reviewed
- **Risk level:**         medium — audio capture path used by every dictation and meeting

## Evidence

- `~/Library/Logs/Voicely/last-crash.log` (2026-09-30 22:52): uncaught
  `com.apple.coreaudio.avfaudio` — `required condition is false:
  format.sampleRate == inputHWFormat.sampleRate`, thrown from
  `AudioRecorder.beginCapture()` → `installTap`. The app had been up since
  09-28 and had logged ~580 idle "audio config changed" events (AirPods /
  iPhone mic / built-in mic churn).
- Reproduced in isolation: point an idle, prepared `AVAudioEngine`'s input at
  a device with a different rate. `inputNode.outputFormat(forBus: 0)` keeps
  the OLD rate (96 kHz) while `inputFormat(forBus: 0)` reports the new
  hardware rate (48 kHz); `prepare()` does not refresh it. `installTap` with
  the output format throws the exact exception above; a fresh
  `AVAudioEngine` reports matching formats.

## Scope

- `AudioRecorder` (dictation): before installing the tap, detect a stale
  input format and replace the engine with a fresh one; if the formats still
  disagree, throw a Swift error instead of letting AVFAudio abort.
- `MeetingRecorder` (meetings): same guard in `startMic()`, which the
  mid-meeting device-change rebuild also goes through.

## Non-goals

- The offline model-load failure seen in the log (WhisperKit resolving the
  repo online even though weights are on disk) — separate change.
- Committing the pre-existing uncommitted ModelStorage / WhisperKit work.
- `windows/` (macOS only).

## Files / areas not to touch

- `App/Transcribe/*`, `App/RecordingController.swift`, `VoicelyCore/*ModelStorage*`
  (someone else's uncommitted work in the tree).

## Success metric

n/a (crash fix) — zero `inputHWFormat` aborts in `last-crash.log`.

## Verification plan

- Gates: `swift test` (VoicelyCore), `xcodebuild` app build, SwiftLint.
- Repro harness re-run against the fixed decision logic.
- Install, relaunch, confirm launch + a real dictation in the log.
