import Foundation

/// Turns a model's response into a `MeetingSummary`.
///
/// JSON mode is requested, but never trusted: providers honour it unevenly, and
/// a model that wraps its object in ```json fences or adds "Here are your
/// notes:" is not a rare event. So the contract is enforced here, and failure
/// degrades visibly (`parseDegraded`) rather than silently producing empty
/// notes that look like a quiet meeting.
public enum MeetingSummaryParsing {
    public enum ParseOutcome: Equatable {
        /// Parsed cleanly.
        case parsed(MeetingSummary)
        /// Unparseable — the caller should retry once with `retryInstruction`.
        case retryable
        /// Unparseable twice. The raw text is kept as the summary rather than
        /// thrown away: a wall of prose the user can read beats a blank page
        /// pretending the meeting had no content.
        case degraded(MeetingSummary)
    }

    /// Attempt a parse. `isFinalAttempt` decides whether a failure is retryable
    /// or degrades.
    public static func parse(_ response: String, isFinalAttempt: Bool = false) -> ParseOutcome {
        let cleaned = extractJSONObject(from: response)
        if let data = cleaned.data(using: .utf8),
           let summary = try? JSONDecoder().decode(MeetingSummary.self, from: data),
           !summary.isEmpty {
            return .parsed(summary)
        }
        guard isFinalAttempt else { return .retryable }

        let raw = response.trimmingCharacters(in: .whitespacesAndNewlines)
        return .degraded(MeetingSummary(summary: raw, parseDegraded: true))
    }

    /// Pulls the JSON object out of a response that may be fenced, prefixed with
    /// chat ("Sure! Here are the notes:"), or both.
    ///
    /// Braces are matched by depth rather than by first/last, and brace-like
    /// characters inside strings are ignored — a transcript quoting "{" would
    /// otherwise truncate the object at the wrong place.
    public static func extractJSONObject(from response: String) -> String {
        let trimmed = stripFences(response)
        guard let start = trimmed.firstIndex(of: "{") else { return trimmed }

        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < trimmed.endIndex {
            let character = trimmed[index]
            if escaped {
                escaped = false
            } else if character == "\\", inString {
                escaped = true
            } else if character == "\"" {
                inString.toggle()
            } else if !inString {
                if character == "{" { depth += 1 }
                if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(trimmed[start...index])
                    }
                }
            }
            index = trimmed.index(after: index)
        }
        return String(trimmed[start...])   // unbalanced; let the decoder reject it
    }

    /// Removes ```json … ``` fences, which several providers add despite JSON mode.
    private static func stripFences(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.hasPrefix("```") else { return result }
        if let firstNewline = result.firstIndex(of: "\n") {
            result = String(result[result.index(after: firstNewline)...])
        }
        if let fenceRange = result.range(of: "```", options: .backwards) {
            result = String(result[..<fenceRange.lowerBound])
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
