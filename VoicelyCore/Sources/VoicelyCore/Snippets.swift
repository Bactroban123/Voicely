import Foundation

/// A voice-triggered text expansion: say the trigger phrase, get the expansion.
/// e.g. trigger "my email" → expansion "gal@example.com".
public struct Snippet: Codable, Equatable {
    public let trigger: String
    public let expansion: String
    public init(trigger: String, expansion: String) {
        self.trigger = trigger
        self.expansion = expansion
    }
}

/// Expands snippets inline within a transcript. Case-insensitive, whole-phrase
/// (word-boundary) matching. Longer triggers are applied first so they win over
/// shorter ones they contain.
public enum SnippetExpander {
    public static func expand(_ text: String, snippets: [Snippet]) -> String {
        var result = text
        for snippet in snippets.sorted(by: { $0.trigger.count > $1.trigger.count }) {
            let trigger = snippet.trigger.trimmingCharacters(in: .whitespaces)
            guard !trigger.isEmpty else { continue }
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: trigger) + "\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            let template = NSRegularExpression.escapedTemplate(for: snippet.expansion)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: template)
        }
        return result
    }
}
