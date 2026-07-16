import Foundation

/// Builds the OpenRouter chat-completions request body for the cleanup step,
/// encoding the research §5 decisions: temp 0.1, reasoning off, streaming, and
/// latency-first provider routing with zero-data-retention on by default.
/// The actual URLSession call lives in the app (OS-bound); this part is pure.
public struct CleanupRequest: Codable, Equatable {
    public struct Message: Codable, Equatable {
        public let role: String
        public let content: String
    }
    public struct Reasoning: Codable, Equatable {
        public let enabled: Bool
    }
    public struct Provider: Codable, Equatable {
        public let sort: String
        public let data_collection: String
        public let zdr: Bool
    }

    public let model: String
    public let messages: [Message]
    public let temperature: Double
    public let max_tokens: Int
    public let stream: Bool
    public let reasoning: Reasoning
    public let provider: Provider

    /// Token budget for the cleaned output, sized from the transcript.
    ///
    /// A fixed cap silently truncates long dictations: the model stops
    /// mid-sentence, the API still returns 200, and the half-sentence gets
    /// pasted as if it were correct. Cleanup rewrites rather than expands, but
    /// translation can inflate token counts (Hebrew and Thai tokenize far more
    /// densely than English), so budget from the input with real headroom.
    ///
    /// The 4096 ceiling is about provider routing, not cost (`max_tokens` is
    /// billed on tokens generated, not reserved): OpenRouter only routes to
    /// providers that can return a response of the requested length, so a
    /// bigger number quietly shrinks the pool — past ~8k it drops Gemini, past
    /// ~16k it drops several Llama endpoints. Beyond the ceiling the safety net
    /// is `finish_reason`, checked at the call site.
    public static func maxTokens(forTranscript transcript: String) -> Int {
        let estimatedInputTokens = max(1, transcript.count / 2) // conservative: English is ~4 chars/token
        return min(4096, max(400, estimatedInputTokens * 2 + 256))
    }

    /// `maxTokens: nil` sizes the budget from the transcript (recommended).
    public init(modelID: String,
                systemPrompt: String,
                transcript: String,
                temperature: Double = 0.1,
                maxTokens: Int? = nil,
                stream: Bool = true,
                zeroRetention: Bool = true) {
        self.model = modelID
        self.messages = [
            Message(role: "system", content: systemPrompt),
            Message(role: "user", content: transcript),
        ]
        self.temperature = temperature
        self.max_tokens = maxTokens ?? Self.maxTokens(forTranscript: transcript)
        self.stream = stream
        self.reasoning = Reasoning(enabled: false)
        self.provider = Provider(sort: "latency",
                                 data_collection: zeroRetention ? "deny" : "allow",
                                 zdr: zeroRetention)
    }

    public func jsonData() throws -> Data {
        try JSONEncoder().encode(self)
    }
}
