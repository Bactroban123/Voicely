import AppKit
import VoicelyCore

/// Orchestrates the dictation loop by driving the tested
/// VoicelyCore.DictationSession reducer: hotkey → record → transcribe →
/// (cleanup) → insert. The session is the single source of truth — it couples
/// the hotkey FSM and the pipeline (busy-reject, Esc-cancel anywhere) and
/// token-guards every async completion so stale work can never paste.
/// Cleanup failures fall back to the raw transcript (never lose it).
final class RecordingController {
    enum UIState { case idle, recording, processing }

    private(set) var state: UIState = .idle {
        didSet { onStateChange?(state) }
    }
    var onStateChange: ((UIState) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onTranscript: ((String) -> Void)?
    /// Transient user-facing hints ("still finishing…", "couldn't start").
    var onNotice: ((String) -> Void)?

    private let settings = SettingsStore.shared
    private var session = DictationSession(config: HotKeyConfig(hotKeyCode: 61),
                                           cleanupEnabled: false)
    private var pendingSamples: [Float] = []

    private let recorder = AudioRecorder()
    private var engine: TranscriptionEngine = ParakeetEngine(version: .v2)
    private let inserter = TextInserter()
    private let cleanup = CleanupService()
    private lazy var monitor = KeyEventMonitor { [weak self] event in
        self?.handle(event) // CGEventTap callbacks fire on the main run loop
    }

    /// Returns false if the event tap couldn't start (Input Monitoring not granted).
    func start() -> Bool {
        recorder.onLevel = { [weak self] level in self?.onLevel?(level) }
        recorder.prewarm()
        reconfigure()
        NotificationCenter.default.addObserver(forName: .voicelySettingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.reconfigure()
        }
        return monitor.start()
    }

    /// Re-read settings: hotkey and the selected on-device engine.
    private func reconfigure() {
        // Only rebuild the hotkey FSM when the binding actually changed —
        // rebuilding voids any in-progress press, so an unrelated settings
        // change (e.g. a cleanup-mode click) must not orphan a live take.
        let config = HotKeyConfig(hotKeyCode: UInt16(settings.hotKeyCode))
        if config != currentHotKeyConfig {
            currentHotKeyConfig = config
            apply(session.setHotKeyConfig(config)) // cancels a take the old key can no longer stop
        }
        engine = Self.makeEngine(for: settings.transcriptionModelID)
        Task { [engine] in try? await engine.prepare() } // warm-load
    }

    private var currentHotKeyConfig: HotKeyConfig?

    private static func makeEngine(for modelID: String) -> TranscriptionEngine {
        switch modelID {
        case "whisper-large-v3-turbo":
            return WhisperKitEngine()        // multilingual incl. Hebrew
        case "parakeet-multi":
            return ParakeetEngine(version: .v3)
        default:
            return ParakeetEngine(version: .v2) // parakeet-en is the default
        }
    }

    // MARK: - Hotkey

    /// Runs on the main run loop from inside the CGEventTap callback: only the
    /// (cheap, timestamp-sensitive) session reducer runs synchronously here.
    /// All recorder I/O is enqueued on the recorder's serial queue; each
    /// completion reports back to the session with the token of the take it
    /// belongs to, so completions for cancelled/superseded takes are dropped.
    private func handle(_ event: KeyEvent) {
        apply(session.handleKey(event))
    }

    // MARK: - Session effects

    private func apply(_ effect: DictationSession.Effect) {
        syncState()
        switch effect {
        case .none:
            break

        case .startRecording(let token):
            session.cleanupEnabled = settings.cleanupEnabled
            recorder.start { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch result {
                    case .success(let ms):
                        VoicelyLog.recording.info("recording started in \(ms)ms")
                        self.apply(self.session.recordingStarted(token))
                    case .failure(let error):
                        VoicelyLog.recording.error("failed to start recording — \(error)")
                        self.apply(self.session.recordingFailedToStart(token))
                    }
                }
            }

        case .stopRecording(let token):
            recorder.stop { [weak self] samples in
                DispatchQueue.main.async {
                    guard let self else { return }
                    let effect = self.session.recordingStopped(token)
                    if effect != .none {
                        // Keep audio only for a live take; a token-dropped
                        // (cancelled) stop must not linger in memory.
                        self.pendingSamples = samples
                    }
                    self.apply(effect)
                }
            }

        case .cancelRecording:
            recorder.stop { _ in } // discard; the session already reset to idle

        case .cancelPipelineWork:
            // The session guarantees the recorder isn't live here. Token
            // invalidation already makes any late result a no-op; actual Task
            // cancellation of the network call lands with the cleanup-timeout
            // slice. Nothing pastes either way.
            VoicelyLog.recording.info("dictation cancelled while processing — late results will be dropped")

        case .beginTranscription(let token):
            runTranscription(token: token)

        case .beginCleanup(let raw, let token):
            runCleanup(raw, token: token)

        case .insert(let text, let token):
            performInsert(text, token: token)

        case .busyRejected:
            onNotice?("Still finishing your last dictation…")

        case .recordingFailedFeedback:
            onNotice?("Couldn't start recording")
        }
    }

