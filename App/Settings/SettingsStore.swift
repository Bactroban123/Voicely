import Foundation
import VoicelyCore

extension Notification.Name {
    /// Posted when settings are saved so the controller can reconfigure live.
    static let voicelySettingsChanged = Notification.Name("VoicelySettingsChanged")
}

/// Small UserDefaults-backed preferences. Secrets (the OpenRouter key) live in
/// the Keychain, not here. Custom vocabulary lives in a JSON file.
final class SettingsStore {
    static let shared = SettingsStore()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let hotKeyCode = "hotKeyCode"
        static let cleanupEnabled = "cleanupEnabled"
        static let transcriptionModelID = "transcriptionModelID"
        static let cleanupModelID = "cleanupModelID"
        static let cleanupModeID = "cleanupModeID"
        static let zeroRetention = "zeroRetention"
    }

    var cleanupModeID: String {
        get { defaults.string(forKey: Key.cleanupModeID) ?? CleanupModes.defaultID }
        set { defaults.set(newValue, forKey: Key.cleanupModeID) }
    }

    var hotKeyCode: Int {
        get { defaults.object(forKey: Key.hotKeyCode) as? Int ?? 61 } // Right Option
        set { defaults.set(newValue, forKey: Key.hotKeyCode) }
    }

    /// Off by default so the app dictates raw text until a key is added.
    var cleanupEnabled: Bool {
        get { defaults.object(forKey: Key.cleanupEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.cleanupEnabled) }
    }

    var transcriptionModelID: String {
        get { defaults.string(forKey: Key.transcriptionModelID) ?? ModelCatalog.defaultTranscriptionID }
        set { defaults.set(newValue, forKey: Key.transcriptionModelID) }
    }

    var cleanupModelID: String {
        get { defaults.string(forKey: Key.cleanupModelID) ?? ModelCatalog.defaultCleanupID }
        set { defaults.set(newValue, forKey: Key.cleanupModelID) }
    }

    var zeroRetention: Bool {
        get { defaults.object(forKey: Key.zeroRetention) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.zeroRetention) }
    }
}
