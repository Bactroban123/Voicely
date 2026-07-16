import AVFoundation
import Foundation
import VoicelyCore

/// Records a meeting as two independent tracks — the microphone ("Me") and the
/// system output mixdown ("Them") — straight to disk.
///
/// Two tracks rather than one mixed stream is the whole trick: because the tap
/// captures playback and the mic captures input, speaker attribution falls out
/// of *which file a sample landed in*. No diarization model, no clustering.
///
/// Nothing is buffered in memory beyond a bounded ring: a two-hour meeting must
/// cost the same RAM as a two-minute one, even if the disk stalls. Both tracks
/// are written as 16 kHz mono Int16 CAF chunks — 16 kHz because that's what the
/// ASR engines consume anyway, Int16 because speech doesn't need Float32's range
/// (it halves the bytes), and CAF/PCM because it stays valid if the process is
/// killed mid-write, unlike AAC whose index lands at close.
///
/// This is a second, independent vertical: it never touches `AudioRecorder`,
/// `RecordingController`, or the dictation pipeline, so a meeting can record
/// while the user dictates.
@available(macOS 14.2, *)
final class MeetingRecorder {
    enum RecorderError: Error, CustomStringConvertible {
        case micUnavailable
        case noUsableInputFormat
        case alreadyRecording

        var description: String {
            switch self {
            case .micUnavailable: return "couldn't build a converter for the microphone format"
            case .noUsableInputFormat: return "no usable microphone input device"
            case .alreadyRecording: return "a meeting is already recording"
            }
        }
    }

    /// What `start` achieved. A tap failure must not abort a live meeting — but
    /// mic-only is, by this feature's own reasoning, the useless product that
    /// got the previous attempt deleted, so the caller is told rather than left
    /// to discover it after the call.
    enum StartOutcome: Equatable {
        case bothTracks
        case micOnly(reason: String)
    }

    private struct Track {
        let name: String
        var chunkIndex = -1                      // -1 = nothing opened yet
        var file: AVAudioFile?
        var framesInChunk: AVAudioFrameCount = 0
        var started = false
        /// Wall-clock offset of each opened chunk, against the meeting's t=0.
        var offsets: [Int: TimeInterval] = [:]
    }

    /// Rotate every 5 minutes: bounds worst-case loss on a hard kill to one
    /// chunk (~9.6MB), and keeps each file independently decodable.
    private let framesPerChunk: AVAudioFrameCount = 16_000 * 60 * 5
    /// How often the ring is drained to disk.
    private let drainInterval: TimeInterval = 0.25

    private let queue = DispatchQueue(label: "com.voicely.meeting.recorder", qos: .userInitiated)
    private let directory: URL
    private let engine = AVAudioEngine()
    private let tap = SystemAudioTap()
    private let systemRing = SampleRing()
    private var drainTimer: DispatchSourceTimer?
    private var scratch: UnsafeMutablePointer<Float>?
    private let scratchCapacity = 48_000

