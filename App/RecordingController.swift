import AppKit
import VoicelyCore

/// Ties the hotkey monitor to the pure HotKeyProcessor and the audio recorder.
/// Phase 1: start/stop recording and surface UI state. Later phases hand the
/// captured samples to transcription → cleanup → insertion.
final class RecordingController {
    enum UIState { case idle, recording }

    private(set) var state: UIState = .idle {
        didSet { onStateChange?(state) }
    }
    var onStateChange: ((UIState) -> Void)?

    // Default hotkey: Right Option (keyCode 61). User-configurable in a later phase.
    private var processor = HotKeyProcessor(config: HotKeyConfig(hotKeyCode: 61))
    private let recorder = AudioRecorder()
    private lazy var monitor = KeyEventMonitor { [weak self] event in
        // CGEventTap callbacks fire on the main run loop, so this is main-thread.
        self?.handle(event)
    }

    /// Returns false if the event tap couldn't start (Input Monitoring not granted).
    func start() -> Bool {
        recorder.onLevel = { level in
            // Phase 5 wires this to the HUD waveform.
            _ = level
        }
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
            state = .idle
            let seconds = Double(samples.count) / 16_000.0
            NSLog("Voicely: captured %d samples (%.1fs)", samples.count, seconds)
        case .cancel:
            recorder.stop()
            state = .idle
            NSLog("Voicely: cancelled")
        }
    }
}
