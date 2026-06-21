import AppKit
import VoicelyCore

/// Phase 0 shell: an accessory (menu-bar-only) app with a status item.
/// Later phases attach the hotkey monitor, recorder, HUD, and real menu actions.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let icon = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Voicely")
        icon?.isTemplate = true
        item.button?.image = icon

        let menu = NSMenu()

        let status = NSMenuItem(title: "Voicely — idle", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let defaultModel = ModelCatalog.transcriptionModel(id: ModelCatalog.defaultTranscriptionID)?.name ?? "—"
        let model = NSMenuItem(title: "Model: \(defaultModel)", action: nil, keyEquivalent: "")
        model.isEnabled = false
        menu.addItem(model)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Voicely",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))

        item.menu = menu
        self.statusItem = item
    }
}
