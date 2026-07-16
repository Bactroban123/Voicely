import XCTest
@testable import VoicelyCore

final class DictationSessionTests: XCTestCase {
    private let hotKey: UInt16 = 61
    private let esc: UInt16 = 53

    private func makeSession(cleanup: Bool = false) -> DictationSession {
        DictationSession(config: HotKeyConfig(hotKeyCode: hotKey), cleanupEnabled: cleanup)
    }

    private func down(_ code: UInt16, at t: TimeInterval, isRepeat: Bool = false) -> KeyEvent {
        KeyEvent(keyCode: code, phase: .down, timestamp: t, isRepeat: isRepeat)
    }

    private func up(_ code: UInt16, at t: TimeInterval) -> KeyEvent {
        KeyEvent(keyCode: code, phase: .up, timestamp: t)
    }

    /// Starts a take and confirms the engine started. Returns the take's token.
    @discardableResult
    private func startTake(_ s: inout DictationSession, at t: TimeInterval = 0) -> DictationSession.Token {
        guard case .startRecording(let token) = s.handleKey(down(hotKey, at: t)) else {
            XCTFail("expected .startRecording"); return DictationSession.Token(value: -1)
        }
        XCTAssertEqual(s.recordingStarted(token), .none)
        return token
    }

    /// Drives a take to the point where transcription has begun.
    @discardableResult
    private func driveToTranscribing(_ s: inout DictationSession, from t: TimeInterval = 0) -> DictationSession.Token {
        let token = startTake(&s, at: t)
        XCTAssertEqual(s.handleKey(up(hotKey, at: t + 1.0)), .stopRecording(token))
        XCTAssertEqual(s.recordingStopped(token), .beginTranscription(token))
        XCTAssertEqual(s.pipelineState, .transcribing)
        return token
    }

    // MARK: - Happy paths

    func testHoldToTalkFlowWithoutCleanup() {
        var s = makeSession(cleanup: false)
        let token = driveToTranscribing(&s)
        XCTAssertEqual(s.transcriptReady("hello world", token: token), .insert("hello world", token))
        XCTAssertEqual(s.inserted(success: true, token: token), .none)
        XCTAssertEqual(s.pipelineState, .idle)
        XCTAssertFalse(s.isRecorderLive)
    }

    func testTapToggleFlowWithCleanup() {
        var s = makeSession(cleanup: true)
        let token = startTake(&s)
        XCTAssertEqual(s.handleKey(up(hotKey, at: 0.1)), .none) // tap → locked on
        XCTAssertEqual(s.pipelineState, .recording)
        XCTAssertEqual(s.handleKey(down(hotKey, at: 2.0)), .stopRecording(token))
        XCTAssertEqual(s.recordingStopped(token), .beginTranscription(token))
        XCTAssertEqual(s.transcriptReady("raw text", token: token), .beginCleanup("raw text", token))
        XCTAssertEqual(s.cleaned("Clean text.", token: token), .insert("Clean text.", token))
        XCTAssertEqual(s.inserted(success: true, token: token), .none)
        XCTAssertEqual(s.pipelineState, .idle)
    }

    func testCleanupFailureFallsBackToRawTranscript() {
        var s = makeSession(cleanup: true)
        let token = driveToTranscribing(&s)
        XCTAssertEqual(s.transcriptReady("raw take", token: token), .beginCleanup("raw take", token))
        XCTAssertEqual(s.cleanupFailed(token: token), .insert("raw take", token))
    }

    func testReleaseExactlyAtThresholdIsAHoldAndStops() {
        var s = makeSession()
        let token = startTake(&s)
        // dt == tapThreshold (0.25) is NOT a tap: it stops.
        XCTAssertEqual(s.handleKey(up(hotKey, at: 0.25)), .stopRecording(token))
    }

    // MARK: - Busy handling (the P0-3 fix)

    func testPressWhileTranscribingIsRejectedAndOriginalTakeSurvives() {
        var s = makeSession()
        let token = driveToTranscribing(&s)
        XCTAssertEqual(s.handleKey(down(hotKey, at: 5)), .busyRejected)
        XCTAssertEqual(s.handleKey(up(hotKey, at: 5.1)), .none) // voided press: no lock, no stop
        XCTAssertEqual(s.transcriptReady("first take", token: token), .insert("first take", token))
    }

    func testPressWhileRefiningIsRejected() {
        var s = makeSession(cleanup: true)
        let token = driveToTranscribing(&s)
        XCTAssertEqual(s.transcriptReady("raw", token: token), .beginCleanup("raw", token))
        XCTAssertEqual(s.handleKey(down(hotKey, at: 5)), .busyRejected)
        XCTAssertEqual(s.pipelineState, .refining)
    }

