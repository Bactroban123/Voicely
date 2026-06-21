import Foundation
import VoicelyCore

/// Persists the custom vocabulary as JSON under Application Support/Voicely.
final class VocabularyStore {
    static let shared = VocabularyStore()
    private let fileURL: URL
    private(set) var entries: [VocabularyEntry] = []

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Voicely", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("vocabulary.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        entries = (try? JSONDecoder().decode([VocabularyEntry].self, from: data)) ?? []
    }

    func save(_ newEntries: [VocabularyEntry]) {
        entries = newEntries
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
