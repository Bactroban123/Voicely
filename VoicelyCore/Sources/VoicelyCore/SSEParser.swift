import Foundation

/// Pure parsing of OpenRouter/OpenAI server-sent-event stream lines into text
/// deltas, so the streaming cleanup can be assembled and (later) pasted as it
/// arrives. The network transport is OS-bound; extracting the delta is not.
public enum SSE {
    /// Returns the text delta from a single `data:` line, or nil for the
    /// terminal `[DONE]` marker, comments, keep-alives, or lines without content.
    public static func delta(fromDataLine line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" || payload.isEmpty { return nil }
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let delta = first["delta"] as? [String: Any],
              let content = delta["content"] as? String
        else { return nil }
        return content
    }

    /// Convenience: fold a batch of raw SSE lines into the accumulated text.
    public static func assemble(_ lines: [String]) -> String {
        lines.compactMap { delta(fromDataLine: $0) }.joined()
    }
}
