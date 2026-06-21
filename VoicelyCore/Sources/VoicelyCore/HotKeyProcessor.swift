import Foundation

/// A keyboard event, normalized away from any OS API so the activation logic
/// can be reasoned about and tested in isolation. The live app feeds these from
/// a CGEventTap; tests feed them by hand.
public enum KeyPhase: Equatable { case down, up }

public struct KeyEvent: Equatable {
    public let keyCode: UInt16
    public let phase: KeyPhase
    public let timestamp: TimeInterval
    public let isRepeat: Bool
    public init(keyCode: UInt16, phase: KeyPhase, timestamp: TimeInterval, isRepeat: Bool = false) {
        self.keyCode = keyCode
        self.phase = phase
        self.timestamp = timestamp
        self.isRepeat = isRepeat
    }
}

/// What the processor wants the app to do. `nil` means "no change".
public enum HotKeyOutput: Equatable { case startRecording, stopRecording, cancel }

public struct HotKeyConfig: Equatable {
    public var hotKeyCode: UInt16
    public var cancelKeyCode: UInt16
    /// Press shorter than this is a tap (toggle); longer is a hold (push-to-talk).
    public var tapThreshold: TimeInterval
    public init(hotKeyCode: UInt16, cancelKeyCode: UInt16 = 53, tapThreshold: TimeInterval = 0.25) {
        self.hotKeyCode = hotKeyCode
        self.cancelKeyCode = cancelKeyCode
        self.tapThreshold = tapThreshold
    }
}

/// Pure state machine for one-key dictation activation.
///
/// - Recording starts immediately on key-down (so a hold has zero perceived lag).
/// - On key-up we decide what the press *was*: a quick tap locks recording on
///   (toggle); a longer hold stops it (push-to-talk released).
/// - While locked, the next press of the hotkey stops recording.
/// - Esc cancels (discard) whenever recording.
public struct HotKeyProcessor {
    public enum Mode: Equatable { case idle, holding, lockedRecording }
    public private(set) var mode: Mode = .idle

    private let config: HotKeyConfig
    private var keyDownAt: TimeInterval?

    public init(config: HotKeyConfig) { self.config = config }

    public mutating func process(_ event: KeyEvent) -> HotKeyOutput? {
        if event.isRepeat { return nil }

        // Cancel only matters while we are recording.
        if event.keyCode == config.cancelKeyCode, event.phase == .down {
            guard mode == .holding || mode == .lockedRecording else { return nil }
            mode = .idle
            keyDownAt = nil
            return .cancel
        }

        guard event.keyCode == config.hotKeyCode else { return nil }

        switch mode {
        case .idle:
            guard event.phase == .down else { return nil }
            mode = .holding
            keyDownAt = event.timestamp
            return .startRecording

        case .holding:
            guard event.phase == .up else { return nil }
            let dt = event.timestamp - (keyDownAt ?? event.timestamp)
            keyDownAt = nil
            if dt < config.tapThreshold {
                mode = .lockedRecording   // tap: keep recording (toggle on)
                return nil
            } else {
                mode = .idle              // hold: stop on release
                return .stopRecording
            }

        case .lockedRecording:
            guard event.phase == .down else { return nil }
            mode = .idle                  // next press stops
            keyDownAt = nil
            return .stopRecording
        }
    }
}