    func testPressWhileInsertingIsRejected() {
        var s = makeSession()
        let token = driveToTranscribing(&s)
        XCTAssertEqual(s.transcriptReady("text", token: token), .insert("text", token))
        XCTAssertEqual(s.pipelineState, .inserting)
        XCTAssertEqual(s.handleKey(down(hotKey, at: 5)), .busyRejected)
    }

    func testRePressBeforeStartConfirmationDoesNotDropTheFirstTake() {
        // The engine can take hundreds of ms to confirm; during that window the
        // pipeline is still .idle, so a second press must be rejected on
        // takeInFlight — not silently supersede take 1.
        var s = makeSession()
        guard case .startRecording(let token) = s.handleKey(down(hotKey, at: 0)) else {
            return XCTFail("expected .startRecording")
        }
        XCTAssertEqual(s.handleKey(up(hotKey, at: 0.5)), .stopRecording(token)) // hold released
        XCTAssertEqual(s.pipelineState, .idle)                                   // start not confirmed yet
        XCTAssertEqual(s.handleKey(down(hotKey, at: 0.6)), .busyRejected)        // must not steal the take
        // Take 1's confirmations still land and it completes normally.
        XCTAssertEqual(s.recordingStarted(token), .none)
        XCTAssertEqual(s.recordingStopped(token), .beginTranscription(token))
        XCTAssertEqual(s.transcriptReady("survived", token: token), .insert("survived", token))
    }

    func testVoidedBusyPressDoesNotActLikeAToggleLater() {
        var s = makeSession()
        let token = driveToTranscribing(&s)
        XCTAssertEqual(s.handleKey(down(hotKey, at: 5)), .busyRejected)
        XCTAssertEqual(s.handleKey(up(hotKey, at: 5.05)), .none)
        XCTAssertEqual(s.transcriptReady("first", token: token), .insert("first", token))
        XCTAssertEqual(s.inserted(success: true, token: token), .none)
        // A fresh press must START, not stop.
        guard case .startRecording = s.handleKey(down(hotKey, at: 6)) else {
            return XCTFail("expected a fresh .startRecording")
        }
    }

    func testBusyRejectedHoldReleaseAfterLongPressIsInert() {
        var s = makeSession()
        _ = driveToTranscribing(&s)
        XCTAssertEqual(s.handleKey(down(hotKey, at: 5)), .busyRejected)
        // User keeps holding, then releases 2s later: the voided press must not
        // emit a stop for the live take.
        XCTAssertEqual(s.handleKey(up(hotKey, at: 7)), .none)
    }

    // MARK: - Cancellation + stale completions (the token guard)

    func testEscWhileRecordingDropsLateStartConfirmation() {
        var s = makeSession()
        guard case .startRecording(let stale) = s.handleKey(down(hotKey, at: 0)) else {
            return XCTFail("expected .startRecording")
        }
        XCTAssertEqual(s.handleKey(down(esc, at: 0.05)), .cancelRecording)
        XCTAssertEqual(s.pipelineState, .idle)
        XCTAssertEqual(s.recordingStarted(stale), .none) // must NOT resurrect .recording
        XCTAssertEqual(s.pipelineState, .idle)
    }

    func testEscAfterTapLockStopsTheRecorder() {
        var s = makeSession()
        _ = startTake(&s)
        XCTAssertEqual(s.handleKey(up(hotKey, at: 0.1)), .none) // tap-locked, still recording
        XCTAssertTrue(s.isRecorderLive)
        // Esc must stop the mic, not just abort pipeline work.
        XCTAssertEqual(s.handleKey(down(esc, at: 1)), .cancelRecording)
        XCTAssertFalse(s.isRecorderLive)
    }

    func testEscAfterHoldReleaseBeforeStopConfirmStopsTheRecorder() {
        // mode .idle (press released) but pipeline still .recording (stop not
        // yet confirmed): Esc goes through the post-recording top-check, which
        // must still recognise the recorder as live.
        var s = makeSession()
        let token = startTake(&s)
        XCTAssertEqual(s.handleKey(up(hotKey, at: 1.0)), .stopRecording(token))
        XCTAssertTrue(s.isRecorderLive)
        XCTAssertEqual(s.handleKey(down(esc, at: 1.1)), .cancelRecording)
        XCTAssertFalse(s.isRecorderLive)
    }

