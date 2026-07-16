import Foundation

/// What to do with a meeting found on disk at launch.
///
/// A meeting is an hour of someone's day and cannot be re-recorded, so the
/// rules here are asymmetric on purpose: when in doubt, offer the audio back
/// rather than tidy it away. The one thing that must never happen is a meeting
/// quietly disappearing because the app crashed while writing it.
public enum MeetingRecovery {
    public enum Action: Equatable {
        /// Nothing to do — it finished.
        case none
        /// Recording never finished (the app died mid-call), but chunks are on
        /// disk. Offer to transcribe them or discard.
        case offerInterrupted
        /// Audio is on disk and un-transcribed. Resume where it left off.
        case resumeTranscription
        /// A stage failed but the input survived — retry is possible.
        case offerRetry
        /// Nothing usable is left. Only worth offering to clear it away.
        case offerCleanup
    }

    public static func action(for meeting: Meeting) -> Action {
        switch meeting.status {
        case .complete:
            return .none

        case .recording:
            // The app died mid-call. Chunks are only listed in the header once
            // they're closed, so whatever's there is valid audio — but the
            // header may also predate any chunk at all (we write it before
            // recording starts precisely so this case is findable).
            return meeting.canTranscribe ? .offerInterrupted : .offerCleanup

        case .recorded:
            return meeting.canTranscribe ? .resumeTranscription : .offerCleanup

        case .transcribing:
            // Died mid-transcription. The audio is still there, so just do it
            // again — transcription is idempotent and costs minutes, not an
            // hour of someone's day.
            return meeting.canTranscribe ? .resumeTranscription : .offerCleanup

        case .transcribed, .summarizing:
            // The transcript is saved; only the notes are missing. Retry needs
            // no audio, so this is cheap and safe.
            return .offerRetry

        case .failed:
            if meeting.canTranscribe { return .offerRetry }
            // A summarization failure leaves no audio (it's deleted once the
            // transcript exists) but the transcript is what matters.
            return .offerRetry
        }
    }

    /// Meetings worth telling the user about at launch, newest first.
    /// `.none` and `.offerCleanup` are deliberately excluded: a finished
    /// meeting needs no prompt, and nagging about an empty husk on every launch
    /// trains people to dismiss the dialog that actually matters.
    public static func needingAttention(_ meetings: [Meeting]) -> [Meeting] {
        meetings.filter {
            switch action(for: $0) {
            case .offerInterrupted, .resumeTranscription, .offerRetry: return true
            case .none, .offerCleanup: return false
            }
        }
    }

    /// Husks worth deleting silently: no audio, no transcript, nothing to show.
    /// Only ever an empty folder from a start that failed immediately.
    public static func isDisposable(_ meeting: Meeting) -> Bool {
        action(for: meeting) == .offerCleanup
    }
}

/// Whether there's room to record.
///
/// Meetings are the only feature that writes hundreds of MB, and running the
/// disk dry mid-call would fail the recording AND whatever else the user is
/// doing. Better to refuse up front, when it's still just a menu click.
public enum DiskGuard: Equatable {
    /// ~230 MB/hour across both tracks at 16kHz mono Int16.
    public static let bytesPerHour: Int64 = 230 * 1_024 * 1_024
    /// Refuse below this: roughly four hours of headroom, plus room for the
    /// system to breathe.
    public static let minimumFreeBytes: Int64 = 1_024 * 1_024 * 1_024

    public enum Verdict: Equatable {
        case ok
        /// Enough to start, but say how long it can last.
        case tight(hoursRemaining: Double)
        case refuse(freeBytes: Int64)
    }

    public static func check(freeBytes: Int64) -> Verdict {
        guard freeBytes >= minimumFreeBytes else { return .refuse(freeBytes: freeBytes) }
        let hours = Double(freeBytes - minimumFreeBytes) / Double(bytesPerHour)
        return hours < 2 ? .tight(hoursRemaining: hours) : .ok
    }

    /// Human-readable size, for the retention UI and the refusal message.
    public static func format(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}
