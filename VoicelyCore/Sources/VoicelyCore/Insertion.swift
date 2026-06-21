import Foundation

/// How transcribed text gets into the focused app. The chain always ends in
/// `copyOnly` so a transcript is never lost (research §3): worst case, it's on
/// the clipboard and the user presses ⌘V.
public enum InsertMethod: Equatable { case accessibility, paste, copyOnly }

public enum InsertOutcome: Equatable {
    case inserted(InsertMethod)
    case copiedOnly
}

public enum InsertPlan {
    /// Ordered methods to attempt. `axFirst` adds an Accessibility attempt before
    /// the universal clipboard paste; both always fall back to copy-only.
    public static func methods(axFirst: Bool) -> [InsertMethod] {
        axFirst ? [.accessibility, .paste, .copyOnly] : [.paste, .copyOnly]
    }

    /// Walk the plan, trying each method via `attempt` until one succeeds.
    /// `copyOnly` is the guaranteed terminal outcome (it cannot fail).
    public static func resolve(_ plan: [InsertMethod], attempt: (InsertMethod) -> Bool) -> InsertOutcome {
        for method in plan {
            if method == .copyOnly { return .copiedOnly }
            if attempt(method) { return .inserted(method) }
        }
        return .copiedOnly
    }
}
