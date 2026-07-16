import AVFoundation
import FluidAudio
import Foundation
import VoicelyCore
import WhisperKit

/// Transcribes one chunk file into timed segments.
///
/// Meetings must honour the transcription model the user picked in Settings,
/// not quietly substitute another. Parakeet is faster, but it does not speak
/// Hebrew — `WhisperKitEngine` says so itself, and dictation already routes
/// Hebrew to WhisperKit for exactly that reason. Hardcoding Parakeet here would
/// have handed an EN⇄HE user confident Latin-script nonsense for half of every
/// call, with no error to explain it — and Hebrew is the product's own
/// differentiator.
@available(macOS 14.2, *)
protocol MeetingTranscriber {
    /// Load models. May download hundreds of MB on first use.
    func prepare() async throws
    /// Segments with times relative to the START OF THIS CHUNK.
    func segments(inChunk url: URL, speaker: VoicelyCore.Speaker) async throws -> [TranscriptSegment]
}

// MARK: - Parakeet (fast, English + 25 European languages)

/// Uses the URL overload, which streams from disk — a chunk never lands in
/// memory as one big `[Float]`.
@available(macOS 14.2, *)
actor ParakeetMeetingTranscriber: MeetingTranscriber {
    private var manager: AsrManager?
    private let version: AsrModelVersion

    init(version: AsrModelVersion = .v3) { self.version = version }

    func prepare() async throws {
        guard manager == nil else { return }
        let models = try await AsrModels.downloadAndLoad(version: version)
        let manager = AsrManager()
        try await manager.loadModels(models)
        self.manager = manager
    }

    func segments(inChunk url: URL, speaker: VoicelyCore.Speaker) async throws -> [TranscriptSegment] {
        try await prepare()
        guard let manager else { return [] }
        // Fresh decoder state per chunk: chunks are independent files, and
        // carrying state across them would bleed one chunk's tail into the
        // next one's opening words.
        var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(url, decoderState: &decoderState)

        guard let timings = result.tokenTimings, !timings.isEmpty else {
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return [] }
            return [TranscriptSegment(speaker: speaker, text: text, start: 0, end: result.duration)]
        }
        let tokens = timings.map { TimedToken(text: $0.token, start: $0.startTime, end: $0.endTime) }
        // Parakeet exposes no per-segment confidence, so only the stock-phrase
        // check applies here.
        return TokenGrouping.segments(from: tokens, speaker: speaker)
            .filter { SpeechConfidence.isSpeech(text: $0.text, confidence: nil) }
    }
}

// MARK: - Whisper (slower, ~100 languages incl. Hebrew)

/// Whisper returns segment-level timings directly, so no token grouping is
/// needed. It loads the chunk into memory, which is fine *because* the recorder
/// rotates every 5 minutes (~9.6 MB at 16 kHz Int16) — the chunking that exists
/// for crash-safety also bounds this.
@available(macOS 14.2, *)
actor WhisperMeetingTranscriber: MeetingTranscriber {
    private var kit: WhisperKit?
    private let modelName: String

    init(modelName: String = "large-v3-v20240930_turbo") { self.modelName = modelName }

    func prepare() async throws {
        guard kit == nil else { return }
        kit = try await WhisperKit(model: modelName, verbose: false, prewarm: true, load: true, download: true)
    }

    func segments(inChunk url: URL, speaker: VoicelyCore.Speaker) async throws -> [TranscriptSegment] {
        try await prepare()
        guard let kit else { return [] }
        // Detect the language per chunk: a call can switch languages partway,
        // and each chunk is only 5 minutes of it.
        let options = DecodingOptions(detectLanguage: true, chunkingStrategy: .vad)
        let results = try await kit.transcribe(audioPath: url.path, decodeOptions: options)

        let segments = results.flatMap(\.segments).compactMap { segment -> TranscriptSegment? in
            // Segment text carries Whisper's control tokens inline
            // (<|startoftranscript|><|he|><|0.00|>…). The library strips them
            // for its own top-level `text`, but that has no timings — and
            // timings are the point here — so we strip them ourselves.
            let text = WhisperText.strippingSpecialTokens(segment.text)
            // Whisper invents filler from silence, and a meeting's other track
            // is silent whenever the other person isn't talking — so without
            // this, every quiet gap becomes dialogue nobody said, and the
            // summarizer treats it as real. It reports its own doubt; we act
            // on it.
            guard SpeechConfidence.isSpeech(
                text: text,
                confidence: SegmentConfidence(noSpeechProbability: segment.noSpeechProb,
                                              averageLogProbability: segment.avgLogprob))
            else {
                VoicelyLog.meeting.info(
                    "dropped a likely hallucination (noSpeech \(String(format: "%.2f", segment.noSpeechProb)))")
                return nil
            }
            return TranscriptSegment(speaker: speaker, text: text,
                                     start: TimeInterval(segment.start),
                                     end: TimeInterval(segment.end))
        }
        // Whisper's segments are already utterance-sized; coalescing only tidies
        // the seams between them.
        return DialogueMerge.coalesce(segments)
    }
}
