import Foundation
import VoicelyCore

enum CleanupError: Error {
    case noAPIKey
    case badResponse(Int)
    case malformed
}

/// Sends the raw transcript to OpenRouter for cleanup using the VoicelyCore
/// request builder + prompt. Non-streaming for v1 (streaming paste is a later
/// enhancement). Errors propagate so the Pipeline falls back to the raw text.
final class CleanupService {
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    func clean(_ raw: String,
               modelID: String,
               vocabulary: [VocabularyEntry],
               zeroRetention: Bool) async throws -> String {
        guard let apiKey = KeychainStore.openRouterKey(), !apiKey.isEmpty else {
            throw CleanupError.noAPIKey
        }

        let body = CleanupRequest(modelID: modelID,
                                  systemPrompt: CleanupPrompt.system(vocabulary: vocabulary),
                                  transcript: raw,
                                  stream: false,
                                  zeroRetention: zeroRetention)

        var request = URLRequest(url: endpoint)
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
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else { throw CleanupError.malformed }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
