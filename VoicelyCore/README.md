# VoicelyCore

The pure, dependency-free logic at the heart of Voicely, split out (Hex-style) so
it can be reasoned about and tested in isolation, with no AppKit / AVFoundation /
network coupling. The Xcode app imports this package and wires it to the OS.

## What's here

| Type | Responsibility |
|---|---|
| `HotKeyProcessor` | One-key activation: quick tap = toggle, hold = push-to-talk, tap-again/Esc = stop/cancel |
| `Pipeline` | idle → recording → transcribing → (refining) → inserting, incl. cleanup-off and cleanup-fail-→-raw fallbacks |
| `CleanupPrompt` + `VocabularyEntry` | The OpenRouter cleanup system prompt + custom-vocabulary injection |
| `CleanupRequest` | The OpenRouter chat-completions request body (temp 0.1, reasoning off, latency routing, ZDR) |
| `SSE` | Parses streamed `data:` lines into text deltas |
| `InsertPlan` | The insertion fallback policy: accessibility → paste → copy-only |
| `ModelCatalog` | The selectable transcription + cleanup models and their defaults |

## Verify

```bash
# Command Line Tools only (no Xcode): compiles sources + runs the spec.
./scripts/verify.sh          # → ALL PASS — 74 checks

# With full Xcode installed:
swift test                   # runs the XCTest suite (mirrors the spec)
```

The XCTest suite under `Tests/` is the canonical suite for CI once Xcode is
present; `Sources/voicely-spec` is a runnable mirror for CLT-only machines (see
`../BUILD.md` for why SwiftPM needs Xcode here).
