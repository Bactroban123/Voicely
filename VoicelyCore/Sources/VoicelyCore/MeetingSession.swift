import Foundation

/// The state of one meeting, from "record" to "notes ready".
///
/// A pure reducer, like `DictationSession` — and for the same reason: this is
/// the part where a meeting gets lost. But the failure modes are the opposite
/// way round. A dictation is seconds long and cheap to redo; a meeting is an
/// hour of someone's day that cannot be re-recorded. So every rule here favours
/// keeping what exists over reaching a tidy state:
///
/// - Transcription failing must not discard the audio.
/// - Summarization failing must not discard the transcript — notes are a nice
///   to have, the transcript is the meeting.
/// - Each stage can be retried from what survived, without re-recording.
///
/// Deliberately shares nothing with `DictationSession`: a meeting recording and
/// a dictation can be in flight at once, and coupling them would make each
/// other's bugs contagious.
public struct MeetingSession {
    /// Identity of one meeting. Async work carries it so a result from a
    /// cancelled or superseded meeting can never be applied to another.
    public struct Token: Equatable {
        let value: Int
    }

    public enum Stage: Equatable {
        case transcription
        case summarization
    }

    public enum State: Equatable {
        case idle
        case recording(paused: Bool)
        /// Recording stopped; files are being closed.
        case stopping
        case transcribing(progress: Double)
        case summarizing
        /// Everything succeeded.
        case complete
        /// A stage failed. The work that survived is still on disk, and
        /// `canRetry` says so.
        case failed(Stage, reason: String)
    }

    public enum Effect: Equatable {
        case none
        case beginRecording(Token)
        case pauseRecording
        case resumeRecording
        /// Stop the recorder and hand the chunks to transcription.
        case finalizeRecording(Token)
        case beginTranscription(Token)
        case beginSummarization(Token)
        /// The meeting is done; tell the user (it may have finished long after
        /// they walked away from the call).
        case notifyComplete
        /// Discard this meeting's audio and transcript.
        case discard(Token)
        /// A request that doesn't apply in this state.
        case rejected(reason: String)
    }

    public enum Event: Equatable {
        case start
        case pause
        case resume
        case stop
        case recordingFinalized(hasAudio: Bool)
        case transcriptionProgress(Double)
        case transcriptReady
        case transcriptionFailed(String)
        case summaryReady
        case summarizationFailed(String)
        case retry
        case discard
    }

    private var generation = 0
    public private(set) var currentToken = Token(value: 0)
    public private(set) var state: State = .idle
    /// True once a transcript exists on disk — set by `transcriptReady`, and
    /// deliberately NOT cleared by a summarization failure. It's what makes
    /// "retry the summary" possible without re-transcribing an hour of audio.
    public private(set) var hasTranscript = false
    /// True once audio has been recorded and finalized.
    public private(set) var hasAudio = false

    public init() {}

    /// Whether the current failure can be retried from what's on disk.
    public var canRetry: Bool {
        guard case .failed(let stage, _) = state else { return false }
        switch stage {
        case .transcription: return hasAudio
        case .summarization: return hasTranscript
        }
    }

    /// True while the recorder should be live.
    public var isRecording: Bool {
        if case .recording = state { return true }
        if case .stopping = state { return true }
        return false
    }

