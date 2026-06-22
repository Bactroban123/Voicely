import Foundation
import VoicelyCore

/// Bridges the SwiftUI settings form to the stores (UserDefaults, Keychain, JSON).
/// Vocabulary is edited as text: one entry per line, optional misheard variants
/// after a colon ("Collabo: colab, kollabo").
final class SettingsViewModel: ObservableObject {
    @Published var hotKeyCode: Int
    @Published var transcriptionModelID: String
    @Published var cleanupEnabled: Bool
    @Published var cleanupModelID: String
    @Published var zeroRetention: Bool
    @Published var cleanupModeID: String
    @Published var apiKey: String
    @Published var launchAtLogin: Bool
    @Published var vocabularyText: String
    @Published var snippetsText: String

    // Self-learning
    @Published var autoLearnEnabled: Bool
    @Published var learnedTerms: [String]
    @Published var snippetSuggestions: [SnippetSuggestion]

    private let settings = SettingsStore.shared

    init() {
        hotKeyCode = settings.hotKeyCode
        transcriptionModelID = settings.transcriptionModelID
        cleanupEnabled = settings.cleanupEnabled
        cleanupModelID = settings.cleanupModelID
        cleanupModeID = settings.cleanupModeID
        zeroRetention = settings.zeroRetention
        apiKey = KeychainStore.openRouterKey() ?? ""
        launchAtLogin = LaunchAtLogin.isEnabled
        vocabularyText = SettingsViewModel.render(VocabularyStore.shared.entries)
        snippetsText = SettingsViewModel.renderSnippets(SnippetStore.shared.snippets)
        autoLearnEnabled = settings.autoLearnEnabled
        learnedTerms = []
        snippetSuggestions = []
        refreshLearning()
    }

    /// Phrases the user accepted this session; their "don't suggest again" flag is
    /// only committed on save() so closing without saving discards them cleanly.
    private var pendingSnippetDismissals: [String] = []

    /// Recompute what's been learned + fresh snippet suggestions from history.
    /// Gates on the live (in-memory) toggle, not the persisted store, so flipping
    /// the switch updates the view before Done is pressed.
    func refreshLearning() {
        guard autoLearnEnabled else {
            learnedTerms = []
            snippetSuggestions = []
            return
        }
        let history = HistoryStore.shared.entries.map(\.text)
        AutoLearnStore.shared.refreshVocabulary(history: history, manual: VocabularyStore.shared.entries)
        learnedTerms = AutoLearnStore.shared.learnedTerms
        snippetSuggestions = AutoLearnStore.shared.snippetSuggestions(
            history: history, manual: SnippetStore.shared.snippets)
    }

    /// Forget an auto-learned term (and never re-learn it).
    func removeLearnedTerm(_ term: String) {
        AutoLearnStore.shared.removeLearnedTerm(term)
        learnedTerms = AutoLearnStore.shared.learnedTerms
    }

    /// Turn a suggested phrase into a real snippet (added to the editable buffer).
    /// The "don't suggest again" flag is deferred to save() so it only sticks if
    /// the snippet itself is saved — closing without Done discards both together.
    func acceptSnippet(_ suggestion: SnippetSuggestion, trigger: String) {
        let t = trigger.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let line = "\(t) => \(suggestion.phrase)"
        snippetsText = snippetsText.isEmpty ? line : snippetsText + "\n" + line
        pendingSnippetDismissals.append(suggestion.phrase)
        snippetSuggestions.removeAll { $0.phrase == suggestion.phrase }
    }

    func dismissSnippet(_ suggestion: SnippetSuggestion) {
        AutoLearnStore.shared.dismissSnippet(phrase: suggestion.phrase)
        snippetSuggestions.removeAll { $0.phrase == suggestion.phrase }
    }

    func save() {
        settings.hotKeyCode = hotKeyCode
        settings.transcriptionModelID = transcriptionModelID
        settings.cleanupEnabled = cleanupEnabled
        settings.cleanupModelID = cleanupModelID
        settings.cleanupModeID = cleanupModeID
        settings.zeroRetention = zeroRetention
        settings.autoLearnEnabled = autoLearnEnabled
        KeychainStore.setOpenRouterKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
        LaunchAtLogin.setEnabled(launchAtLogin)
        let manual = SettingsViewModel.parse(vocabularyText)
        VocabularyStore.shared.save(manual)
        SnippetStore.shared.save(SettingsViewModel.parseSnippets(snippetsText))

        // Commit accepted-snippet dismissals now that the snippets are saved.
        for phrase in pendingSnippetDismissals {
            AutoLearnStore.shared.dismissSnippet(phrase: phrase)
        }
        pendingSnippetDismissals = []

        // Reconcile learned vocabulary against the freshly-saved manual list so a
        // term promoted to the manual list isn't also sent as a learned duplicate.
        if autoLearnEnabled {
            AutoLearnStore.shared.refreshVocabulary(
                history: HistoryStore.shared.entries.map(\.text), manual: manual)
        }

        NotificationCenter.default.post(name: .voicelySettingsChanged, object: nil)
    }

    private static func renderSnippets(_ snippets: [Snippet]) -> String {
        snippets.map { "\($0.trigger) => \($0.expansion)" }.joined(separator: "\n")
    }

    private static func parseSnippets(_ text: String) -> [Snippet] {
        text.split(separator: "\n").compactMap { line in
            guard let sep = line.range(of: "=>") else { return nil }
            let trigger = line[..<sep.lowerBound].trimmingCharacters(in: .whitespaces)
            let expansion = line[sep.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !trigger.isEmpty, !expansion.isEmpty else { return nil }
            return Snippet(trigger: trigger, expansion: expansion)
        }
    }

    private static func render(_ entries: [VocabularyEntry]) -> String {
        entries.map { entry in
            entry.variants.isEmpty ? entry.term : "\(entry.term): \(entry.variants.joined(separator: ", "))"
        }.joined(separator: "\n")
    }

    private static func parse(_ text: String) -> [VocabularyEntry] {
        text.split(separator: "\n").compactMap { line in
            let raw = line.trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { return nil }
            guard let colon = raw.firstIndex(of: ":") else {
                return VocabularyEntry(term: raw)
            }
            let term = String(raw[..<colon]).trimmingCharacters(in: .whitespaces)
            guard !term.isEmpty else { return nil }
            let variants = String(raw[raw.index(after: colon)...])
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return VocabularyEntry(term: term, variants: variants)
        }
    }
}
