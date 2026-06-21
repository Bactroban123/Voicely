import Foundation
import VoicelyCore

/// Persists voice-triggered snippets as JSON under Application Support/Voicely.
final class SnippetStore {
    static let shared = SnippetStore()
    private let fileURL: URL
    private(set) var snippets: [Snippet] = []

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Voicely", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("snippets.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        snippets = (try? JSONDecoder().decode([Snippet].self, from: data)) ?? []
    }

    func save(_ newSnippets: [Snippet]) {
        snippets = newSnippets
        guard let data = try? JSONEncoder().encode(snippets) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
