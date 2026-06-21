import Foundation
import WhisperKit

/// On-device transcription via WhisperKit (Whisper large-v3-turbo). Unlike
/// Parakeet, Whisper is multilingual (~100 languages incl. Hebrew), with
/// automatic language detection so it handles English and Hebrew in one model.
/// First use downloads the model (~600 MB) once.
actor WhisperKitEngine: TranscriptionEngine {
    private var kit: WhisperKit?
    private let modelName: String

    init(modelName: String = "large-v3-v20240930_turbo") {
        self.modelName = modelName
    }

    func prepare() async throws {
        guard kit == nil else { return }
        kit = try await WhisperKit(
            model: modelName,
            verbose: false,
            prewarm: true,
            load: true,
            download: true)
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard !samples.isEmpty else { throw TranscriptionError.emptyAudio }
        try await prepare()
        guard let kit else { throw TranscriptionError.notReady }

        // Auto-detect the spoken language (English, Hebrew, …) per utterance.
        let options = DecodingOptions(detectLanguage: true)
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        return results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
