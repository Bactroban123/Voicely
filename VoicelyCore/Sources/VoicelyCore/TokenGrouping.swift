import Foundation

/// One timed token as emitted by a speech engine, normalized away from any
/// engine's own type so the grouping logic can be tested without audio, a
/// model, or a meeting.
public struct TimedToken: Equatable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// Groups a stream of timed tokens into utterances.
///
/// Engines emit one timing per *token*, not per sentence — a segment per token
/// would render as one dialogue line per syllable. This splits on pauses
/// instead, and `DialogueMerge` does the final coalescing across the merged
/// tracks.
///
/// The joining rule is the subtle part, and it's why this lives here rather
/// than in the app: Parakeet's tokens **already carry their own leading
/// spaces** (`" He"`, `"y"`, `","`, `" can"`), so they are concatenated
/// verbatim. Trimming each token before joining — the obvious-looking thing —
/// silently welds every word together ("Hey,canyouhearme"), which compiles,
/// passes any test built from hand-made segments, and is only ever caught by
/// running real audio through it. It was, once.
public enum TokenGrouping {
    /// A pause longer than this ends the current utterance.
    ///
    /// `DialogueMerge` coalesces with the same value, deliberately. When this
    /// was smaller, every pause in the gap between the two thresholds was split
    /// here and rejoined there — and rejoining inserts a space where the token's
    /// own spacing was authoritative, rendering "Hey ," for a hesitation before
    /// punctuation. One threshold, applied once.
    public static let defaultUtteranceGap: TimeInterval = 1.5

    public static func segments(from tokens: [TimedToken],
                                speaker: Speaker,
                                gap: TimeInterval = defaultUtteranceGap) -> [TranscriptSegment] {
        guard let first = tokens.first else { return [] }

        var segments: [TranscriptSegment] = []
        var current = ""
        var start = first.start
        var end = first.end

        func flush() {
            let text = current.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            segments.append(TranscriptSegment(speaker: speaker, text: text, start: start, end: end))
        }

        for token in tokens {
            if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               token.start - end > gap {
                flush()
                current = ""
                start = token.start
            }
            current += token.text     // verbatim: tokens carry their own spacing
            end = max(end, token.end) // engine windows can overlap; never rewind
        }
        flush()
        return segments
    }
}
