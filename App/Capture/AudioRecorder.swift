import AVFoundation
import Foundation

/// Captures microphone audio and converts it to the 16 kHz mono Float32 the
/// transcription engines expect, while reporting RMS levels for the HUD waveform.
/// Triggers the microphone permission prompt on first `start`.
///
/// All engine work runs on a private serial queue: `start`/`stop`/`prewarm`
/// return immediately, so the CGEventTap callback that drives them never waits
/// on CoreAudio (a stalled tap callback lags keyboard input system-wide and
/// gets the tap force-disabled). The serial queue also guarantees start/stop
/// FIFO ordering, which `installTap`/`removeTap` pairing depends on.
enum AudioRecorderError: Error {
    /// The input device reported a 0 Hz / 0-channel format — no usable mic
    /// (or a device switch is still settling). installTap would throw an
    /// uncatchable NSException with such a format, so we refuse first.
    case noUsableInputDevice
    /// The tap format still disagrees with the hardware rate even after a
    /// fresh engine. installTap would abort the app on this, so we refuse.
    case inputFormatMismatch(tapRate: Double, hardwareRate: Double)
    /// The mic's native format can't be converted to 16kHz mono (exotic
    /// device). Previously this was swallowed: every buffer was dropped and
    /// the take produced silence with no diagnostic anywhere.
    case unsupportedInputFormat(AVAudioFormat)
}

final class AudioRecorder {
    /// Queue-confined. Replaced wholesale when its input format goes stale
    /// after a device switch — see `AVAudioInputNode.hasStaleOutputFormat`.
    private var engine = AVAudioEngine()
    private let targetFormat = AudioRecorder.makeTargetFormat()
    private var samples: [Float] = []
    private let lock = NSLock()

    /// Serializes every touch of `engine`/`isCapturing`. (Each tap's converter
    /// is captured by that tap's closure and lives on the tap-callback thread.)
    private let queue = DispatchQueue(label: "com.voicely.audio", qos: .userInitiated)
    /// Queue-confined: whether a tap is installed and the engine is running.
    private var isCapturing = false
    private var configObserver: NSObjectProtocol?

