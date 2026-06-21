import Foundation

/// The user-selectable models (the manual pickers in Settings). Defaults come
/// from research §1 (Parakeet) and §5 (Gemini 2.5 Flash-Lite).
public struct ModelOption: Equatable, Identifiable {
    public let id: String
    public let name: String
    public let detail: String
    public init(id: String, name: String, detail: String) {
        self.id = id
        self.name = name
        self.detail = detail
    }
}

public enum ModelCatalog {
    /// On-device transcription engines, fastest/leanest → broadest.
    public static let transcription: [ModelOption] = [
        ModelOption(id: "parakeet-en",
                    name: "Parakeet (English)",
                    detail: "Fastest + most accurate for English. Runs on the Neural Engine."),
        ModelOption(id: "apple-speech",
                    name: "Apple Dictation (native)",
                    detail: "No download, shared with macOS. Requires macOS 26+."),
        ModelOption(id: "parakeet-multi",
                    name: "Parakeet (Multilingual)",
                    detail: "Same speed; 25 languages + Japanese."),
        ModelOption(id: "whisper-large-v3-turbo",
                    name: "Whisper Large-v3-Turbo",
                    detail: "100 languages + custom-vocabulary support. ~550 MB."),
    ]

    /// OpenRouter cleanup models, default → strictest.
    public static let cleanup: [ModelOption] = [
        ModelOption(id: "google/gemini-2.5-flash-lite",
                    name: "Gemini 2.5 Flash-Lite",
                    detail: "Fast + cheap, thinking off. The default."),
        ModelOption(id: "openai/gpt-5-nano",
                    name: "GPT-5 Nano",
                    detail: "Cheapest. Low latency."),
        ModelOption(id: "meta-llama/llama-3.3-70b-instruct:nitro",
                    name: "Llama 3.3 70B (Nitro)",
                    detail: "Fastest wall-clock via throughput routing."),
        ModelOption(id: "anthropic/claude-haiku-4.5",
                    name: "Claude Haiku 4.5",
                    detail: "Strictest: least likely to invent edits."),
    ]

    public static let defaultTranscriptionID = "parakeet-en"
    public static let defaultCleanupID = "google/gemini-2.5-flash-lite"

    public static func transcriptionModel(id: String) -> ModelOption? {
        transcription.first { $0.id == id }
    }
    public static func cleanupModel(id: String) -> ModelOption? {
        cleanup.first { $0.id == id }
    }
}
