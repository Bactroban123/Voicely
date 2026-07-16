import Foundation
import VoicelyCore

enum CleanupError: Error {
    case noAPIKey
    case badResponse(Int)
    case malformed
    /// The model hit the token cap and stopped mid-output. The API still
    /// returns 200, so this must be detected explicitly or half a sentence
    /// gets pasted as if it were the finished text.
    case truncated
}

/// Sends the raw transcript to OpenRouter for cleanup using the VoicelyCore
/// request builder + prompt. Non-streaming for v1 (streaming paste is a later
/// enhancement). Errors propagate so the Pipeline falls back to the raw text.
final class CleanupService {
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    func clean(_ raw: String,
               modelID: String,
               modeID: String,
               vocabulary: [VocabularyEntry],
               zeroRetention: Bool) async throws -> String {
        guard let apiKey = KeychainStore.openRouterKey(), !apiKey.isEmpty else {
            throw CleanupError.noAPIKey
        }

        let body = CleanupRequest(modelID: modelID,
                                  systemPrompt: CleanupModes.system(modeID: modeID, vocabulary: vocabulary),
                                  transcript: raw,
                                  stream: false,
                                  zeroRetention: zeroRetention)

        var request = URLRequest(url: endpoint)
        // Without this the URLSession default (60s) applies: a hung connection
        // would hold the pipeline in .refining for a full minute, rejecting new
        // dictations the whole time. Cleanup is a sub-second call in practice;
        // past this we insert the raw transcript instead of stalling.
        request.timeoutInterval = 12
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://voicely.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Voicely", forHTTPHeaderField: "X-Title")
        request.httpBody = try body.jsonData()

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CleanupError.malformed }
        guard (200..<300).contains(http.statusCode) else { throw CleanupError.badResponse(http.statusCode) }

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let choice = choices.first,
              let message = choice["message"] as? [String: Any],
              let content = message["content"] as? String
        else { throw CleanupError.malformed }

        // A truncated completion is a 200 with finish_reason "length". Rather
        // than paste half a sentence, throw: the pipeline's designed fallback
        // inserts the raw transcript, so the dictation is never lost.
        if let finishReason = choice["finish_reason"] as? String, finishReason == "length" {
            throw CleanupError.truncated
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