    /// The 16kHz mono Float32 format the transcription engines expect. These
    /// parameters are fixed and valid, so this cannot fail in practice; the
    /// guard exists only to give a diagnosable crash instead of a bare `!`.
    private static func makeTargetFormat() -> AVAudioFormat {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                          sampleRate: 16_000,
                                          channels: 1,
                                          interleaved: false) else {
            fatalError("Voicely: failed to construct the 16kHz mono target format")
        }
        return format
    }

    /// Called on the main queue with the latest RMS level (0...~1).
    var onLevel: ((Float) -> Void)?

    init() {
        observeConfigurationChanges()
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    /// Pre-allocates engine resources so the next `start` is as fast as possible.
    /// Touching `inputNode` first is what actually pulls the input HAL unit
    /// into the graph — `prepare()` on an untouched engine prepares an empty
    /// graph and pre-warms nothing.
    func prewarm() {
        queue.async { [self] in
            _ = engine.inputNode.outputFormat(forBus: 0)
            engine.prepare()
        }
    }

    /// Begins capture. `completion` runs on the recorder's queue with the
    /// engine-start latency in ms, or the error.
    func start(completion: @escaping (Result<Int, Error>) -> Void) {
        queue.async { [self] in
            if isCapturing {
                // Shouldn't happen once the session FSM is unified; defensive
                // teardown beats an installTap-twice NSException.
                VoicelyLog.recording.warning("start requested while already capturing — restarting")
                tearDownCapture()
            }
            lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()
            let began = CFAbsoluteTimeGetCurrent()
            do {
                try beginCapture()
                isCapturing = true
                completion(.success(Int((CFAbsoluteTimeGetCurrent() - began) * 1000)))
            } catch {
                isCapturing = false
                completion(.failure(error))
            }
        }
    }

    /// Ends capture. `completion` runs on the recorder's queue with everything
    /// captured since `start`. Also re-arms the engine for the next press.
    func stop(completion: @escaping ([Float]) -> Void) {
        queue.async { [self] in
            if isCapturing { tearDownCapture() }
            lock.lock(); let result = samples; lock.unlock()
            engine.prepare() // re-arm so the next start stays snappy
            completion(result)
        }
    }

    // MARK: - Queue-confined internals

    /// Default-device switches (e.g. Bluetooth headset connecting) reset the
    /// engine; rebuild capture instead of silently recording nothing. The
    /// notification is per engine instance, so `replaceEngine()` re-registers.
    private func observeConfigurationChanges() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        let observed = engine
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: observed, queue: nil
        ) { [weak self, weak observed] _ in
            guard let self else { return }
            self.queue.async {
                // A change queued by an engine we've since replaced is stale news.
                guard let observed, observed === self.engine else { return }
                self.handleConfigurationChange()
            }
        }
    }

    private func replaceEngine() {
        engine.stop()
        engine = AVAudioEngine()
        observeConfigurationChanges()
    }

    private func beginCapture() throws {
        if engine.inputNode.hasStaleOutputFormat {
            let stale = engine.inputNode
            VoicelyLog.recording.warning(
                "input format is stale after a device change (\(Int(stale.outputFormat(forBus: 0).sampleRate)) Hz,"
                    + " hardware \(Int(stale.inputFormat(forBus: 0).sampleRate)) Hz) — rebuilding the audio engine")
            replaceEngine()
        }
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioRecorderError.noUsableInputDevice
        }
        // installTap's own precondition, checked here so a mismatch is a
        // failed take instead of an abort.
        let hardwareRate = input.inputFormat(forBus: 0).sampleRate
        guard inputFormat.sampleRate == hardwareRate else {
            throw AudioRecorderError.inputFormatMismatch(tapRate: inputFormat.sampleRate, hardwareRate: hardwareRate)
        }

        // The converter is captured by THIS tap's closure (not a shared stored
        // property): an in-flight callback from an old tap can never race a
        // rebuild's reassignment or feed an old-format buffer to a new converter.
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioRecorderError.unsupportedInputFormat(inputFormat)
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer, with: converter)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0) // never leak the tap: a second install would crash
            throw error
        }
    }

    private func tearDownCapture() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
    }

    private func handleConfigurationChange() {
        guard isCapturing else {
            VoicelyLog.recording.info("audio config changed while idle — re-arming engine")
            // Swap a stale engine now, so the next press doesn't pay for the
            // rebuild (beginCapture still checks, as the backstop).
            if engine.inputNode.hasStaleOutputFormat {
                let stale = engine.inputNode
                VoicelyLog.recording.warning(
                    "input format went stale (\(Int(stale.outputFormat(forBus: 0).sampleRate)) Hz,"
                        + " hardware \(Int(stale.inputFormat(forBus: 0).sampleRate)) Hz) — rebuilding the idle audio engine")
                replaceEngine()
                _ = engine.inputNode.outputFormat(forBus: 0) // pull the input unit in, as prewarm does
            }
            engine.prepare()
            return
        }
        VoicelyLog.recording.warning("audio config changed mid-recording — rebuilding capture")
        tearDownCapture()
        do {
            try beginCapture() // samples so far are preserved; brief gap at the switch
            isCapturing = true
        } catch {
            // Accepted limitation: capture does not auto-resume later — the take
            // ends here (partial samples still return from the eventual stop).
            VoicelyLog.recording.error("could not rebuild capture after device change — take truncated: \(error)")
        }
    }

    private func process(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1_024
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error else { return }

        appendAndMeter(out)
    }

    private func appendAndMeter(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        let ptr = channel[0]

        var sumSquares: Float = 0
        var chunk = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let sample = ptr[i]
            chunk[i] = sample
            sumSquares += sample * sample
        }

        lock.lock(); samples.append(contentsOf: chunk); lock.unlock()

        let rms = (sumSquares / Float(count)).squareRoot()
        DispatchQueue.main.async { [weak self] in self?.onLevel?(rms) }
    }
}
