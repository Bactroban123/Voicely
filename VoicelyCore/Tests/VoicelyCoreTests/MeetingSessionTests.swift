import XCTest
@testable import VoicelyCore

final class MeetingSessionTests: XCTestCase {
    /// Drives a session to `.summarizing`, returning its token.
    @discardableResult
    private func driveToSummarizing(_ s: inout MeetingSession) -> MeetingSession.Token {
        guard case .beginRecording(let token) = s.handle(.start) else {
            XCTFail("expected .beginRecording"); return MeetingSession.Token(value: -1)
        }
        XCTAssertEqual(s.handle(.stop), .finalizeRecording(token))
        XCTAssertEqual(s.handle(.recordingFinalized(hasAudio: true)), .beginTranscription(token))
        XCTAssertEqual(s.handle(.transcriptReady), .beginSummarization(token))
        return token
    }

    // MARK: - Happy path

    func testAMeetingRunsRecordToNotes() {
        var s = MeetingSession()
        let token = driveToSummarizing(&s)
        XCTAssertEqual(s.handle(.summaryReady), .notifyComplete)
        XCTAssertEqual(s.state, .complete)
        XCTAssertTrue(s.isCurrent(token))
    }

    func testPauseAndResume() {
        var s = MeetingSession()
        _ = s.handle(.start)
        XCTAssertEqual(s.handle(.pause), .pauseRecording)
        XCTAssertEqual(s.state, .recording(paused: true))
        XCTAssertEqual(s.handle(.resume), .resumeRecording)
        XCTAssertEqual(s.state, .recording(paused: false))
        XCTAssertTrue(s.isRecording)
    }

    func testProgressIsReportedAndClamped() {
        var s = MeetingSession()
        _ = s.handle(.start); _ = s.handle(.stop); _ = s.handle(.recordingFinalized(hasAudio: true))
        XCTAssertEqual(s.handle(.transcriptionProgress(0.5)), .none)
        XCTAssertEqual(s.state, .transcribing(progress: 0.5))
        _ = s.handle(.transcriptionProgress(1.7))
        XCTAssertEqual(s.state, .transcribing(progress: 1))
        _ = s.handle(.transcriptionProgress(-3))
        XCTAssertEqual(s.state, .transcribing(progress: 0))
    }

    /// Found by fuzzing: min/max don't sanitise NaN (it fails every comparison,
    /// so both pass it through). A 0/0 progress report would poison the
    /// progress bar and every `%` format downstream.
    func testNonFiniteProgressCannotPoisonTheState() {
        var s = MeetingSession()
        _ = s.handle(.start); _ = s.handle(.stop); _ = s.handle(.recordingFinalized(hasAudio: true))
        for bad in [Double.nan, .infinity, -.infinity, .signalingNaN] {
            _ = s.handle(.transcriptionProgress(bad))
            guard case .transcribing(let progress) = s.state else { return XCTFail("left .transcribing") }
            XCTAssertFalse(progress.isNaN, "NaN leaked into the state")
            XCTAssertTrue((0...1).contains(progress))
        }
    }

    // MARK: - Nothing is lost

    func testASummarizationFailureKeepsTheTranscript() {
        // Notes are a nice-to-have; the transcript IS the meeting.
        var s = MeetingSession()
        driveToSummarizing(&s)
        XCTAssertEqual(s.handle(.summarizationFailed("model refused")), .notifyComplete)
        XCTAssertEqual(s.state, .failed(.summarization, reason: "model refused"))
        XCTAssertTrue(s.hasTranscript)
        XCTAssertTrue(s.canRetry, "the transcript is on disk, so the summary can be retried")
    }

    func testRetryingASummaryDoesNotRetranscribeAnHourOfAudio() {
        var s = MeetingSession()
        let token = driveToSummarizing(&s)
        _ = s.handle(.summarizationFailed("timeout"))
        XCTAssertEqual(s.handle(.retry), .beginSummarization(token))
        XCTAssertEqual(s.state, .summarizing)
    }

    func testATranscriptionFailureKeepsTheAudio() {
        var s = MeetingSession()
        guard case .beginRecording(let token) = s.handle(.start) else { return XCTFail() }
        _ = s.handle(.stop)
        _ = s.handle(.recordingFinalized(hasAudio: true))
        XCTAssertEqual(s.handle(.transcriptionFailed("model crashed")), .none)
        XCTAssertEqual(s.state, .failed(.transcription, reason: "model crashed"))
        XCTAssertTrue(s.hasAudio)
        XCTAssertTrue(s.canRetry)
        XCTAssertEqual(s.handle(.retry), .beginTranscription(token), "retry from the audio, no re-recording")
    }

