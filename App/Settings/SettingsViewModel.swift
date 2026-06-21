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
    @Published var apiKey: String
    @Published var launchAtLogin: Bool
    @Published var vocabularyText: String

    private let settings = SettingsStore.shared

    init() {
        hotKeyCode = settings.hotKeyCode
        transcriptionModelID = settings.transcriptionModelID
        cleanupEnabled = settings.cleanupEnabled
        cleanupModelID = settings.cleanupModelID
        zeroRetention = settings.zeroRetention
        apiKey = KeychainStore.openRouterKey() ?? ""
        launchAtLogin = LaunchAtLogin.isEnabled
        vocabularyText = SettingsViewModel.render(VocabularyStore.shared.entries)
    }

    func save() {
        settings.hotKeyCode = hotKeyCode
        settings.transcriptionModelID = transcriptionModelID
        settings.cleanupEnabled = cleanupEnabled
        settings.cleanupModelID = cleanupModelID
        settings.zeroRetention = zeroRetention
        KeychainStore.setOpenRouterKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
        LaunchAtLogin.setEnabled(launchAtLogin)
        VocabularyStore.shared.save(SettingsViewModel.parse(vocabularyText))
        NotificationCenter.default.post(name: .voicelySettingsChanged, object: nil)
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
