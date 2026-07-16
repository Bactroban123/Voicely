import Foundation

/// Renders a meeting as Markdown.
///
/// Plain Markdown on purpose, with no Obsidian-specific syntax: YAML
/// frontmatter becomes Obsidian properties, `- [ ]` becomes checkable tasks,
/// and the same file is still readable in any editor, on GitHub, or pasted into
/// a message. Coupling the export to one app would be a worse file for
/// everyone, including that app's users.
///
/// Pure so the exact bytes can be pinned by a test — an export that silently
/// drops the tasks or mangles the frontmatter is the kind of thing nobody
/// notices until they need the file.
public enum MeetingMarkdownExporter {
    public static func export(meeting: Meeting,
                              summary: MeetingSummary?,
                              transcript: [TranscriptSegment]) -> String {
        var out = frontmatter(for: meeting)
        out += "\n# \(meeting.title)\n"

        if !meeting.capturedSystemAudio {
            // The file has to explain itself: a one-sided transcript with no
            // note reads like the transcription failed.
            out += "\n> Only the microphone was captured for this meeting — "
            out += "the other side of the call isn't in this transcript.\n"
        }

        if let summary, !summary.summary.isEmpty {
            out += "\n## Summary\n\n\(summary.summary)\n"
        }
        if let summary, summary.parseDegraded {
            out += "\n> These notes couldn't be structured automatically; the text above is the model's raw reply.\n"
        }

        if let summary {
            out += section("Key points", summary.keyPoints)
            out += section("Decisions", summary.decisions)

            if !summary.actionItems.isEmpty {
                out += "\n## Action items\n\n"
                for item in summary.actionItems {
                    var line = "- [ ] \(item.title)"
                    // Only rendered when the transcript actually said them.
                    let details = [item.owner.map { "Owner: \($0)" }, item.due.map { "Due: \($0)" }]
                        .compactMap { $0 }
                    if !details.isEmpty { line += " (\(details.joined(separator: ", ")))" }
                    out += line + "\n"
                }
            }

            out += section("Follow-ups", summary.followups)
        }

        if !transcript.isEmpty {
            out += "\n## Transcript\n\n"
            out += transcript.map { segment in
                "**\(segment.speaker.label)** (\(DialogueMerge.timestamp(segment.start))): \(segment.text)"
            }.joined(separator: "\n\n")
            out += "\n"
        }
        return out
    }

    /// A filename that sorts chronologically and survives every filesystem:
    /// "2026-07-16 Weekly sync.md".
    public static func filename(for meeting: Meeting) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Local date on purpose: people look for "the meeting I had on Tuesday",
        // which is a local-calendar fact, not a UTC one.
        let date = formatter.string(from: meeting.startedAt)
        // Drop the illegal characters' empty remnants before joining, or a
        // title of "///" becomes "---" instead of falling back to "Meeting".
        let safeTitle = meeting.title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "\(date) \(safeTitle.isEmpty ? "Meeting" : safeTitle).md"
    }

    // MARK: - Pieces

    private static func frontmatter(for meeting: Meeting) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var out = "---\n"
        out += "title: \"\(escapeYAML(meeting.title))\"\n"
        out += "date: \(formatter.string(from: meeting.startedAt))\n"
        if meeting.duration > 0 {
            out += "duration_minutes: \(Int((meeting.duration / 60).rounded()))\n"
        }
        out += "tags: [meeting, voicely]\n"
        out += "---\n"
        return out
    }

    /// Quotes inside a double-quoted YAML scalar must be escaped, or the
    /// frontmatter silently stops parsing and the note loses its properties.
    private static func escapeYAML(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func section(_ title: String, _ items: [String]) -> String {
        guard !items.isEmpty else { return "" }
        return "\n## \(title)\n\n" + items.map { "- \($0)" }.joined(separator: "\n") + "\n"
    }
}