    private lazy var targetFormat: AVAudioFormat = {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                         channels: 1, interleaved: true) else {
            fatalError("Voicely: failed to build the 16kHz mono meeting format")
        }
        return format
    }()

    private var micTrack = Track(name: "mic")
    private var systemTrack = Track(name: "system")
    private var systemConverter: AVAudioConverter?
    private var tapFormat: AVAudioFormat?
    private var isRecording = false
    private var configObserver: NSObjectProtocol?
    /// The meeting's t=0. Both tracks measure against this one clock — deriving
    /// each track's zero from its own first sample would bias them apart by
    /// however long the tap took to come up.
    private var startedAt: Date?

    init(directory: URL) {
        self.directory = directory
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        scratch?.deallocate()
    }

    /// Starts both tracks. Throws only if the microphone can't start — a tap
    /// failure yields `.micOnly` with the reason, which the caller must surface.
    func start(completion: @escaping (Result<StartOutcome, Error>) -> Void) {
        queue.async { [self] in
            guard !isRecording else { return completion(.failure(RecorderError.alreadyRecording)) }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                // Fresh chunk numbering per recording. Reset here rather than in
                // teardown, because stop() reports the chunk list after tearing
                // down — and without a reset, a second recording would reopen
                // the last chunk and truncate the previous meeting's audio.
                micTrack = Track(name: "mic")
                systemTrack = Track(name: "system")
                startedAt = Date()
                try startMic()
                let outcome = startSystem()
                isRecording = true
                observeConfigurationChanges()
                startDraining()
                VoicelyLog.meeting.info("meeting recording started — \(outcome == .bothTracks ? "mic + system audio" : "MIC ONLY")")
                completion(.success(outcome))
            } catch {
                teardown()
                VoicelyLog.meeting.error("meeting recording failed to start — \(error)")
                completion(.failure(error))
            }
        }
    }

    /// Stops both tracks and closes the current chunks. `completion` receives
    /// the chunk files written, in order, per track.
    func stop(completion: @escaping (_ mic: [(URL, RecordedChunk)], _ system: [(URL, RecordedChunk)]) -> Void) {
        queue.async { [self] in
            let wasRecording = isRecording
            drainRing()          // flush whatever the ring still holds
            teardown()
            let mic = recordedChunks(for: micTrack)
            let system = recordedChunks(for: systemTrack)
            if wasRecording {
                let dropped = systemRing.dropped
                VoicelyLog.meeting.info(
                    "meeting stopped — \(mic.count) mic chunk(s), \(system.count) system chunk(s)"
                        + (dropped > 0 ? ", \(dropped) samples dropped (disk couldn't keep up)" : ""))
            }
            completion(mic, system)
        }
    }

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
        // AVAudioEngine's tap thread is not the audio IO thread and may allocate,
        // so hopping straight to `queue` is fine here (unlike the tap's IOProc).
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.queue.async { self.convertAndWrite(buffer, through: converter, toMic: true) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)   // never strand the tap on a failed start
            throw error
        }
        micTrack.started = true
    }

    /// Best-effort. Never throws: a meeting with only your own voice is degraded,
    /// not worthless, and aborting mid-call would be worse.
    private func startSystem() -> StartOutcome {
        do {
            try tap.start { [ring = systemRing] samples, count in
                // REAL-TIME THREAD. memcpy + index publish only: no allocation,
                // no ARC, no locks, no dispatch.
                ring.write(samples, count: count)
            }
            guard let format = tap.format,
                  let converter = AVAudioConverter(from: format, to: targetFormat) else {
                tap.stop()
                let reason = "no converter for the tap's format"
                VoicelyLog.meeting.error("system audio unavailable — \(reason)")
                return .micOnly(reason: reason)
            }
            tapFormat = format
            systemConverter = converter
            systemTrack.started = true
            return .bothTracks
        } catch {
            // The TCC-denial path lands here. It must never be swallowed.
            let reason = String(describing: error)
            VoicelyLog.meeting.error("system audio unavailable — \(reason)")
            return .micOnly(reason: reason)
        }
    }

    private func startDraining() {
        if scratch == nil {
            scratch = UnsafeMutablePointer<Float>.allocate(capacity: scratchCapacity)
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + drainInterval, repeating: drainInterval)
        timer.setEventHandler { [weak self] in self?.drainRing() }
        timer.resume()
        drainTimer = timer
    }

    /// Moves samples the RT thread parked in the ring onto disk.
    private func drainRing() {
        guard let scratch, let tapFormat, let converter = systemConverter else { return }
        while true {
            let count = systemRing.read(into: scratch, max: scratchCapacity)
            guard count > 0 else { return }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: tapFormat,
                                                frameCapacity: AVAudioFrameCount(count)) else { return }
            buffer.frameLength = AVAudioFrameCount(count)
            buffer.floatChannelData?[0].update(from: scratch, count: count)
            convertAndWrite(buffer, through: converter, toMic: false)
        }
    }

    private func convertAndWrite(_ buffer: AVAudioPCMBuffer, through converter: AVAudioConverter, toMic: Bool) {
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
        write(out, toMic: toMic)
    }

    private func write(_ buffer: AVAudioPCMBuffer, toMic: Bool) {
        var track = toMic ? micTrack : systemTrack
        defer { if toMic { micTrack = track } else { systemTrack = track } }

        let needsRotation = track.file != nil && track.framesInChunk + buffer.frameLength > framesPerChunk
        if track.file == nil || needsRotation {
            guard openChunk(&track) else { return }
        }
        do {
            try track.file?.write(from: buffer)
            track.framesInChunk += buffer.frameLength
        } catch {
            VoicelyLog.meeting.error("chunk write failed on \(track.name) — \(error)")
        }
    }

    /// Opens the next chunk and stamps its wall-clock offset.
    ///
    /// The index ALWAYS advances, including after a failure. Reusing it would
    /// reopen the previous chunk `forWriting` on the next buffer and truncate
    /// five minutes of recorded meeting — destroying audio while trying to
    /// recover from not being able to write it.
    private func openChunk(_ track: inout Track) -> Bool {
        track.chunkIndex += 1
        let index = track.chunkIndex
        let url = chunkURL(name: track.name, index: index)
        do {
            track.file = try AVAudioFile(forWriting: url, settings: targetFormat.settings,
                                         commonFormat: .pcmFormatInt16, interleaved: true)
            track.framesInChunk = 0
            track.offsets[index] = Date().timeIntervalSince(startedAt ?? Date())
            return true
        } catch {
            track.file = nil
            track.framesInChunk = 0
            VoicelyLog.meeting.error("couldn't open chunk \(url.lastPathComponent) — \(error)")
            return false
        }
    }

    /// A device switch (AirPods connecting) resets the engine; without this the
    /// mic track goes silent for the rest of the meeting.
    private func observeConfigurationChanges() {
        guard configObserver == nil else { return }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                guard self.isRecording else { return }
                VoicelyLog.meeting.warning("audio device changed mid-meeting — rebuilding the mic track")
                self.engine.inputNode.removeTap(onBus: 0)
                self.engine.stop()
                do {
                    try self.startMic()   // continues into the SAME chunk; a brief gap at the switch
                } catch {
                    VoicelyLog.meeting.error("mic track lost after a device change — \(error)")
                }
            }
        }
    }

    private func teardown() {
        drainTimer?.cancel()
        drainTimer = nil
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
        if micTrack.started || engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        tap.stop()
        isRecording = false
        systemConverter = nil
        tapFormat = nil
        // Dropping the last reference to the AVAudioFile flushes its header.
        // The chunk indices deliberately survive so stop() can still report
        // what was written; start() resets them for the next recording.
        micTrack.file = nil
        micTrack.started = false
        systemTrack.file = nil
        systemTrack.started = false
        startedAt = nil
    }

    private func chunkURL(name: String, index: Int) -> URL {
        directory.appendingPathComponent(String(format: "%@-%04d.caf", name, index))
    }

    /// Chunks written, in order, each with the wall-clock offset it started at.
    private func recordedChunks(for track: Track) -> [(URL, RecordedChunk)] {
        guard track.chunkIndex >= 0 else { return [] }
        return (0...track.chunkIndex).compactMap { index in
            let url = chunkURL(name: track.name, index: index)
            guard FileManager.default.fileExists(atPath: url.path),
                  let offset = track.offsets[index] else { return nil }
            let duration = (try? AVAudioFile(forReading: url))
                .map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0
            return (url, RecordedChunk(startOffset: offset, duration: duration))
        }
    }
}
