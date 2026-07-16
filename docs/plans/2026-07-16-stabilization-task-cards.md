# Task Cards — Stabilization program (M0/M1), 2026-07-16

Full plan: Claude plan file `voicely-is-causing-a-buzzing-pumpkin.md` (M0 safety net → M1 fixes → M1.5 research → M2 meeting notes). Branch `claude/voicely-debug-features-35d40b`. Reviewer note: `OPENROUTER_API_KEY` absent on this machine → GLM red-team unavailable; every slice gets an independent fresh-Claude deep review instead and the PR is marked **single-model-reviewed** (dev-os fallback rule).

---

## Card PR1 — tests green + suite consolidation

- **Project:** voicely
- **Task:** Fix stale CleanupModes count test, port AutoLearn checks to XCTest, retire the duplicate `voicely-spec` runner
- **Business goal:** A trustworthy, single test suite that can gate every future fix (today `swift test` is red and the duplicate spec runner has drifted)
- **Tags:** testing
- **Protocols bound:** 00, 07
- **Founder Gate:** no
- **GLM red-team:** no (would be n/a; single-model fallback applies program-wide)
- **Risk level:** low — test files + deletion of an unused executable target

### Scope
`SnippetAndModeTests.swift:34` 5→7 + translate-th/th-en assertions; new `AutoLearnTests.swift` porting the spec-runner's AutoLearn checks 1:1; delete `VoicelyCore/Sources/voicely-spec/`, `VoicelyCore/scripts/verify.sh`, its Package.swift target; update `BUILD.md`/`docs/STATUS.md` refs.

### Non-goals
No production-code changes. No test behavior changes beyond the stale literal.

### Files / areas not to touch
`App/`, `VoicelyCore/Sources/VoicelyCore/` production sources, `windows/`.

### Success metric
n/a (plumbing).

### Verification plan
`cd VoicelyCore && swift test` green (count ≥ 55 + new AutoLearn tests, 0 failures); `grep -r voicely-spec` clean outside .git; app still builds.

---

## Card PR2 — CI + lint gates

