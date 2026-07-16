import Foundation

/// Decides how to respond when macOS disables the global event tap.
///
/// The tap is always re-enabled immediately — the failure this exists to
/// prevent is the hotkey silently dying until relaunch. But repeated disables
/// mean self-healing isn't keeping up, and the user deserves to know rather
/// than think the app is dead. Pure so the windowing rule is actually testable
/// (it lives on the untestable App-target tap callback otherwise).
public struct TapDisableTracker {
    public enum Response: Equatable {
        /// Re-enable and carry on; no user-visible notice.
        case recovered
        /// Re-enable, and tell the user once for this burst.
        case recoveredUnreliable
    }

    private let window: TimeInterval
    private let threshold: Int
    private var recent: [TimeInterval] = []
    /// Latch: one notice per burst, not one per disable.
    private var noticedThisBurst = false

    /// How many disables happened inside the current window.
    public var recentCount: Int { recent.count }

    public init(window: TimeInterval = 60, threshold: Int = 3) {
        self.window = window
        self.threshold = threshold
    }

    public mutating func record(at now: TimeInterval) -> Response {
        recent.append(now)
        recent.removeAll { now - $0 > window }

        guard recent.count >= threshold else {
            noticedThisBurst = false // burst subsided; a future one may notify again
            return .recovered
        }
        guard !noticedThisBurst else { return .recovered }
        noticedThisBurst = true
        return .recoveredUnreliable
    }

    /// Forget history (e.g. the tap was torn down and rebuilt).
    public mutating func reset() {
        recent.removeAll()
        noticedThisBurst = false
    }
}
