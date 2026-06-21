import Foundation

/// The app-level pipeline: what happens after the hotkey starts/stops a recording.
/// idle → recording → transcribing → (refining?) → inserting → idle.
///
/// This is a pure reducer: `handle(_:)` mutates state and returns the side effect
/// the coordinator should perform. It encodes two important spec rules:
/// - cleanup can be skipped (insert the raw transcript directly), and
/// - if cleanup fails, we still insert the raw transcript (never lose it).
public struct Pipeline {
    public enum State: Equatable { case idle, recording, transcribing, refining, inserting }

    public enum Event: Equatable {
        case startedRecording
        case stoppedRecording
        case transcript(String)
        case cleaned(String)
        case cleanupFailed
        case transcriptionFailed
        case inserted
        case insertionFailed
        case cancelled
    }

    public enum Effect: Equatable {
        case none
        case beginTranscription
        case beginCleanup(String)
        case insert(String)
    }

    public private(set) var state: State = .idle
    public private(set) var pendingText: String?
    public var cleanupEnabled: Bool

    public init(cleanupEnabled: Bool) { self.cleanupEnabled = cleanupEnabled }

    public mutating func handle(_ event: Event) -> Effect {
        // Cancel is valid from any active state and always returns to idle.
        if case .cancelled = event {
            state = .idle
            pendingText = nil
            return .none
        }

        switch (state, event) {
        case (.idle, .startedRecording):
            state = .recording
            return .none

        case (.recording, .stoppedRecording):
            state = .transcribing
            return .beginTranscription

        case (.transcribing, .transcript(let raw)):
            pendingText = raw
            if cleanupEnabled {
                state = .refining
                return .beginCleanup(raw)
            }
            state = .inserting
            return .insert(raw)

        case (.transcribing, .transcriptionFailed):
            state = .idle
            pendingText = nil
            return .none

        case (.refining, .cleaned(let clean)):
            pendingText = clean
            state = .inserting
            return .insert(clean)

        case (.refining, .cleanupFailed):
            // Graceful fallback: insert the raw transcript we kept.
            let raw = pendingText ?? ""
            state = .inserting
            return .insert(raw)

        case (.inserting, .inserted), (.inserting, .insertionFailed):
            state = .idle
            pendingText = nil
            return .none

        default:
            return .none
        }
    }
}
