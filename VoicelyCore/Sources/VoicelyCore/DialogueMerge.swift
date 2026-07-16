import Foundation

/// Weaves the two independently-transcribed tracks into one readable dialogue.
///
/// This is where the two-track capture pays off: each track is transcribed on
/// its own (so neither engine ever hears a mix of voices), and speaker
/// attribution is already known from which track a segment came out of. All
/// that's left is ordering by time and tidying — no diarization, no clustering.
///
/// Pure and deterministic so it can be tested without audio, an engine, or a
/// meeting.
public enum DialogueMerge {
    /// Segments closer than this to the previous one from the same speaker are
    /// joined. ASR emits per-token or per-VAD-chunk pieces, so without this a
    /// transcript reads as one line per breath.
    public static let defaultCoalesceGap: TimeInterval = 1.5

    /// Merge mic ("me") and system ("them") segments into a single ordered
    /// dialogue.
    ///
    /// - Ordering is by start time; ties put `me` first purely for determinism
    ///   (an arbitrary but stable choice beats a nondeterministic transcript).
    /// - Overlapping speech is preserved as separate consecutive lines rather
    ///   than interleaved word-by-word: people do talk over each other, and a
    ///   readable approximation beats a mangled interleave.
    /// - Empty and whitespace-only segments are dropped; ASR emits them for
    ///   silence and they'd otherwise become blank dialogue lines.
    public static func merge(me: [TranscriptSegment],
                             them: [TranscriptSegment],
                             coalesceGap: TimeInterval = defaultCoalesceGap) -> [TranscriptSegment] {
        let all = (me + them)
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                if lhs.speaker != rhs.speaker { return lhs.speaker == .me }
                return lhs.end < rhs.end
            }
        return coalesce(all, gap: coalesceGap)
    }

    /// Join runs of same-speaker segments separated by less than `gap`.
    /// Assumes `segments` is already sorted by start time.
    public static func coalesce(_ segments: [TranscriptSegment],
                                gap: TimeInterval = defaultCoalesceGap) -> [TranscriptSegment] {
        var result: [TranscriptSegment] = []
        for segment in segments {
            let clean = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }

            if let last = result.last, last.adjoins(segment, within: gap) {
                result[result.count - 1] = TranscriptSegment(
                    speaker: last.speaker,
                    text: last.text + " " + clean,
                    start: last.start,
                    // A later segment can end before the previous one does when
                    // ASR windows overlap; never let the end time go backwards.
                    end: max(last.end, segment.end))
            } else {
                result.append(TranscriptSegment(speaker: segment.speaker, text: clean,
                                                start: segment.start, end: segment.end))
            }
        }
        return result
    }

    /// Renders the dialogue for display and for the Markdown export.
    /// `**Me:** …` per line — readable as plain text, and valid Markdown.
    public static func render(_ segments: [TranscriptSegment], includeTimestamps: Bool = false) -> String {
        segments.map { segment in
            let prefix = includeTimestamps ? "[\(timestamp(segment.start))] " : ""
            return "\(prefix)**\(segment.speaker.label):** \(segment.text)"
        }.joined(separator: "\n\n")
    }

    /// `m:ss` under an hour, `h:mm:ss` beyond it.
    public static func timestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
