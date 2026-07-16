import AVFoundation
import FluidAudio
import Foundation
import VoicelyCore

// Note: `Speaker` is qualified throughout — FluidAudio exports a Speaker type
// of its own (from its diarizer), so the bare name is ambiguous here.

/// Turns a meeting's recorded chunks into a two-speaker dialogue.
///
/// Each track is transcribed independently — the mic is you, the system mixdown
/// is everyone else — so neither engine ever hears a mix of voices, and speaker
/// attribution is already known before a word is transcribed. `DialogueMerge`
/// then weaves them together by time.
///
/// Deliberately its own engine instance, at `.utility`: an actor serialises its
/// queue, so sharing the dictation engine would make the next hotkey press wait
/// behind an hour of meeting audio. Dictation stays instant.
@available(macOS 14.2, *)
actor MeetingTranscriptionService {
    struct Progress: Equatable {
        let completedChunks: Int
        let totalChunks: Int
        var fraction: Double {
            totalChunks > 0 ? Double(completedChunks) / Double(totalChunks) : 0
        }
    }

    enum TranscriptionError: Error, CustomStringConvertible {
        case noAudio
        var description: String {
            switch self { case .noAudio: return "the meeting has no readable audio" }
        }
    }

    private var manager: AsrManager?

    /// Transcribes both tracks and returns the merged dialogue.
    ///
    /// - Parameters:
    ///   - mic: mic chunks in recording order (may be empty).
    ///   - system: system-audio chunks in recording order (empty when the tap
    ///     was refused — the meeting is then one-sided but still transcribed).
    ///   - onProgress: fires on this actor as chunks complete.
    func transcribe(mic: [URL],
                    system: [URL],
                    onProgress: @Sendable (Progress) -> Void = { _ in }) async throws -> [TranscriptSegment] {
        guard !mic.isEmpty || !system.isEmpty else { throw TranscriptionError.noAudio }
        try await prepare()

        let total = mic.count + system.count
        var completed = 0
        func tick() {
            completed += 1
            onProgress(Progress(completedChunks: completed, totalChunks: total))
        }

        let meSegments = try await segments(for: mic, speaker: VoicelyCore.Speaker.me, onChunk: tick)
        let themSegments = try await segments(for: system, speaker: VoicelyCore.Speaker.them, onChunk: tick)
        return DialogueMerge.merge(me: meSegments, them: themSegments)
    }

    // MARK: - Internals

    private func prepare() async throws {
        guard manager == nil else { return }
        // v3 (multilingual) rather than dictation's English-default v2: a call
        // is likelier to contain another language than a dictation is, and the
        // cost is a slightly larger model we're loading in the background anyway.
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        let manager = AsrManager()
        try await manager.loadModels(models)
        self.manager = manager
    }

    /// Transcribes one track, placing every segment on the meeting's timeline.
    private func segments(for chunks: [URL],
                          speaker: VoicelyCore.Speaker,
                          onChunk: () -> Void) async throws -> [TranscriptSegment] {
        guard !chunks.isEmpty, let manager else { return [] }

        // Durations are MEASURED, never assumed: chunks are nominally 5 minutes,
        // but the last one is short and a rotation failure or device change can
        // shorten any of them. Assuming the nominal length would drift every
        // later timestamp, silently.
        let timeline = ChunkTimeline(durations: chunks.map { Self.duration(of: $0) })

        var placed: [TranscriptSegment] = []
        for (index, url) in chunks.enumerated() {
            defer { onChunk() }
            guard Self.duration(of: url) > 0 else { continue }
            do {
                // Fresh decoder state per chunk: chunks are independent files,
                // and carrying state across them would let one chunk's tail
                // bleed into the next one's opening words.
                var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
                // The URL overload streams from disk for long files, so a 5-min
                // chunk never lands in memory as one big [Float].
                let result = try await manager.transcribe(url, decoderState: &decoderState)
                let chunkSegments = Self.segments(from: result, speaker: speaker)
                placed += timeline.place(chunkSegments, fromChunk: index)
            } catch {
                // One bad chunk must not lose the rest of the meeting.
                VoicelyLog.meeting.error("chunk \(url.lastPathComponent) failed to transcribe — \(error)")
            }
        }
        return placed
    }

    /// Maps the engine's timings onto the pure grouping logic in VoicelyCore.
    ///
    /// The grouping itself lives there because getting it wrong is invisible:
    /// an earlier version trimmed each token before joining and welded every
    /// word together ("Hey,canyouhearme"). It compiled, and every test built
    /// from hand-made segments passed. Only real audio caught it — so the rule
    /// now lives where a test can pin it, against a real captured token stream.
    private static func segments(from result: ASRResult, speaker: VoicelyCore.Speaker) -> [TranscriptSegment] {
        guard let timings = result.tokenTimings, !timings.isEmpty else {
            // No timings: keep the text rather than drop it, spanning the chunk.
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return [] }
            return [TranscriptSegment(speaker: speaker, text: text, start: 0, end: result.duration)]
        }
        let tokens = timings.map { TimedToken(text: $0.token, start: $0.startTime, end: $0.endTime) }
        return TokenGrouping.segments(from: tokens, speaker: speaker)
    }

    private static func duration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }
}