- **Project:** voicely
- **Task:** Add push/PR CI (unit-tests + app-build jobs) and a narrow SwiftLint ruleset
- **Business goal:** No change lands unverified again — today tests only run when cutting a release tag, and the macOS release never runs them
- **Tags:** ci, deployment
- **Protocols bound:** 00, 07, 09
- **Founder Gate:** no (adds a workflow; doesn't touch release/signing)
- **GLM red-team:** no
- **Risk level:** low — additive workflow + config

### Scope
`.github/workflows/ci.yml` (macos-15: `swift test` job + `xcodegen`/`xcodebuild` job with SPM caches + `swiftlint --strict`); `.swiftlint.yml` `only_rules:` allowlist (force_unwrapping, force_try, force_cast, unused_closure_parameter — `unused_import` dropped: it's an analyzer-only rule that plain `swiftlint lint` never runs), `excluded: [windows, .build-xcode, VoicelyCore/.build, site]`.

### Non-goals
No changes to `release.yml`/`windows.yml`; no auto-fix/format sweep.

### Files / areas not to touch
Release workflows, `windows/`, app sources (except if a lint hit must be annotated — prefer fixing in PR7's P2 batch instead).

### Success metric
n/a (plumbing).

### Verification plan
`swiftlint lint --strict` locally clean (or documented pending-fix carried by PR7); workflow YAML validated (`actionlint` if available, else careful review); first CI run green once pushed.

---

## Card PR3 — observability foundation

- **Project:** voicely
- **Task:** os.Logger facade + rotating file log + crash/signal capture + tap-latency canary + Diagnostics tab
- **Business goal:** Failures stop being invisible; field incidents (like "Voicely broke my terminal") become diagnosable after the fact
- **Tags:** observability, logging
- **Protocols bound:** 00, 07, 10
- **Founder Gate:** no
- **GLM red-team:** no
- **Risk level:** medium — signal handlers must be async-signal-safe; logging must never block the tap callback

### Scope
`App/Diagnostics/VoicelyLog.swift`, `FileLogMirror.swift` (~/Library/Logs/Voicely, 5MB×2, serial utility queue, ring buffer), `CrashReporter.swift` (uncaught-exception + SIGABRT/ILL/SEGV/FPE/BUS/TRAP via pre-opened fd + `write(2)`, re-raise; MetricKit subscriber best-effort), replace 5 NSLog call sites (transcript content → `.private`), tap-callback wall-time canary (>8ms warn + os_signpost), `DiagnosticsView.swift` 5th Settings tab + permission status reads (prompt:false).

### Non-goals
No telemetry/network transmission; no behavior change to the dictation pipeline itself.

### Files / areas not to touch
`VoicelyCore` reducers; `TextInserter`; `windows/`.

### Success metric
n/a (plumbing), enables everything after.

### Verification plan
swift test + build green; debug `fatalError()` → crash marker + log tail on relaunch; Diagnostics tab shows real permission states; stalled-tap debug flag triggers canary warning; log rotation observed at 5MB (synthetic spam).

---

## Card PR4 — P0-1 tap/audio decoupling

- **Project:** voicely
- **Task:** Move AVAudioEngine start/stop off the CGEventTap callback onto a serial audio queue; pre-warm engine; handle config changes
- **Business goal:** Voicely must never again stall system-wide keyboard delivery (the likely "broke Claude Code sessions" mechanism) — this is the core Wispr-differentiating fix
- **Tags:** concurrency, hot-path
- **Protocols bound:** 00, 07
- **Founder Gate:** no
- **GLM red-team:** would be YES (concurrency-sensitive) → single-model deep review ×2 reviewers instead
- **Risk level:** high — core hot path; ordering between start/stop must be provably FIFO

### Scope
`RecordingController.handle` enqueues recorder I/O on `DispatchQueue("com.voicely.audiorecorder")` (FSM classification stays sync); `AudioRecorder` pre-warm (`prepare()` at launch + re-arm after stop), start-latency measurement, `AVAudioEngineConfigurationChange` observation.

### Non-goals
No FSM semantics change (that's PR5). No engine/model changes.

### Files / areas not to touch
`VoicelyCore` (this PR is App-layer only), `TextInserter`.

### Success metric
Tap-callback canary <8ms worst case during recording start/stop (was: unbounded).

### Verification plan
swift test + build green; install; dictate while watching canary logs; rapid start/stop spam; Bluetooth mic connect mid-recording; push-to-talk latency subjectively unchanged + logged start latency compared before/after.

---

## Card PR5 — DictationSession unification (P0-3 + P1-4)

- **Project:** voicely
- **Task:** Compose HotKeyProcessor + Pipeline into a pure DictationSession with busy-reject, token-guarded async completions, Esc-cancel-while-busy, and clean start-failure unwind
- **Business goal:** No dictation is ever silently discarded or pasted stale — the top "it feels broken" bug class
- **Tags:** state-machine
- **Protocols bound:** 00, 07
- **Founder Gate:** no
- **GLM red-team:** YES per bindings (state machine) — unavailable → TWO independent fresh-Claude adversarial reviews + exhaustive transition tests
- **Risk level:** high — state-machine surgery on the product's core loop

### Scope
New `VoicelyCore/Sources/VoicelyCore/DictationSession.swift` + `DictationSessionTests.swift`; `RecordingController` rewired to drive the session with tokens; HUD busy hint + "Couldn't start recording" surface. `HotKeyProcessor.swift`/`Pipeline.swift` and their tests untouched.

### Non-goals
No queueing of busy presses (rejected by design — focus may move); no changes to insertion.

### Files / areas not to touch
`HotKeyProcessor.swift`, `Pipeline.swift`, their test files, `windows/`.

### Success metric
Hotkey-spam QA: exactly one dictation in flight, zero silent drops (was: second dictation silently discarded).

### Verification plan
New tests: busy-reject, stale-completion-after-cancel, fresh-session-after-cancel, Esc-during-refining; all existing tests green unmodified; manual hotkey spam + Esc-during-slow-cleanup.

---

## Card PR6 — event-tap robustness (P0-2 + P1-5)

- **Project:** voicely
- **Task:** Re-enable the tap on timeout/user-input disable with user notice; derive modifier up/down from event flag bits
- **Business goal:** The hotkey never silently dies until relaunch; modifier state can't invert and wedge
- **Tags:** hot-path
- **Protocols bound:** 00, 07
- **Founder Gate:** no
- **GLM red-team:** no (small, well-isolated; single-model review)
- **Risk level:** medium — touches the tap callback switch

### Scope
`KeyEventMonitor`: `.tapDisabledByTimeout/.tapDisabledByUserInput` → `tapEnable(true)` + `onTapIssue` (3+ in 60s → persistent notice). New pure `ModifierKeyTracking.swift` (device-bit map verified against IOLLEvent.h, Set fallback for unmapped codes) + tests incl. same-flags-twice idempotence.

### Non-goals
No hotkey semantics changes.

### Files / areas not to touch
`RecordingController` beyond wiring `onTapIssue`; `Pipeline`/`HotKeyProcessor`.

### Success metric
Forced tap disable self-recovers without relaunch (was: dead until relaunch).

### Verification plan
Unit tests for bit map; debug-stall forced timeout → recovery log; hold/release each of the 5 hotkey options rapidly; sleep/wake with modifier held.

---

## Card PR7 — P1/P2 batch

- **Project:** voicely
- **Task:** Clipboard changeCount guard + cancellable restore; cleanup timeout + cancellation; Monster Arena timer lifecycle; P2 hardening batch
- **Business goal:** Kill the remaining "problems on my computer": clipboard clobbering, minute-long stuck states, background CPU drain, silent zero-sample recordings
- **Tags:** ai (cleanup call path), ui
- **Protocols bound:** 00, 06, 07
- **Founder Gate:** no
- **GLM red-team:** no (single-model review)
- **Risk level:** medium — several small independent fixes

### Scope
`TextInserter` (DispatchWorkItem + changeCount), `CleanupService` (timeoutInterval 12, CancellationError short-circuit) + cancel path from RecordingController, `SettingsWindowController.windowWillClose` contentViewController=nil + `ArenaEngine.deinit`, `AudioRecorder` converter-nil throws + format guard, observer token removal, remove `apple-speech` catalog entry (+ test count updates).

### Non-goals
AX direct insertion (M1.5 backlog); clipboard history stack (documented burst limitation accepted).

### Files / areas not to touch
`windows/`, release workflows.

### Success metric
Settings-close CPU ~0% within 1s (was: 60Hz timer forever); cleanup worst-case stall 12s (was 60s).

### Verification plan
swift test + build green; manual: monsters tab close → Activity Monitor; copy → dictate → clipboard restored; airplane-mode cleanup → raw transcript inserted ≤12s; model picker no longer lists Apple Dictation.
