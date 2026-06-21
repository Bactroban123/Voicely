import AppKit
import SwiftUI

/// Shows the settings window from a menu-bar (accessory) app. Bypasses the
/// SwiftUI `Settings` scene because `openSettings` is broken on macOS 26 Tahoe
/// (research §4): a plain NSWindow + the activation-policy dance is reliable.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false)
            window.title = "Voicely Settings"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }

        // Fresh view each open so it reflects current stored values.
        window?.contentViewController = NSHostingController(
            rootView: SettingsView(onClose: { [weak self] in self?.window?.close() }))

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Return to menu-bar-only.
        NSApp.setActivationPolicy(.accessory)
    }
}