    func testAFailedTranscriptionThenSuccessfulRetryCompletes() {
        var s = MeetingSession()
        _ = s.handle(.start); _ = s.handle(.stop); _ = s.handle(.recordingFinalized(hasAudio: true))
        _ = s.handle(.transcriptionFailed("transient"))
        _ = s.handle(.retry)
        XCTAssertEqual(s.handle(.transcriptReady), .beginSummarization(s.currentToken))
        XCTAssertEqual(s.handle(.summaryReady), .notifyComplete)
        XCTAssertEqual(s.state, .complete)
    }

    func testAMeetingThatCapturedNothingSaysSoRatherThanLookingEmpty() {
        var s = MeetingSession()
        _ = s.handle(.start)
        _ = s.handle(.stop)
        XCTAssertEqual(s.handle(.recordingFinalized(hasAudio: false)), .none)
        XCTAssertEqual(s.state, .failed(.transcription, reason: "no audio was recorded"))
        XCTAssertFalse(s.canRetry, "there's nothing to retry from")
    }

    func testRetryWithNothingOnDiskIsRejectedNotSilentlyAccepted() {
        var s = MeetingSession()
        _ = s.handle(.start); _ = s.handle(.stop); _ = s.handle(.recordingFinalized(hasAudio: false))
        XCTAssertEqual(s.handle(.retry), .rejected(reason: "there's nothing left on disk to retry from"))
    }

    // MARK: - Concurrency guards

    func testStartingASecondMeetingIsRejected() {
        var s = MeetingSession()
        _ = s.handle(.start)
        XCTAssertEqual(s.handle(.start), .rejected(reason: "a meeting is already in progress"))
        XCTAssertEqual(s.state, .recording(paused: false))
    }

    /// Also found by fuzzing: `.start` from `.complete` used to fall through to
    /// `.none`, so the menu item did nothing after every finished meeting.
    func testStartingAfterAFinishedMeetingBeginsTheNextOne() {
        var s = MeetingSession()
        driveToSummarizing(&s)
        _ = s.handle(.summaryReady)
        XCTAssertEqual(s.state, .complete)
        guard case .beginRecording(let token) = s.handle(.start) else {
            return XCTFail("the finished meeting is already saved — the next one should just start")
        }
        XCTAssertEqual(s.state, .recording(paused: false))
        XCTAssertTrue(s.isCurrent(token))
        XCTAssertFalse(s.hasTranscript, "the new meeting starts clean")
    }

    func testStartingOverAFailedMeetingIsRefusedSoItsAudioIsNotAbandoned() {
        var s = MeetingSession()
        _ = s.handle(.start); _ = s.handle(.stop); _ = s.handle(.recordingFinalized(hasAudio: true))
        _ = s.handle(.transcriptionFailed("model crashed"))
        XCTAssertEqual(s.handle(.start), .rejected(reason: "retry or discard the unfinished meeting first"))
        XCTAssertTrue(s.hasAudio, "an hour of audio must not be silently abandoned")
        // Discarding is the explicit way out.
        _ = s.handle(.discard)
        guard case .beginRecording = s.handle(.start) else { return XCTFail("discard should free it up") }
    }

    func testStartingOverAnUnrecoverableFailureIsRefusedWithAnHonestReason() {
        var s = MeetingSession()
        _ = s.handle(.start); _ = s.handle(.stop); _ = s.handle(.recordingFinalized(hasAudio: false))
        XCTAssertEqual(s.handle(.start), .rejected(reason: "discard the failed meeting first"))
    }

    func testStartingWhileTranscribingIsRejected() {
        var s = MeetingSession()
        _ = s.handle(.start); _ = s.handle(.stop); _ = s.handle(.recordingFinalized(hasAudio: true))
        XCTAssertEqual(s.handle(.start), .rejected(reason: "a meeting is already in progress"))
    }

    func testStaleTokensAreRejected() {
        var s = MeetingSession()
        guard case .beginRecording(let first) = s.handle(.start) else { return XCTFail() }
        _ = s.handle(.discard)
        _ = s.handle(.start)
        XCTAssertFalse(s.isCurrent(first), "a discarded meeting's results must never apply to the next one")
        XCTAssertTrue(s.isCurrent(s.currentToken))
    }

    // MARK: - Discard

    func testDiscardWhileRecordingStopsAndCleansUp() {
        var s = MeetingSession()
        guard case .beginRecording(let token) = s.handle(.start) else { return XCTFail() }
        XCTAssertEqual(s.handle(.discard), .discard(token))
        XCTAssertEqual(s.state, .idle)
        XCTAssertFalse(s.hasAudio)
    }

    func testDiscardAfterCompletion() {
        var s = MeetingSession()
        driveToSummarizing(&s)
        _ = s.handle(.summaryReady)
        guard case .discard = s.handle(.discard) else { return XCTFail("expected a discard effect") }
        XCTAssertEqual(s.state, .idle)
        XCTAssertFalse(s.hasTranscript)
    }

