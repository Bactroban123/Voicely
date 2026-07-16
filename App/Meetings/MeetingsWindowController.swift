import AppKit
import SwiftUI

/// Hosts the Meetings window.
///
/// Mirrors `SettingsWindowController`, including the fix from stabilization:
/// the content view controller is released on close. Without that, closing the
/// window only orders it out — the SwiftUI tree stays mounted, `.onDisappear`
/// never fires, and anything it drives keeps running invisibly. That cost us a
/// 60fps timer in the Monsters tab; a meetings list that keeps reloading on
/// every change notification would be the same bug wearing a different hat.
@available(macOS 14.2, *)
final class MeetingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false)
            window.title = "Voicely Meetings"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.center()
            window.delegate = self
            self.window = window
        }
        window?.contentViewController = NSHostingController(
            rootView: MeetingsView(onClose: { [weak self] in self?.window?.close() }))
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Release the SwiftUI tree so its observers stop; show() rebuilds it.
        window?.contentViewController = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