    func testEscDuringTranscribingCancelsAndDropsLateTranscript() {
        var s = makeSession()
        let token = driveToTranscribing(&s)
        XCTAssertEqual(s.handleKey(down(esc, at: 3)), .cancelPipelineWork) // recorder is not live
        XCTAssertEqual(s.pipelineState, .idle)
        XCTAssertEqual(s.transcriptReady("late", token: token), .none)
        XCTAssertEqual(s.pipelineState, .idle)
    }

    func testEscDuringRefiningCancelsAndDropsLateCleanup() {
        var s = makeSession(cleanup: true)
        let token = driveToTranscribing(&s)
        XCTAssertEqual(s.transcriptReady("raw", token: token), .beginCleanup("raw", token))
        XCTAssertEqual(s.pipelineState, .refining)
        // Impossible with the old split FSMs: hotkey mode is already idle here.
        XCTAssertEqual(s.handleKey(down(esc, at: 3)), .cancelPipelineWork)
        XCTAssertEqual(s.pipelineState, .idle)
        XCTAssertEqual(s.cleaned("late clean", token: token), .none)
    }

    func testEscDuringInsertingDropsLateInsertConfirmation() {
        var s = makeSession()
        let token = driveToTranscribing(&s)
        XCTAssertEqual(s.transcriptReady("text", token: token), .insert("text", token))
        XCTAssertEqual(s.handleKey(down(esc, at: 4)), .cancelPipelineWork)
        XCTAssertEqual(s.inserted(success: true, token: token), .none)
        XCTAssertEqual(s.pipelineState, .idle)
    }

    func testEscAutorepeatDoesNotCancelProcessing() {
        var s = makeSession()
        let token = driveToTranscribing(&s)
        // Esc held down since before the take: autorepeat must not discard it.
        XCTAssertEqual(s.handleKey(down(esc, at: 3, isRepeat: true)), .none)
        XCTAssertEqual(s.pipelineState, .transcribing)
        XCTAssertEqual(s.transcriptReady("kept", token: token), .insert("kept", token))
    }

    func testDoubleEscAndEscUpAreNoOps() {
        var s = makeSession()
        _ = driveToTranscribing(&s)
        XCTAssertEqual(s.handleKey(down(esc, at: 3)), .cancelPipelineWork)
        XCTAssertEqual(s.handleKey(down(esc, at: 3.1)), .none)
        XCTAssertEqual(s.handleKey(up(esc, at: 3.2)), .none)
    }

    func testFreshTakeAfterCancelWorksNormally() {
        var s = makeSession()
        _ = s.handleKey(down(hotKey, at: 0))
        XCTAssertEqual(s.handleKey(down(esc, at: 0.05)), .cancelRecording)
        let token = startTake(&s, at: 1)
        XCTAssertEqual(s.pipelineState, .recording)
        XCTAssertEqual(s.handleKey(up(hotKey, at: 2)), .stopRecording(token))
        XCTAssertEqual(s.recordingStopped(token), .beginTranscription(token))
        XCTAssertEqual(s.transcriptReady("second", token: token), .insert("second", token))
    }

    func testStaleStopAndFailureCompletionsAreDropped() {
        var s = makeSession()
        guard case .startRecording(let stale) = s.handleKey(down(hotKey, at: 0)) else {
            return XCTFail("expected .startRecording")
        }
        XCTAssertEqual(s.handleKey(down(esc, at: 0.1)), .cancelRecording)
        XCTAssertEqual(s.recordingStopped(stale), .none)
        XCTAssertEqual(s.transcriptionFailed(token: stale), .none)
        XCTAssertEqual(s.cleanupFailed(token: stale), .none)
        XCTAssertEqual(s.pipelineState, .idle)
    }

    // MARK: - Start-failure unwind (the P1-4 fix)

    func testStartFailureDuringHoldVoidsThePress() {
        var s = makeSession()
        guard case .startRecording(let token) = s.handleKey(down(hotKey, at: 0)) else {
            return XCTFail("expected .startRecording")
        }
        XCTAssertEqual(s.recordingFailedToStart(token), .recordingFailedFeedback)
        XCTAssertEqual(s.pipelineState, .idle)
        XCTAssertFalse(s.isRecorderLive)
        XCTAssertEqual(s.handleKey(up(hotKey, at: 1)), .none) // releasing the failed hold: inert
        guard case .startRecording = s.handleKey(down(hotKey, at: 2)) else {
            return XCTFail("next press must start fresh, not be eaten as a stop")
        }
    }

