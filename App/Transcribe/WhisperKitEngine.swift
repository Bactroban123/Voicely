import Foundation
import VoicelyCore
import WhisperKit

/// On-device transcription via WhisperKit (Whisper large-v3-turbo). Unlike
/// Parakeet, Whisper is multilingual (~100 languages incl. Hebrew), with
/// automatic language detection so it handles English and Hebrew in one model.
/// First use downloads the model (~600 MB) once.
actor WhisperKitEngine: TranscriptionEngine {
    private var kit: WhisperKit?
    /// The in-flight load, so concurrent callers join it instead of each
    /// starting their own. `prepare()` suspends inside `WhisperKit.init`, and
    /// actors are re-entrant: without this, the warm-load kicked off at launch
    /// and the first dictation's `prepare()` both saw `kit == nil` and loaded
    /// 1.5 GB of weights twice, side by side.
    private var loadTask: Task<WhisperKit, Error>?
    private let modelName: String
    private let modelsDirectory: URL

    /// - Parameter modelsDirectory: where weights are downloaded and read from.
    ///   Must be somewhere macOS won't sync, evict or purge — see `ModelStorage`.
    ///   WhisperKit's own default is `~/Documents/huggingface`, which is inside
    ///   iCloud Drive; leaving it there is what made dictation hang forever.
    init(modelName: String = "large-v3-v20240930_turbo",
         modelsDirectory: URL = ModelStorage.modelsDirectory(
            applicationSupport: FileManager.default.urls(for: .applicationSupportDirectory,
                                                        in: .userDomainMask)[0])) {
        self.modelName = modelName
        self.modelsDirectory = modelsDirectory
    }

    func prepare() async throws {
        _ = try await loadedKit()
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard !samples.isEmpty else { throw TranscriptionError.emptyAudio }
        let kit = try await loadedKit()

        // Auto-detect the spoken language (English, Hebrew, …) per utterance.
        let options = DecodingOptions(detectLanguage: true)
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        return results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Loads the model once and keeps it resident. Safe to call concurrently.
    private func loadedKit() async throws -> WhisperKit {
        if let kit { return kit }
        if let loadTask { return try await loadTask.value }

        // A weights directory the system can take back is a configuration bug,
        // not a runtime condition: an evicted file blocks in read(2) with no
        // error and no timeout, which reads as "the app is just slow" forever.
        assert(ModelStorage.isSafeForModelWeights(modelsDirectory),
               "model weights must not live somewhere macOS can sync or purge: \(modelsDirectory.path)")

        let name = modelName
        let directory = modelsDirectory
        VoicelyLog.model.info("loading \(name) from \(directory.path)")
        let started = Date()
        let task = Task {
            try await WhisperKit(
                model: name,
                downloadBase: directory, // also where the tokenizer lands
                verbose: false,
                prewarm: true,
                load: true,
                download: true)
        }
        loadTask = task
        do {
            let loaded = try await task.value
            kit = loaded
            loadTask = nil
            VoicelyLog.model.info("loaded \(name) in \(Int(Date().timeIntervalSince(started) * 1000))ms")
            return loaded
        } catch {
            // Clear the task so the next dictation retries rather than
            // replaying a stored failure forever.
            loadTask = nil
            VoicelyLog.model.error("failed to load \(name) — \(error)")
            throw error
        }
    }
}
