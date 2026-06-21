import Foundation
import VoicelyCore

/// Persists the transcript history as JSON under Application Support/Voicely.
/// Newest first; capped; de-dupes immediate repeats (logic in VoicelyCore.History).
final class HistoryStore {
    static let shared = HistoryStore()
    private let fileURL: URL
    private(set) var entries: [HistoryEntry] = []

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Voicely", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        entries = (try? JSONDecoder().decode([HistoryEntry].self, from: data)) ?? []
    }

    func record(_ text: String) {
        entries = History.add(text, to: entries, now: Date())
        persist()
    }

    func clear() {
        entries = []
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
