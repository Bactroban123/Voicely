import Foundation

/// The OpenRouter request body for meeting summarization.
///
/// Mirrors `CleanupRequest`'s privacy posture exactly — latency-first routing,
/// zero data retention on by default — but is a separate type on purpose:
/// dictation's `max_tokens` is sized for one spoken sentence, and quietly
/// widening it there would change every dictation's routing and cost to serve a
/// feature that isn't dictation.
public struct MeetingSummaryRequest: Codable, Equatable {
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
    public struct ResponseFormat: Codable, Equatable {
        public let type: String
    }

    public let model: String
    public let messages: [Message]
    public let temperature: Double
    public let max_tokens: Int
    public let stream: Bool
    public let reasoning: Reasoning
    public let provider: Provider
    public let response_format: ResponseFormat?

    /// Notes are far shorter than the transcript they come from, so the budget
    /// is sized to the OUTPUT, not the input.
    ///
    /// The ceiling is about routing, not cost (`max_tokens` bills on tokens
    /// generated, not reserved): OpenRouter only routes to providers that can
    /// return the requested length, so a bigger number quietly shrinks the pool.
    /// 4096 keeps every catalog model eligible while being far more than any
    /// realistic set of meeting notes needs.
    public static let defaultMaxTokens = 4_096
    /// The map step returns compact bullets for one slice.
    public static let mapMaxTokens = 1_024

    public init(modelID: String,
                systemPrompt: String,
                content: String,
                temperature: Double = 0.2,
                maxTokens: Int = defaultMaxTokens,
                requireJSON: Bool = true,
                zeroRetention: Bool = true) {
        self.model = modelID
        self.messages = [
            Message(role: "system", content: systemPrompt),
            Message(role: "user", content: content),
        ]
        // Slightly above dictation's 0.1: notes need to generalise a little,
        // but not enough to start inventing.
        self.temperature = temperature
        self.max_tokens = maxTokens
        // Non-streaming: nothing renders these token-by-token, and the parser
        // needs the whole object anyway.
        self.stream = false
        self.reasoning = Reasoning(enabled: false)
        self.provider = Provider(sort: "latency",
                                 data_collection: zeroRetention ? "deny" : "allow",
                                 zdr: zeroRetention)
        self.response_format = requireJSON ? ResponseFormat(type: "json_object") : nil
    }

    public func jsonData() throws -> Data {
        try JSONEncoder().encode(self)
    }
}

/// Decides whether a transcript goes in one call or needs map-reduce.
public enum MeetingSummaryPlan: Equatable {
    /// The whole transcript in one call.
    case single(String)
    /// Ordered slices to condense separately, then fold together.
    case mapReduce([String])

    /// Above this many characters, split. Every catalog model's context window
    /// swallows a 2-hour meeting (~12-18k words) whole, so single-shot is the
    /// common case and map-reduce is the exception — which is the right way
    /// round, because map-reduce loses detail at the seams.
    public static let singleShotLimit = 60_000
    /// Slice size when splitting, with overlap so a sentence spanning a seam
    /// isn't lost from both sides.
    public static let sliceLength = 12_000
    public static let sliceOverlap = 500

    public static func plan(for transcript: String) -> MeetingSummaryPlan {
        guard transcript.count > singleShotLimit else { return .single(transcript) }
        return .mapReduce(slice(transcript))
    }

    /// Splits on paragraph boundaries where possible so slices don't start
    /// mid-sentence.
    static func slice(_ transcript: String) -> [String] {
        var slices: [String] = []
        var start = transcript.startIndex
        while start < transcript.endIndex {
            let hardEnd = transcript.index(start, offsetBy: sliceLength, limitedBy: transcript.endIndex)
                ?? transcript.endIndex
            var end = hardEnd
            if hardEnd < transcript.endIndex {
                // Prefer a paragraph break in the last 20% of the slice.
                let searchStart = transcript.index(hardEnd, offsetBy: -sliceLength / 5, limitedBy: start) ?? start
                if let breakRange = transcript.range(of: "\n\n", options: .backwards,
                                                     range: searchStart..<hardEnd) {
                    end = breakRange.upperBound
                }
            }
            slices.append(String(transcript[start..<end]))
            if end >= transcript.endIndex { break }
            start = transcript.index(end, offsetBy: -sliceOverlap, limitedBy: start) ?? end
            if start == end && end < transcript.endIndex { start = end }
        }
        return slices
    }
}
