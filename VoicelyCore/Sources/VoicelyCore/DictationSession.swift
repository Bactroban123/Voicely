import Foundation

/// The single source of truth for one dictation take, composing the two
/// existing pure reducers — `HotKeyProcessor` (what the keys mean) and
/// `Pipeline` (what happens to the audio) — which stay untouched and keep
/// their own tests.
///
/// It exists to close the gap between them: previously a hotkey press while a
/// prior take was still transcribing/refining started a real recording whose
/// events the pipeline silently ignored — the new dictation was discarded and
/// the stale one pasted later. The session adds exactly the missing coupling:
///
/// - **Busy-reject:** a press while a take is in flight is voided as if it
///   never happened (`.busyRejected` lets the UI hint why). Deliberately not
///   queued — insertion targets whatever app is focused *at paste time*, so a
///   queued take could paste into the wrong window. Not cancel-and-replace —
///   an accidental double-press must not destroy a finished dictation.
/// - **Token guard:** every async completion carries the `Token` of the take
///   it belongs to, minted when that take began and handed out inside the
///   effect that starts the work. Completions for a cancelled or superseded
///   take compare unequal and are dropped, so late work can never resurrect a
///   dead take or paste into a live one.
/// - **Esc cancels anything:** while recording (via `HotKeyProcessor`) and —
///   new — while transcribing/refining/inserting, which the hotkey FSM alone
///   could never express because its mode is already `.idle` by then.
/// - **Failure unwind:** a recorder that failed to start resets the hotkey FSM
///   so the next press starts fresh instead of being eaten as a phantom stop.
///
/// A take is "in flight" from the moment `.startRecording` is emitted until
/// the pipeline returns to idle — deliberately *not* keyed on
/// `pipeline.state != .idle`, because the pipeline only learns a recording
/// exists once the engine confirms the start. During that window (cold engine:
/// hundreds of ms) a second press would otherwise look legitimate and silently
/// discard the first take.
public struct DictationSession {
    /// Opaque identity of one take. Minted by the session and handed out in
    /// the effect that starts a piece of work; report completions back with
    /// the token you were given, never with `currentToken` read later.
    public struct Token: Equatable {
        let value: Int
    }

    public enum Effect: Equatable {
        case none
        /// Start the recorder; report via `recordingStarted`/`recordingFailedToStart`.
        case startRecording(Token)
        /// Stop the recorder, keep samples; report via `recordingStopped`.
        case stopRecording(Token)
        /// Stop the recorder and discard samples. No report expected.
        case cancelRecording
        /// Abort in-flight transcription/cleanup. The recorder is not running.
        case cancelPipelineWork
        case beginTranscription(Token)
        case beginCleanup(String, Token)
        case insert(String, Token)
        /// A press was voided because a take is still in flight.
        case busyRejected
        /// Recording could not start; surface it (the press was voided).
        case recordingFailedFeedback
    }

    private var config: HotKeyConfig
    private var hotKey: HotKeyProcessor
    private var pipeline: Pipeline
    private var generation = 0
    /// True from `.startRecording` until the pipeline is idle again.
    private var takeInFlight = false

    public private(set) var currentToken = Token(value: 0)

    /// Read at transcript time to decide raw-insert vs cleanup.
    public var cleanupEnabled: Bool {
        get { pipeline.cleanupEnabled }
        set { pipeline.cleanupEnabled = newValue }
    }

    public var pipelineState: Pipeline.State { pipeline.state }

    /// True while the recorder is (or is about to be) capturing — i.e. a take
    /// exists that only a key or a cancel can end.
    public var isRecorderLive: Bool {
        takeInFlight && (pipeline.state == .idle || pipeline.state == .recording)
    }

    public init(config: HotKeyConfig, cleanupEnabled: Bool) {
        self.config = config
        self.hotKey = HotKeyProcessor(config: config)
        self.pipeline = Pipeline(cleanupEnabled: cleanupEnabled)
    }

    /// Swap the hotkey binding. Post-recording work (transcribing/refining/
    /// inserting) is unaffected — it needs no key to finish — but a take whose
    /// recorder is still live is cancelled rather than orphaned: the old key
    /// can no longer stop it and the new key would read as a fresh press.
    public mutating func setHotKeyConfig(_ newConfig: HotKeyConfig) -> Effect {
        config = newConfig
        hotKey = HotKeyProcessor(config: newConfig)
        guard isRecorderLive else { return .none }
        endTake()
        return .cancelRecording
    }