    func testStartFailureAfterTapLockDoesNotTurnNextPressIntoStop() {
        var s = makeSession()
        guard case .startRecording(let token) = s.handleKey(down(hotKey, at: 0)) else {
            return XCTFail("expected .startRecording")
        }
        XCTAssertEqual(s.handleKey(up(hotKey, at: 0.1)), .none) // tap-locked before failure lands
        XCTAssertEqual(s.recordingFailedToStart(token), .recordingFailedFeedback)
        guard case .startRecording = s.handleKey(down(hotKey, at: 1)) else {
            return XCTFail("expected .startRecording")
        }
    }

    func testCompletionsAfterFailedStartAreDropped() {
        var s = makeSession()
        guard case .startRecording(let token) = s.handleKey(down(hotKey, at: 0)) else {
            return XCTFail("expected .startRecording")
        }
        XCTAssertEqual(s.recordingFailedToStart(token), .recordingFailedFeedback)
        // A duplicate/late success callback for the same take must not revive it.
        XCTAssertEqual(s.recordingStarted(token), .none)
        XCTAssertEqual(s.recordingStopped(token), .none)
        XCTAssertEqual(s.pipelineState, .idle)
    }

    // MARK: - Rebinding

    func testRebindWhileRecordingCancelsTheOrphanedTake() {
        var s = makeSession()
        _ = startTake(&s)
        XCTAssertEqual(s.handleKey(up(hotKey, at: 0.1)), .none) // tap-locked: recorder live
        // The old key can no longer stop it and the new key would read as a
        // fresh press — cancel rather than leave the mic hot forever.
        XCTAssertEqual(s.setHotKeyConfig(HotKeyConfig(hotKeyCode: 63)), .cancelRecording)
        XCTAssertEqual(s.pipelineState, .idle)
        XCTAssertFalse(s.isRecorderLive)
        guard case .startRecording = s.handleKey(down(63, at: 2)) else {
            return XCTFail("the new key must work immediately")
        }
    }

    func testRebindBeforeStartConfirmationCancelsTheTake() {
        var s = makeSession()
        _ = s.handleKey(down(hotKey, at: 0)) // start emitted, not yet confirmed
        XCTAssertEqual(s.setHotKeyConfig(HotKeyConfig(hotKeyCode: 63)), .cancelRecording)
        XCTAssertFalse(s.isRecorderLive)
    }

    func testRebindDuringTranscriptionPreservesTheTake() {
        var s = makeSession()
        let token = driveToTranscribing(&s)
        // Post-recording work needs no key: it must not be cancelled.
        XCTAssertEqual(s.setHotKeyConfig(HotKeyConfig(hotKeyCode: 63)), .none)
        XCTAssertEqual(s.transcriptReady("kept", token: token), .insert("kept", token))
        XCTAssertEqual(s.inserted(success: true, token: token), .none)
        XCTAssertEqual(s.handleKey(down(hotKey, at: 9)), .none) // old key is inert
        guard case .startRecording = s.handleKey(down(63, at: 10)) else {
            return XCTFail("expected the new key to start a take")
        }
    }

    func testRebindWhileIdleIsInert() {
        var s = makeSession()
        XCTAssertEqual(s.setHotKeyConfig(HotKeyConfig(hotKeyCode: 63)), .none)
        XCTAssertEqual(s.pipelineState, .idle)
    }

    // MARK: - Guards

    func testEscWhileFullyIdleDoesNothing() {
        var s = makeSession()
        XCTAssertEqual(s.handleKey(down(esc, at: 0)), .none)
        XCTAssertEqual(s.pipelineState, .idle)
    }

    func testMismatchedTokenNeverAdvancesThePipeline() {
        var s = makeSession()
        _ = s.handleKey(down(hotKey, at: 0))
        let forged = DictationSession.Token(value: 999_999)
        XCTAssertEqual(s.recordingStarted(forged), .none)
        XCTAssertEqual(s.pipelineState, .idle)
    }

    func testUnrelatedKeyCodesAreIgnored() {
        var s = makeSession()
        XCTAssertEqual(s.handleKey(down(40, at: 0)), .none)
        XCTAssertEqual(s.handleKey(up(40, at: 0.1)), .none)
        XCTAssertEqual(s.pipelineState, .idle)
    }

    func testCleanupEnabledCanChangeMidSession() {
        var s = makeSession(cleanup: false)
        s.cleanupEnabled = true
        let token = driveToTranscribing(&s)
        XCTAssertEqual(s.transcriptReady("raw", token: token), .beginCleanup("raw", token))
    }
}