    public mutating func handle(_ event: Event) -> Effect {
        switch (state, event) {

        // MARK: Recording
        case (.idle, .start):
            generation += 1
            currentToken = Token(value: generation)
            hasTranscript = false
            hasAudio = false
            state = .recording(paused: false)
            return .beginRecording(currentToken)

        case (.recording(false), .pause):
            state = .recording(paused: true)
            return .pauseRecording

        case (.recording(true), .resume):
            state = .recording(paused: false)
            return .resumeRecording

        case (.recording, .stop):
            state = .stopping
            return .finalizeRecording(currentToken)

        case (.stopping, .recordingFinalized(let hasAudio)):
            self.hasAudio = hasAudio
            guard hasAudio else {
                // Nothing was captured — say so rather than showing an empty
                // meeting that looks like a transcription bug.
                state = .failed(.transcription, reason: "no audio was recorded")
                return .none
            }
            state = .transcribing(progress: 0)
            return .beginTranscription(currentToken)

        // MARK: Transcribing
        case (.transcribing, .transcriptionProgress(let fraction)):
            // isFinite first: NaN fails every comparison, so min/max pass it
            // straight through — a 0/0 progress report would otherwise poison
            // the progress bar and every `%` format downstream.
            state = .transcribing(progress: fraction.isFinite ? min(max(fraction, 0), 1) : 0)
            return .none

        case (.transcribing, .transcriptReady):
            hasTranscript = true
            state = .summarizing
            return .beginSummarization(currentToken)

        case (.transcribing, .transcriptionFailed(let reason)):
            // The audio survives; retry re-transcribes it.
            state = .failed(.transcription, reason: reason)
            return .none

        // MARK: Summarizing
        case (.summarizing, .summaryReady):
            state = .complete
            return .notifyComplete

        case (.summarizing, .summarizationFailed(let reason)):
            // The transcript survives. Notes are a nice-to-have; the meeting
            // itself is already saved.
            state = .failed(.summarization, reason: reason)
            return .notifyComplete

        // MARK: Retry
        case (.failed(.transcription, _), .retry) where hasAudio:
            state = .transcribing(progress: 0)
            return .beginTranscription(currentToken)

        case (.failed(.summarization, _), .retry) where hasTranscript:
            state = .summarizing
            return .beginSummarization(currentToken)

        case (.failed, .retry):
            return .rejected(reason: "there's nothing left on disk to retry from")

        // MARK: Discard
        case (.idle, .discard):
            return .none

        case (.recording, .discard), (.stopping, .discard):
            let token = currentToken
            invalidate()
            state = .idle
            return .discard(token)

        case (_, .discard):
            let token = currentToken
            invalidate()
            state = .idle
            return .discard(token)

        // MARK: Guards
        case (.recording, .start), (.stopping, .start), (.transcribing, .start),
             (.summarizing, .start):
            return .rejected(reason: "a meeting is already in progress")

        case (.complete, .start):
            // The finished meeting is already saved, so there's nothing to
            // lose: just start the next one. Requiring an explicit discard
            // first would make the menu item look dead after every meeting.
            generation += 1
            currentToken = Token(value: generation)
            hasTranscript = false
            hasAudio = false
            state = .recording(paused: false)
            return .beginRecording(currentToken)

        case (.failed, .start):
            // Unlike .complete, a failed meeting still has recoverable audio or
            // a transcript on disk. Starting over would silently abandon an
            // hour of someone's day, so make them choose.
            return .rejected(reason: canRetry
                             ? "retry or discard the unfinished meeting first"
                             : "discard the failed meeting first")

        default:
            return .none
        }
    }

    /// Adopts a meeting that already exists on disk — one the app was part-way
    /// through when it died, or a failed stage the user is retrying.
    ///
    /// A first-class entry point rather than replaying `.start`/`.stop` and
    /// discarding their effects: that trick works, but it silently depends on
    /// the caller dropping exactly the right ones, and would break the moment
    /// anyone touched the reducer. This mints a fresh token, so the recovered
    /// meeting's async results are guarded like any other.
    public mutating func adopt(hasAudio: Bool, hasTranscript: Bool) -> Effect {
        guard case .idle = state else {
            return .rejected(reason: "finish the meeting in progress first")
        }
        generation += 1
        currentToken = Token(value: generation)
        self.hasAudio = hasAudio
        self.hasTranscript = hasTranscript

        // A transcript means the audio is already spent — resume at the notes,
        // never re-transcribe an hour that's already been done.
        if hasTranscript {
            state = .summarizing
            return .beginSummarization(currentToken)
        }
        if hasAudio {
            state = .transcribing(progress: 0)
            return .beginTranscription(currentToken)
        }
        self.hasAudio = false
        self.hasTranscript = false
        return .rejected(reason: "there's nothing on disk to resume")
    }

    /// Async results carry the token of the meeting they belong to; anything
    /// stale compares unequal and is dropped.
    public func isCurrent(_ token: Token) -> Bool { token == currentToken }

    private mutating func invalidate() {
        generation += 1
        currentToken = Token(value: generation)
        hasTranscript = false
        hasAudio = false
    }
}
