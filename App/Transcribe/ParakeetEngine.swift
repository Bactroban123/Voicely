import Foundation
import FluidAudio

/// On-device transcription via FluidAudio's Parakeet TDT models. v2 = English
/// (fastest + most accurate for our default); v3 = multilingual. Usage pattern
/// mirrors FluidAudio's own CLI: download+load models once, keep the AsrManager
/// resident, and run each utterance with a fresh decoder state.
actor ParakeetEngine: TranscriptionEngine {
    private var manager: AsrManager?
    private let version: AsrModelVersion

    init(version: AsrModelVersion = .v2) {
        self.version = version
    }

    func prepare() async throws {
        guard manager == nil else { return }
        let models = try await AsrModels.downloadAndLoad(version: version)
        let manager = AsrManager()
        try await manager.loadModels(models)
        self.manager = manager
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard !samples.isEmpty else { throw TranscriptionError.emptyAudio }
        try await prepare()
        guard let manager else { throw TranscriptionError.notReady }

        var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
