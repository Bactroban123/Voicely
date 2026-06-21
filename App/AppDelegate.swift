import AppKit
import VoicelyCore

/// Menu-bar-only app. Owns the status item, the recording controller, the
/// floating HUD, and the settings window, and reflects recording state in the icon.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var statusLabel: NSMenuItem?
    private let controller = RecordingController()
    private let hud = HUDController()
    private let settingsWindow = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        buildMenu(on: item)
        updateIcon(.idle)

        controller.onStateChange = { [weak self] state in
            self?.updateIcon(state)
            switch state {
            case .idle:
                self?.statusLabel?.title = "Voicely — idle"
                self?.hud.hide()
            case .recording:
                self?.statusLabel?.title = "Voicely — listening"
                self?.hud.show(phase: .recording, label: "Listening")
            case .processing:
                self?.statusLabel?.title = "Voicely — transcribing…"
                self?.hud.show(phase: .processing, label: "Transcribing…")
            }
        }
        controller.onLevel = { [weak self] level in self?.hud.update(level: level) }

        if !controller.start() {
            // Input Monitoring not granted yet: guide the user to grant it.
            PermissionManager.requestInputMonitoring()
            PermissionManager.openSystemSettings(.inputMonitoring)
        }
    }

    private func buildMenu(on item: NSStatusItem) {
        let menu = NSMenu()

        let status = NSMenuItem(title: "Voicely — idle", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        statusLabel = status

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(NSMenuItem(title: "Quit Voicely",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        item.menu = menu
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    private func updateIcon(_ state: RecordingController.UIState) {
        let symbol: String
        let active: Bool
        switch state {
        case .idle: symbol = "waveform"; active = false
        case .recording: symbol = "waveform.circle.fill"; active = true
        case .processing: symbol = "waveform.circle"; active = true
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Voicely")
        image?.isTemplate = !active
        statusItem?.button?.image = image
        statusItem?.button?.contentTintColor = active ? NSColor.systemOrange : nil
    }
}
