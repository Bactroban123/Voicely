import AppKit
import VoicelyCore

/// Menu-bar-only app. Owns the status item and the recording controller, and
/// reflects recording state in the icon. Permission onboarding gets a real UI in
/// Phase 5; for now we nudge toward System Settings if the hotkey tap can't start.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let controller = RecordingController()
    private var statusLabel: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        buildMenu(on: item)
        updateIcon(.idle)

        controller.onStateChange = { [weak self] state in
            self?.updateIcon(state)
            self?.statusLabel?.title = state == .recording ? "Voicely — listening" : "Voicely — idle"
        }

        if !controller.start() {
            // Input Monitoring not granted yet: send the user to grant it.
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

        let defaultModel = ModelCatalog.transcriptionModel(id: ModelCatalog.defaultTranscriptionID)?.name ?? "—"
        let model = NSMenuItem(title: "Model: \(defaultModel)", action: nil, keyEquivalent: "")
        model.isEnabled = false
        menu.addItem(model)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Voicely",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        item.menu = menu
    }

    private func updateIcon(_ state: RecordingController.UIState) {
        let recording = state == .recording
        let symbol = recording ? "waveform.circle.fill" : "waveform"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Voicely")
        image?.isTemplate = !recording
        statusItem?.button?.image = image
        statusItem?.button?.contentTintColor = recording ? NSColor.systemOrange : nil
    }
}
