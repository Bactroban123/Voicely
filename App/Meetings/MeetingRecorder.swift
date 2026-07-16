import AVFoundation
import Foundation

/// Records a meeting as two independent tracks — the microphone ("Me") and the
/// system output mixdown ("Them") — straight to disk.
///
/// Two tracks rather than one mixed stream is the whole trick: because the tap
/// captures playback and the mic captures input, the speaker attribution falls
/// out of *which file a sample landed in*. No diarization model, no clustering,
/// no guessing.
///
/// Nothing is buffered in memory beyond one AVAudioPCMBuffer at a time: a
/// two-hour meeting must cost the same RAM as a two-minute one. Both tracks are
/// written as 16 kHz mono Int16 CAF chunks — 16 kHz because that's what the ASR
/// engines consume anyway, Int16 because speech doesn't need Float32's range
/// (it halves the bytes), and CAF/PCM because it stays valid if the process is
/// killed mid-write, unlike AAC whose index lands at close.
///
/// This is a second, independent vertical: it never touches `AudioRecorder`,
/// `RecordingController`, or the dictation pipeline, so a meeting can record
/// while the user dictates.
@available(macOS 14.2, *)
final class MeetingRecorder {
    enum RecorderError: Error {
        case micUnavailable
        case noUsableInputFormat
    }

    /// One track's on-disk chunk sequence.
    struct Track {
        let name: String            // "mic" | "system"
        var chunkIndex = 0
        var file: AVAudioFile?
        var framesInChunk: AVAudioFrameCount = 0
    }

    /// Rotate every 5 minutes: bounds worst-case loss on a hard kill to one
    /// chunk, and keeps each file independently decodable.
    private let framesPerChunk: AVAudioFrameCount = 16_000 * 60 * 5

    private let queue = DispatchQueue(label: "com.voicely.meeting.recorder", qos: .userInitiated)
    private let directory: URL
    private let engine = AVAudioEngine()
    private let tap = SystemAudioTap()
    private lazy var targetFormat: AVAudioFormat = {
        guard let f = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                    channels: 1, interleaved: true) else {
            fatalError("Voicely: failed to build the 16kHz mono meeting format")
        }
        return f
    }()

    private var micTrack = Track(name: "mic")
    private var systemTrack = Track(name: "system")
    private var systemConverter: AVAudioConverter?
    private var isRecording = false

    init(directory: URL) {
        self.directory = directory
    }

    /// Starts both tracks. Throws if the mic can't start; a tap failure is
    /// reported but does NOT abort — a mic-only recording is degraded (it's
    /// what the abandoned prototype was) but still better than nothing, and the
    /// caller surfaces it.
    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [self] in
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try startMic()
                startSystem()   // best-effort
                isRecording = true
                completion(.success(()))
            } catch {
                teardown()
                completion(.failure(error))
            }
        }
    }

    /// Stops both tracks and closes the current chunks. `completion` receives
    /// the chunk files written, in order, per track.
    func stop(completion: @escaping (_ mic: [URL], _ system: [URL]) -> Void) {
        queue.async { [self] in
            teardown()
            let mic = chunkURLs(for: micTrack)
            let system = chunkURLs(for: systemTrack)
            VoicelyLog.meeting.info("meeting stopped — \(mic.count) mic chunk(s), \(system.count) system chunk(s)")
            completion(mic, system)
        }
    }

    /// True when the system tap is live; false means mic-only (degraded).
    private(set) var capturingSystemAudio = false

    // MARK: - Queue-confined internals

    private func startMic() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RecorderError.noUsableInputFormat
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.micUnavailable
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.queue.async { self?.write(buffer, through: converter, to: \.micTrack) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    private func startSystem() {
        guard let tapFormat = try? startTapAndFormat() else { return }
        systemConverter = AVAudioConverter(from: tapFormat, to: targetFormat)
        capturingSystemAudio = systemConverter != nil
        if !capturingSystemAudio {
            VoicelyLog.meeting.error("no converter for the tap format — recording mic only")
            tap.stop()
        }
    }

    private func startTapAndFormat() throws -> AVAudioFormat {
        try tap.start { [weak self] samples, count in
            // Real-time thread: copy out and hand off immediately.
            guard let self, let format = self.tap.format,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                                frameCapacity: AVAudioFrameCount(count)) else { return }
            buffer.frameLength = AVAudioFrameCount(count) / format.channelCount
            if let dst = buffer.floatChannelData?[0] {
                dst.update(from: samples, count: count)
            }
            self.queue.async {
                guard let converter = self.systemConverter else { return }
                self.write(buffer, through: converter, to: \.systemTrack)
            }
        }
        guard let format = tap.format else { throw SystemAudioTap.TapError.tapFormatUnavailable }
        return format
    }

    private func write(_ buffer: AVAudioPCMBuffer, through converter: AVAudioConverter,
                       to keyPath: ReferenceWritableKeyPath<MeetingRecorder, Track>) {
        guard isRecording else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1_024
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if consumed { inputStatus.pointee = .noDataNow; return nil }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, out.frameLength > 0 else { return }

        if self[keyPath: keyPath].file == nil { openChunk(keyPath) }
        if self[keyPath: keyPath].framesInChunk + out.frameLength > framesPerChunk {
            openChunk(keyPath)   // rotate
        }
        do {
            try self[keyPath: keyPath].file?.write(from: out)
            self[keyPath: keyPath].framesInChunk += out.frameLength
        } catch {
            VoicelyLog.meeting.error("chunk write failed on \(self[keyPath: keyPath].name) — \(error)")
        }
    }

    private func openChunk(_ keyPath: ReferenceWritableKeyPath<MeetingRecorder, Track>) {
        let track = self[keyPath: keyPath]
        let index = track.file == nil ? track.chunkIndex : track.chunkIndex + 1
        let url = chunkURL(name: track.name, index: index)
        do {
            let file = try AVAudioFile(forWriting: url, settings: targetFormat.settings,
                                       commonFormat: .pcmFormatInt16, interleaved: true)
            self[keyPath: keyPath].file = file
            self[keyPath: keyPath].chunkIndex = index
            self[keyPath: keyPath].framesInChunk = 0
        } catch {
            VoicelyLog.meeting.error("couldn't open chunk \(url.lastPathComponent) — \(error)")
        }
    }

    private func teardown() {
        guard isRecording || engine.isRunning else { return }
        isRecording = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        tap.stop()
        capturingSystemAudio = false
        micTrack.file = nil        // closing the AVAudioFile flushes its header
        systemTrack.file = nil
        systemConverter = nil
    }

    private func chunkURL(name: String, index: Int) -> URL {
        directory.appendingPathComponent(String(format: "%@-%04d.caf", name, index))
    }

    private func chunkURLs(for track: Track) -> [URL] {
        guard track.chunkIndex >= 0, FileManager.default.fileExists(atPath: chunkURL(name: track.name, index: 0).path)
        else { return [] }
        return (0...track.chunkIndex)
            .map { chunkURL(name: track.name, index: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
