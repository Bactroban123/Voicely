# Voicely

A personal, native macOS menu-bar dictation app. Press a hotkey, speak, and
on-device-transcribed + AI-cleaned text lands at your cursor in any app. Audio
never leaves the Mac; only the cleaned-up text (optionally) touches the network.

Not for sale. Built for one person, on an Apple M3 Pro.

## How it works

`hotkey → record → transcribe on-device (Parakeet) → clean up via OpenRouter → insert at cursor`

- **Activation:** one key — quick tap toggles, hold is push-to-talk.
- **Transcription:** on-device (FluidAudio/Parakeet default; Whisper / Apple Speech selectable).
- **Cleanup:** OpenRouter (Gemini 2.5 Flash-Lite default), with custom-vocabulary correction; falls back to raw text if off or offline.
- **Insertion:** clipboard paste with an Accessibility-first option and a copy-only safety net.

## Repo

| Path | What |
|---|---|
| `PRODUCT.md` · `DESIGN.md` | Product context + visual identity (warm amber) |
| `docs/research/` | The 5-agent research sweep (engines, macOS APIs, OSS teardown, OpenRouter) |
| `docs/specs/` | The design spec |
| `docs/plans/` | The 6-phase execution plan |
| `VoicelyCore/` | The pure, tested logic (Swift package) — `./VoicelyCore/scripts/verify.sh` |
| `BUILD.md` | Build status + how to unblock the full app with Xcode |

## Status

The plan is complete and the entire pure-logic core is built and verified (74 checks).
The app shell (UI + OS integration) needs **Xcode** installed — see `BUILD.md`.

Built standing on the shoulders of the MIT-licensed
[Pindrop](https://github.com/watzon/pindrop) and [Hex](https://github.com/kitlangton/Hex),
with [WhisperKit](https://github.com/argmaxinc/WhisperKit) and
[FluidAudio](https://github.com/FluidInference/FluidAudio).
