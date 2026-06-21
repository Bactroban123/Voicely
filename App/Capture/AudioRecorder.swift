import AVFoundation
import Foundation

/// Captures microphone audio and converts it to the 16 kHz mono Float32 the
/// transcription engines expect, while reporting RMS levels for the HUD waveform.
/// Triggers the microphone permission prompt on first `start()`.
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: 16_000,
                                             channels: 1,
                                             interleaved: false)!
    private var samples: [Float] = []
    private let lock = NSLock()

    /// Called on the main queue with the latest RMS level (0...~1).
    var onLevel: ((Float) -> Void)?

    func start() throws {
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        // TODO(perf, Phase 6): installTap is recommended off the main thread.
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    @discardableResult
    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock(); let result = samples; lock.unlock()
        return result
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let converter = converter else { return }
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
