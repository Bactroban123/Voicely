import AppKit
import SwiftUI

/// Shows the first-run onboarding in a normal window (activation dance like the
/// settings window, since the app is otherwise menu-bar-only).
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var onClose: (() -> Void)?

    func show(onClose: @escaping () -> Void) {
        self.onClose = onClose
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "Welcome to Voicely"
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: OnboardingView(onDone: { [weak self] in self?.window?.close() }))
        self.window = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        onClose?()
        onClose = nil
    }
}
