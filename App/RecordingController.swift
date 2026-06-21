import AppKit
import VoicelyCore

/// Orchestrates the dictation loop: hotkey → record → transcribe on-device →
/// insert at the cursor. (AI cleanup arrives in Phase 4 via VoicelyCore.Pipeline.)
final class RecordingController {
    enum UIState { case idle, recording, processing }

    private(set) var state: UIState = .idle {
        didSet { onStateChange?(state) }
    }
    var onStateChange: ((UIState) -> Void)?
    var onTranscript: ((String) -> Void)?

    // Default hotkey: Right Option (keyCode 61). User-configurable in a later phase.
    private var processor = HotKeyProcessor(config: HotKeyConfig(hotKeyCode: 61))
    private let recorder = AudioRecorder()
    private let engine: TranscriptionEngine = ParakeetEngine(version: .v2)
    private let inserter = TextInserter()
    private lazy var monitor = KeyEventMonitor { [weak self] event in
        // CGEventTap callbacks fire on the main run loop.
        self?.handle(event)
    }

    /// Returns false if the event tap couldn't start (Input Monitoring not granted).
    func start() -> Bool {
        // Warm-load the model in the background so the first dictation is fast.
        Task { [engine] in try? await engine.prepare() }
        return monitor.start()
    }

    private func handle(_ event: KeyEvent) {
        guard let output = processor.process(event) else { return }
        switch output {
        case .startRecording:
            do {
                try recorder.start()
                state = .recording
            } catch {
                NSLog("Voicely: failed to start recording — \(error)")
            }
        case .stopRecording:
            let samples = recorder.stop()
            transcribeAndInsert(samples)
        case .cancel:
            recorder.stop()
            state = .idle
            NSLog("Voicely: cancelled")
        }
    }

    private func transcribeAndInsert(_ samples: [Float]) {
        state = .processing
        Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await self.engine.transcribe(samples)
                await MainActor.run {
                    if !text.isEmpty {
                        self.inserter.insert(text)
                        self.onTranscript?(text)
                        NSLog("Voicely transcript: %@", text)
                    }
                    self.state = .idle
                }
            } catch {
                NSLog("Voicely: transcribe error — \(error)")
                await MainActor.run { self.state = .idle }
            }
        }
    }
}
