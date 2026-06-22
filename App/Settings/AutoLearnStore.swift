import Foundation
import VoicelyCore

/// Persists what Voicely has learned from your dictation: auto-applied vocabulary
/// terms, plus the terms/phrases you've dismissed so they're never re-suggested.
/// Stored as JSON under Application Support/Voicely/autolearn.json.
///
/// Thread-safe: the learn pass runs off the main thread (after each dictation),
/// while Settings reads/writes on the main thread. All payload access goes through
/// a private serial queue; the heavy pure computation runs outside the lock.
final class AutoLearnStore {
    static let shared = AutoLearnStore()

    private struct Payload: Codable {
        var learnedTerms: [String] = []
        var dismissedTerms: [String] = []      // lowercased
        var dismissedSnippets: [String] = []   // lowercased phrase keys
    }

    private let fileURL: URL
    private let queue = DispatchQueue(label: "ink.voicely.autolearn")
    private var payload = Payload()
    private static let maxLearned = 60

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Voicely", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("autolearn.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Payload.self, from: data) {
            payload = decoded
        }
    }

    /// Must be called on `queue`.
    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: Vocabulary

    /// Auto-applied learned terms, as vocabulary entries for the cleanup prompt.
    var learnedEntries: [VocabularyEntry] {
        queue.sync { payload.learnedTerms.map { VocabularyEntry(term: $0) } }
    }

    var learnedTerms: [String] {
        queue.sync { payload.learnedTerms }
    }

    /// Recompute learned vocabulary from history and merge (memory: never forgets a
    /// term just because it rolled off the capped history). Returns the terms added.
    /// Safe to call from a background thread.
    @discardableResult
    func refreshVocabulary(history: [String], manual: [VocabularyEntry]) -> [String] {
        let dismissedSnapshot = queue.sync { Set(payload.dismissedTerms) }
        // Heavy pure work outside the lock.
        let found = AutoLearn.vocabularyTerms(from: history,
                                              existing: manual,
                                              dismissed: dismissedSnapshot)
            .map(\.term)
        let manualKeys = Set(manual.flatMap { [$0.term.lowercased()] + $0.variants.map { $0.lowercased() } })

        return queue.sync {
            let before = Set(payload.learnedTerms.map { $0.lowercased() })
            var merged = payload.learnedTerms
            var added: [String] = []
            for term in found where !before.contains(term.lowercased())
                && !dismissedSnapshot.contains(term.lowercased()) {
                merged.append(term)
                added.append(term)
            }
            // Drop anything the user has since added to manual vocabulary (avoid dupes).
            merged.removeAll { manualKeys.contains($0.lowercased()) }
            // Bound the list so it never bloats the cleanup prompt (keep newest).
            if merged.count > Self.maxLearned {
                merged = Array(merged.suffix(Self.maxLearned))
            }
            if merged != payload.learnedTerms {
                payload.learnedTerms = merged
                persistLocked()
            }
            return added
        }
    }

    /// Forget a learned term and never suggest it again.
    func removeLearnedTerm(_ term: String) {
        queue.sync {
            payload.learnedTerms.removeAll { $0.lowercased() == term.lowercased() }
            if !payload.dismissedTerms.contains(term.lowercased()) {
                payload.dismissedTerms.append(term.lowercased())
            }
            persistLocked()
        }
    }

    func clearLearnedVocabulary() {
        queue.sync {
            payload.learnedTerms = []
            persistLocked()
        }
    }

    // MARK: Snippets

    /// Repeated phrases worth turning into snippets (computed on demand, not stored).
    func snippetSuggestions(history: [String], manual: [Snippet]) -> [SnippetSuggestion] {
        let dismissedSnapshot = queue.sync { Set(payload.dismissedSnippets) }
        return AutoLearn.snippetSuggestions(from: history, existing: manual, dismissed: dismissedSnapshot)
    }

    /// Never suggest this phrase again (called on accept-commit or dismiss).
    func dismissSnippet(phrase: String) {
        let key = phrase.lowercased()
        queue.sync {
            if !payload.dismissedSnippets.contains(key) {
                payload.dismissedSnippets.append(key)
                persistLocked()
            }
        }
    }
}
