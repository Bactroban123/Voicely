import AppKit
import VoicelyCore

/// Inserts text into the focused app using the policy from VoicelyCore.InsertPlan.
/// Default is clipboard paste-and-restore (universal); copy-only is the safety net
/// so a transcript is never lost. Accessibility direct-insert is a later phase.
/// Requires Accessibility permission to synthesize ⌘V.
final class TextInserter {
    /// Restore delay must outlast the paste landing in the target app.
    private let restoreDelay: TimeInterval = 0.25
    /// The pending clipboard restore, cancellable so a rapid second dictation
    /// doesn't get clobbered by the previous take's stale restore.
    private var pendingRestore: DispatchWorkItem?

    @discardableResult
    func insert(_ text: String, axFirst: Bool = false) -> InsertOutcome {
        guard !text.isEmpty else { return .copiedOnly }
        let plan = InsertPlan.methods(axFirst: axFirst)
        return InsertPlan.resolve(plan) { method in
            switch method {
            case .accessibility:
                return false   // TODO(Phase 5): AX kAXSelectedTextAttribute insert
            case .paste:
                return self.pasteViaClipboard(text)
            case .copyOnly:
                self.copyOnly(text)
                return true
            }
        }
    }

    private func copyOnly(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func pasteViaClipboard(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        let previous = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)
        let ourChangeCount = pb.changeCount // captured after our own write

        guard postCommandV() else {
            // Leave our text on the clipboard (copy-only) if we couldn't paste.
            return false
        }

        // A newer dictation's restore supersedes this one; without cancelling,
        // this stale restore would overwrite the newer take's clipboard.
        pendingRestore?.cancel()
        let restore = DispatchWorkItem {
            // changeCount only moves on a WRITE (pasting doesn't bump it), so
            // an unequal count means someone else owns the clipboard now —
            // leave it alone rather than stomping the user's own copy.
            guard pb.changeCount == ourChangeCount else { return }
            pb.clearContents()
            if let previous { pb.setString(previous, forType: .string) }
        }
        pendingRestore = restore
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay, execute: restore)
        return true
    }

    private func postCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        let vKeyCode: CGKeyCode = 9 // "v"
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else { return false }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
