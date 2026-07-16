import Foundation
import os

/// Central logging facade: every message goes to the unified log (Console.app,
/// `log stream --predicate 'subsystem == "com.voicely.app"'`) AND the on-disk
/// mirror in ~/Library/Logs/Voicely so field issues stay diagnosable after a
/// crash or relaunch.
///
/// Convention: messages are metadata only — durations, counts, error
/// descriptions, state names. Never log transcript content (the product
/// promise is that dictated text stays private).
enum VoicelyLog {
    static let recording = Channel(category: "recording")
    static let hotkey    = Channel(category: "hotkey")
    static let insertion = Channel(category: "insertion")
    static let cleanup   = Channel(category: "cleanup")
    static let settings  = Channel(category: "settings")
    static let lifecycle = Channel(category: "lifecycle")
    static let meeting   = Channel(category: "meeting")

    struct Channel {
        let category: String
        private let logger: Logger

        init(category: String) {
            self.category = category
            self.logger = Logger(subsystem: "com.voicely.app", category: category)
        }

        func info(_ message: String) {
            logger.info("\(message, privacy: .public)")
            FileLogMirror.shared.append(category: category, level: "INFO", message: message)
        }

        func warning(_ message: String) {
            logger.warning("\(message, privacy: .public)")
            FileLogMirror.shared.append(category: category, level: "WARN", message: message)
        }

        func error(_ message: String) {
            logger.error("\(message, privacy: .public)")
            FileLogMirror.shared.append(category: category, level: "ERROR", message: message)
        }
    }
}