    func testDiscardWhenIdleIsANoOp() {
        var s = MeetingSession()
        XCTAssertEqual(s.handle(.discard), .none)
        XCTAssertEqual(s.state, .idle)
    }

    func testAFreshMeetingAfterDiscardWorks() {
        var s = MeetingSession()
        _ = s.handle(.start)
        _ = s.handle(.discard)
        guard case .beginRecording = s.handle(.start) else { return XCTFail("discard must not poison the session") }
        XCTAssertEqual(s.state, .recording(paused: false))
    }

    // MARK: - Adopting a meeting off disk (crash recovery / retry)

    func testAdoptingAnInterruptedRecordingResumesAtTranscription() {
        var s = MeetingSession()
        guard case .beginTranscription(let token) = s.adopt(hasAudio: true, hasTranscript: false) else {
            return XCTFail("audio on disk should resume at transcription")
        }
        XCTAssertEqual(s.state, .transcribing(progress: 0))
        XCTAssertTrue(s.isCurrent(token))
        XCTAssertTrue(s.hasAudio)
    }

    func testAdoptingATranscriptSkipsStraightToTheNotes() {
        // The audio is already spent — re-transcribing an hour to redo a
        // summary would be the most expensive possible way to be wrong.
        var s = MeetingSession()
        guard case .beginSummarization = s.adopt(hasAudio: false, hasTranscript: true) else {
            return XCTFail("a transcript on disk should resume at summarization")
        }
        XCTAssertEqual(s.state, .summarizing)
        XCTAssertTrue(s.hasTranscript)
    }

    func testATranscriptWinsOverAudioWhenBothExist() {
        var s = MeetingSession()
        guard case .beginSummarization = s.adopt(hasAudio: true, hasTranscript: true) else {
            return XCTFail("never re-transcribe when a transcript already exists")
        }
    }

    func testAdoptingNothingIsRejectedAndLeavesTheSessionClean() {
        var s = MeetingSession()
        XCTAssertEqual(s.adopt(hasAudio: false, hasTranscript: false),
                       .rejected(reason: "there's nothing on disk to resume"))
        XCTAssertEqual(s.state, .idle)
        XCTAssertFalse(s.hasAudio)
        XCTAssertFalse(s.hasTranscript)
    }

    func testAdoptingIsRefusedWhileAMeetingIsInProgress() {
        var s = MeetingSession()
        _ = s.handle(.start)
        XCTAssertEqual(s.adopt(hasAudio: true, hasTranscript: false),
                       .rejected(reason: "finish the meeting in progress first"))
        XCTAssertEqual(s.state, .recording(paused: false), "the live meeting must be untouched")
    }

    func testAnAdoptedMeetingsResultsAreTokenGuardedLikeAnyOther() {
        var s = MeetingSession()
        guard case .beginTranscription(let adopted) = s.adopt(hasAudio: true, hasTranscript: false) else {
            return XCTFail()
        }
        _ = s.handle(.discard)
        XCTAssertFalse(s.isCurrent(adopted), "a discarded recovery's results must not apply to the next meeting")
        XCTAssertEqual(s.handle(.transcriptReady), .none)
    }

    func testAnAdoptedMeetingRunsThroughToComplete() {
        var s = MeetingSession()
        _ = s.adopt(hasAudio: true, hasTranscript: false)
        XCTAssertEqual(s.handle(.transcriptReady), .beginSummarization(s.currentToken))
        XCTAssertEqual(s.handle(.summaryReady), .notifyComplete)
        XCTAssertEqual(s.state, .complete)
    }

    // MARK: - Out-of-order events

    func testEventsThatDoNotApplyAreIgnored() {
        var s = MeetingSession()
        XCTAssertEqual(s.handle(.stop), .none)
        XCTAssertEqual(s.handle(.pause), .none)
        XCTAssertEqual(s.handle(.transcriptReady), .none)
        XCTAssertEqual(s.handle(.summaryReady), .none)
        XCTAssertEqual(s.state, .idle)
    }

    func testDoublePauseAndResumeOutOfOrder() {
        var s = MeetingSession()
        _ = s.handle(.start)
        XCTAssertEqual(s.handle(.resume), .none, "already running")
        _ = s.handle(.pause)
        XCTAssertEqual(s.handle(.pause), .none, "already paused")
        XCTAssertEqual(s.state, .recording(paused: true))
    }

    func testALateTranscriptAfterDiscardDoesNotResurrectTheMeeting() {
        var s = MeetingSession()
        _ = s.handle(.start); _ = s.handle(.stop); _ = s.handle(.recordingFinalized(hasAudio: true))
        _ = s.handle(.discard)
        XCTAssertEqual(s.handle(.transcriptReady), .none)
        XCTAssertEqual(s.state, .idle)
    }
}
