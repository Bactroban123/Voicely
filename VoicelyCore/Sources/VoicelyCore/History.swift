import Foundation

/// One past dictation, for the transcript history.
public struct HistoryEntry: Codable, Equatable, Identifiable {
    public let id: String
    public let text: String
    public let date: Date
    public init(id: String = UUID().uuidString, text: String, date: Date) {
        self.id = id
        self.text = text
        self.date = date
    }
}

/// Pure operations over the transcript history (newest first). The store + UI live
/// in the app; this is the tested logic.
public enum History {
    public static let defaultCap = 200

    /// Prepend a new transcript. Trims it, ignores empties, de-dupes an immediate
    /// repeat of the most recent entry, and caps the list length.
    public static func add(_ text: String,
                           to list: [HistoryEntry],
                           now: Date,
                           cap: Int = defaultCap) -> [HistoryEntry] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return list }
        if let first = list.first, first.text == trimmed { return list }
        var result = list
        result.insert(HistoryEntry(text: trimmed, date: now), at: 0)
        if result.count > cap {
            result = Array(result.prefix(cap))
        }
        return result
    }

    /// Case-insensitive substring filter. Empty query returns the whole list.
    public static func search(_ query: String, in list: [HistoryEntry]) -> [HistoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return list }
        return list.filter { $0.text.lowercased().contains(q) }
    }

    /// A short, single-line preview for menus.
    public static func preview(_ text: String, max: Int = 48) -> String {
        let oneLine = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if oneLine.count <= max { return oneLine }
        return String(oneLine.prefix(max - 1)) + "…"
    }
}
