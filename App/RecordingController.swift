import AppKit
import VoicelyCore

/// Orchestrates the dictation loop, driving side effects from the tested
/// VoicelyCore.Pipeline reducer: hotkey → record → transcribe → (cleanup) → insert.
/// Cleanup failures fall back to the raw transcript (never lose it).
final class RecordingController {
    enum UIState { case idle, recording, processing }

    private(set) var state: UIState = .idle {
        didSet { onStateChange?(state) }
    }
    var onStateChange: ((UIState) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onTranscript: ((String) -> Void)?

    private let settings = SettingsStore.shared
    private var hotKey = HotKeyProcessor(config: HotKeyConfig(hotKeyCode: 61))
    private var pipeline = Pipeline(cleanupEnabled: false)
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
        reconfigure()
        NotificationCenter.default.addObserver(forName: .voicelySettingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.reconfigure()
        }
        return monitor.start()
    }

    /// Re-read settings: hotkey and the selected on-device engine.
    private func reconfigure() {
        hotKey = HotKeyProcessor(config: HotKeyConfig(hotKeyCode: UInt16(settings.hotKeyCode)))
        engine = Self.makeEngine(for: settings.transcriptionModelID)
        Task { [engine] in try? await engine.prepare() } // warm-load
    }

    private static func makeEngine(for modelID: String) -> TranscriptionEngine {
        switch modelID {
        case "whisper-large-v3-turbo":
            return WhisperKitEngine()        // multilingual incl. Hebrew
        case "parakeet-multi":
            return ParakeetEngine(version: .v3)
        default:
            // parakeet-en is the default; Apple Speech engine lands next.
            return ParakeetEngine(version: .v2)
        }
    }

    // MARK: - Hotkey

    private func handle(_ event: KeyEvent) {
        guard let output = hotKey.process(event) else { return }
        switch output {
        case .startRecording:
            pipeline.cleanupEnabled = settings.cleanupEnabled
            do {
                try recorder.start()
                apply(pipeline.handle(.startedRecording))
            } catch {
                NSLog("Voicely: failed to start recording — \(error)")
            }
        case .stopRecording:
            pendingSamples = recorder.stop()
            apply(pipeline.handle(.stoppedRecording))
        case .cancel:
            recorder.stop()
            apply(pipeline.handle(.cancelled))
        }
    }

    // MARK: - Pipeline effects

    private func apply(_ effect: Pipeline.Effect) {
        syncState()
        switch effect {
        case .none:
            break
        case .beginTranscription:
            runTranscription()
        case .beginCleanup(let raw):
            runCleanup(raw)
        case .insert(let text):
            performInsert(text)
        }
    }

    private func syncState() {
        switch pipeline.state {
        case .idle: state = .idle
        case .recording: state = .recording
        case .transcribing, .refining, .inserting: state = .processing
        }
    }

    private func runTranscription() {
        let samples = pendingSamples
        Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await self.engine.transcribe(samples)
                let expanded = SnippetExpander.expand(text, snippets: SnippetStore.shared.snippets)
                await MainActor.run {
                    if expanded.isEmpty {
                        self.apply(self.pipeline.handle(.transcriptionFailed))
                    } else {
                        self.apply(self.pipeline.handle(.transcript(expanded)))
                    }
                }
            } catch {
                NSLog("Voicely: transcribe error — \(error)")
                await MainActor.run { self.apply(self.pipeline.handle(.transcriptionFailed)) }
            }
        }
    }

    private func runCleanup(_ raw: String) {
        let modelID = settings.cleanupModelID
        let modeID = settings.cleanupModeID
        let vocabulary = VocabularyStore.shared.entries
        let zeroRetention = settings.zeroRetention
        Task { [weak self] in
            guard let self else { return }
            do {
                let cleaned = try await self.cleanup.clean(raw,
                                                           modelID: modelID,
                                                           modeID: modeID,
                                                           vocabulary: vocabulary,
                                                           zeroRetention: zeroRetention)
                await MainActor.run { self.apply(self.pipeline.handle(.cleaned(cleaned))) }
            } catch {
                NSLog("Voicely: cleanup failed, inserting raw — \(error)")
                await MainActor.run { self.apply(self.pipeline.handle(.cleanupFailed)) }
            }
        }
    }

    private func performInsert(_ text: String) {
        if !text.isEmpty {
            inserter.insert(text)
            HistoryStore.shared.record(text)
            onTranscript?(text)
            NSLog("Voicely inserted: %@", text)
        }
        apply(pipeline.handle(.inserted))
    }
}
