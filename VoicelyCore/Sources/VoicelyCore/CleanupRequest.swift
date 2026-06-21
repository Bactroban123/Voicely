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

    public init(modelID: String,
                systemPrompt: String,
                transcript: String,
                temperature: Double = 0.1,
                maxTokens: Int = 400,
                stream: Bool = true,
                zeroRetention: Bool = true) {
        self.model = modelID
        self.messages = [
            Message(role: "system", content: systemPrompt),
            Message(role: "user", content: transcript),
        ]
        self.temperature = temperature
        self.max_tokens = maxTokens
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
