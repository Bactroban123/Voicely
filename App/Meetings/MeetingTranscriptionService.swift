import AVFoundation
import Foundation
import VoicelyCore

/// Turns a meeting's recorded chunks into a two-speaker dialogue.
///
/// Each track is transcribed independently — the mic is you, the system mixdown
/// is everyone else — so neither engine ever hears a mix of voices, and speaker
/// attribution is already known before a word is transcribed. `DialogueMerge`
/// then weaves them together by time.
///
/// Deliberately its own transcriber instance, never dictation's: an actor
/// serialises its queue, so sharing would make the next hotkey press wait behind
/// an hour of meeting audio.
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

    private let transcriber: MeetingTranscriber

    /// Uses the model the user chose for dictation. Substituting a faster engine
    /// would silently downgrade a Hebrew speaker's meetings to one that can't
    /// read Hebrew — and Hebrew is the product's own differentiator.
    init(modelID: String) {
        switch modelID {
        case "whisper-large-v3-turbo":
            transcriber = WhisperMeetingTranscriber()
        default:
            // Parakeet v3 covers the same English as v2 plus 24 more languages
            // at the same speed, and a call is likelier than a dictation to
            // contain one of them.
            transcriber = ParakeetMeetingTranscriber(version: .v3)
        }
    }

    /// Transcribes both tracks and returns the merged dialogue.
    ///
    /// - Parameters:
    ///   - mic: mic chunks in recording order, each with its wall-clock offset.
    ///   - system: system-audio chunks (empty when the tap was refused — the
    ///     meeting is then one-sided but still transcribed).
    ///   - onProgress: fires on this actor as chunks complete.
    func transcribe(mic: [(URL, RecordedChunk)],
                    system: [(URL, RecordedChunk)],
                    onProgress: @Sendable (Progress) -> Void = { _ in }) async throws -> [TranscriptSegment] {
        guard !mic.isEmpty || !system.isEmpty else { throw TranscriptionError.noAudio }
        try await transcriber.prepare()

        let total = mic.count + system.count
        var completed = 0
        func tick() {
            completed += 1
            onProgress(Progress(completedChunks: completed, totalChunks: total))
        }

        let meSegments = await segments(for: mic, speaker: VoicelyCore.Speaker.me, onChunk: tick)
        let themSegments = await segments(for: system, speaker: VoicelyCore.Speaker.them, onChunk: tick)
        return DialogueMerge.merge(me: meSegments, them: themSegments)
    }

    // MARK: - Internals

    /// Transcribes one track, placing every segment on the meeting's timeline.
    private func segments(for chunks: [(URL, RecordedChunk)],
                          speaker: VoicelyCore.Speaker,
                          onChunk: () -> Void) async -> [TranscriptSegment] {
        guard !chunks.isEmpty else { return [] }

        // Offsets come from the recorder's wall clock, not from summing
        // durations: lost audio (a device switch, a failed chunk open, a ring
        // overflow) advances the clock without growing the file, and summing
        // would then run one track early and interleave the wrong speaker.
        let timeline = ChunkTimeline(chunks: chunks.map(\.1))

        var placed: [TranscriptSegment] = []
        for (index, chunk) in chunks.enumerated() {
            defer { onChunk() }
            guard chunk.1.duration > 0 else { continue }
            do {
                let chunkSegments = try await transcriber.segments(inChunk: chunk.0, speaker: speaker)
                placed += timeline.place(chunkSegments, fromChunk: index)
            } catch {
                // One bad chunk must not lose the rest of the meeting.
                VoicelyLog.meeting.error("chunk \(chunk.0.lastPathComponent) failed to transcribe — \(error)")
            }
        }
        return placed
    }
}