    // MARK: - Key events (synchronous, from the tap callback path)

    public mutating func handleKey(_ event: KeyEvent) -> Effect {
        // Esc while post-recording work is in flight: the hotkey FSM is
        // already idle then, so it can't see this — handle it here.
        if event.keyCode == config.cancelKeyCode, event.phase == .down, !event.isRepeat,
           hotKey.mode == .idle, takeInFlight || pipeline.state != .idle {
            let recorderLive = isRecorderLive
            endTake()
            return recorderLive ? .cancelRecording : .cancelPipelineWork
        }

        guard let output = hotKey.process(event) else { return .none }
        switch output {
        case .startRecording:
            guard !takeInFlight, pipeline.state == .idle else {
                voidCurrentPress()
                return .busyRejected
            }
            invalidateToken()
            takeInFlight = true
            return .startRecording(currentToken)

        case .stopRecording:
            return .stopRecording(currentToken)

        case .cancel:
            endTake()
            return .cancelRecording
        }
    }

    // MARK: - Async confirmations (token-guarded)

    public mutating func recordingStarted(_ token: Token) -> Effect {
        guard token == currentToken, takeInFlight else { return .none }
        return applyPipeline(.startedRecording)
    }

    public mutating func recordingFailedToStart(_ token: Token) -> Effect {
        guard token == currentToken, takeInFlight else { return .none }
        // This is the one completion that doesn't route through Pipeline (a
        // failed start means the pipeline never left .idle, so there's nothing
        // to unwind there — only the hotkey FSM, or the next press becomes a
        // phantom stop). That makes the .idle precondition ours to enforce:
        // without this guard, a failure delivered AFTER a success for the same
        // take would strand the pipeline in .recording while clearing
        // takeInFlight, and every press would busy-reject until Esc.
        guard pipeline.state == .idle else { return .none }
        // Invalidate too, so a duplicate late `started` can't revive the take.
        invalidateToken()
        takeInFlight = false
        voidCurrentPress()
        return .recordingFailedFeedback
    }

    public mutating func recordingStopped(_ token: Token) -> Effect {
        guard token == currentToken, takeInFlight else { return .none }
        return applyPipeline(.stoppedRecording)
    }

    public mutating func transcriptReady(_ text: String, token: Token) -> Effect {
        guard token == currentToken else { return .none }
        return applyPipeline(.transcript(text))
    }

    public mutating func transcriptionFailed(token: Token) -> Effect {
        guard token == currentToken else { return .none }
        return applyPipeline(.transcriptionFailed)
    }

    public mutating func cleaned(_ text: String, token: Token) -> Effect {
        guard token == currentToken else { return .none }
        return applyPipeline(.cleaned(text))
    }

    public mutating func cleanupFailed(token: Token) -> Effect {
        guard token == currentToken else { return .none }
        return applyPipeline(.cleanupFailed)
    }

    public mutating func inserted(success: Bool, token: Token) -> Effect {
        guard token == currentToken else { return .none }
        return applyPipeline(success ? .inserted : .insertionFailed)
    }

    // MARK: - Internals

    private mutating func invalidateToken() {
        generation += 1
        currentToken = Token(value: generation)
    }

    /// Abandon the current take: no completion for it can be accepted again,
    /// the pipeline returns to idle, and the physical press is voided.
    private mutating func endTake() {
        invalidateToken()
        _ = pipeline.handle(.cancelled)
        takeInFlight = false
        voidCurrentPress()
    }

    /// Treat the in-flight physical press as if it never happened: a fresh
    /// hotkey FSM ignores the eventual key-up (or the next press of a
    /// tap-locked key) instead of emitting a bogus stop.
    private mutating func voidCurrentPress() {
        hotKey = HotKeyProcessor(config: config)
    }

    private mutating func applyPipeline(_ event: Pipeline.Event) -> Effect {
        let effect = pipeline.handle(event)
        if pipeline.state == .idle { takeInFlight = false }
        return map(effect)
    }

    private func map(_ effect: Pipeline.Effect) -> Effect {
        switch effect {
        case .none: return .none
        case .beginTranscription: return .beginTranscription(currentToken)
        case .beginCleanup(let raw): return .beginCleanup(raw, currentToken)
        case .insert(let text): return .insert(text, currentToken)
        }
    }
}
