# Voicely — Build & Status

## Where things stand (June 21 2026)

| Layer | Status |
|---|---|
| Research (5-agent sweep) | ✅ `docs/research/2026-06-21-research-findings.md` |
| Design spec | ✅ `docs/specs/2026-06-21-voicely-design.md` |
| Execution plan (6 phases) | ✅ `docs/plans/2026-06-21-voicely-execution-plan.md` |
| Interface + identity | ✅ `DESIGN.md` (warm-amber), `PRODUCT.md` |
| **VoicelyCore — hotkey state machine** | ✅ built + verified (tap/hold/lock) |
| **VoicelyCore — cleanup prompt + vocabulary** | ✅ built + verified |
| App shell (.app: UI, CGEventTap, audio, HUD, signing) | ⛔ blocked on Xcode (see below) |

## Environment note (important)

This machine has **Command Line Tools only — no Xcode**. Consequences:
- SwiftPM (`swift build` / `swift test` / `swift run`) **fails** on macOS targets here (it needs Xcode's macOS *platform* bundle: `xcrun --show-sdk-platform-path` errors).
- The Swift **compiler works**, so the pure-logic core is verified by compiling directly with `swiftc`.

### Verify the core right now (CLT only)
```bash
cd VoicelyCore && ./scripts/verify.sh      # compiles VoicelyCore + spec, runs all checks
```
Expected: `ALL PASS — 31 checks`.

## To unblock the full app (one-time, on your Mac)

1. **Install Xcode** from the App Store (or `xcodes install`), then:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   xcodebuild -version    # should now work
   ```
2. With Xcode present, the normal toolchain works:
   ```bash
   cd VoicelyCore && swift test     # runs the XCTest suite
   ```
3. Create the app target (Phase 0 of the execution plan): an Xcode macOS App that
   depends on the local `VoicelyCore` package, plus SPM deps WhisperKit
   (`argmaxinc/argmax-oss-swift`), FluidAudio, KeyboardShortcuts, SettingsAccess, Sauce.
   Set `LSUIElement`, non-sandboxed entitlements, `NSMicrophoneUsageDescription`, a stable
   signing identity. (Details: execution plan, Phase 0.)

## Layout
```
docs/            research · specs · plans
PRODUCT.md       product context (for /impeccable)
DESIGN.md        visual tokens (warm amber)
VoicelyCore/     SwiftPM package (pure, testable logic)
  Sources/VoicelyCore/   HotKeyProcessor, CleanupPrompt, Vocabulary
  Sources/voicely-spec/  runnable spec (CLT verification)
  Tests/                 XCTest suite (Xcode)
  scripts/verify.sh      swiftc-based verification (no Xcode needed)
```