    private func syncState() {
        let newState: UIState
        switch session.pipelineState {
        case .idle: newState = .idle
        case .recording: newState = .recording
        case .transcribing, .refining, .inserting: newState = .processing
        }
        // Publish only real changes: `didSet` fires on same-value writes, and a
        // stale token-dropped completion must not stomp an active HUD flash.
        if newState != state { state = newState }
    }

    private func runTranscription(token: DictationSession.Token) {
        let samples = pendingSamples
        Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await self.engine.transcribe(samples)
                let expanded = SnippetExpander.expand(text, snippets: SnippetStore.shared.snippets)
                await MainActor.run {
                    if expanded.isEmpty {
                        self.apply(self.session.transcriptionFailed(token: token))
                    } else {
                        self.apply(self.session.transcriptReady(expanded, token: token))
                    }
                }
            } catch {
                VoicelyLog.recording.error("transcribe error — \(error)")
                await MainActor.run { self.apply(self.session.transcriptionFailed(token: token)) }
            }
        }
    }

    private func runCleanup(_ raw: String, token: DictationSession.Token) {
        let modelID = settings.cleanupModelID
        let modeID = settings.cleanupModeID
        // Effective vocabulary = your manual list + what Voicely has auto-learned.
        var vocabulary = VocabularyStore.shared.entries
        if settings.autoLearnEnabled {
            vocabulary += AutoLearnStore.shared.learnedEntries
        }
        let zeroRetention = settings.zeroRetention
        Task { [weak self] in
            guard let self else { return }
            do {
                let cleaned = try await self.cleanup.clean(raw,
                                                           modelID: modelID,
                                                           modeID: modeID,
                                                           vocabulary: vocabulary,
                                                           zeroRetention: zeroRetention)
                await MainActor.run { self.apply(self.session.cleaned(cleaned, token: token)) }
            } catch {
                VoicelyLog.cleanup.warning("cleanup failed, inserting raw — \(error)")
                await MainActor.run { self.apply(self.session.cleanupFailed(token: token)) }
            }
        }
    }

    private func performInsert(_ text: String, token: DictationSession.Token) {
        if !text.isEmpty {
            inserter.insert(text)
            HistoryStore.shared.record(text)
            if settings.autoLearnEnabled {
                // Learn recurring proper nouns from history so cleanup spells them
                // right. Snapshot on the main thread, do the work off it.
                let history = HistoryStore.shared.entries.map(\.text)
                let manual = VocabularyStore.shared.entries
                Task.detached(priority: .utility) {
                    AutoLearnStore.shared.refreshVocabulary(history: history, manual: manual)
                }
            }
            onTranscript?(text)
            // Metadata only — transcript content never goes to the log.
            VoicelyLog.insertion.info("inserted \(text.count) chars")
        }
        apply(session.inserted(success: true, token: token))
    }
}
