import AppKit
import VoicelyCore

/// Menu-bar-only app. Owns the status item, the recording controller, the
/// floating HUD, and the settings window, and reflects recording state in the icon.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var statusLabel: NSMenuItem?
    private var modeMenu: NSMenu?
    private let recentMenu = NSMenu()
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

        // First-run onboarding: request all three permissions so they show clean
        // system prompts and register Voicely in System Settings. Accessibility +
        // Input Monitoring take effect only after a relaunch.
        PermissionManager.requestMicrophone { _ in }
        _ = PermissionManager.accessibilityTrusted(prompt: true)
        PermissionManager.requestInputMonitoring()

        if !controller.start() {
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

        let modeItem = NSMenuItem(title: "Cleanup mode", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        for mode in CleanupModes.all {
            let item = NSMenuItem(title: mode.name, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.id
            item.state = (mode.id == SettingsStore.shared.cleanupModeID) ? .on : .off
            modeMenu.addItem(item)
        }
        modeItem.submenu = modeMenu
        self.modeMenu = modeMenu
        menu.addItem(modeItem)

        let recentItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        recentMenu.delegate = self
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

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

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        SettingsStore.shared.cleanupModeID = id
        NotificationCenter.default.post(name: .voicelySettingsChanged, object: nil)
        modeMenu?.items.forEach { item in
            item.state = ((item.representedObject as? String) == id) ? .on : .off
        }
    }

    // MARK: - Recent (transcript history)

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === recentMenu else { return }
        menu.removeAllItems()
        let entries = HistoryStore.shared.entries
        guard !entries.isEmpty else {
            let empty = NSMenuItem(title: "No recent dictations", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        let header = NSMenuItem(title: "Click to copy", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for entry in entries.prefix(12) {
            let item = NSMenuItem(title: History.preview(entry.text),
                                  action: #selector(copyRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.text
            item.toolTip = entry.text
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear recent", action: #selector(clearRecent), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }

    @objc private func copyRecent(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    @objc private func clearRecent() {
        HistoryStore.shared.clear()
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
        // Frostpane: live-cyan while capturing/processing, monochrome template when idle.
        let liveCyan = NSColor(srgbRed: 0.133, green: 0.827, blue: 0.933, alpha: 1)
        statusItem?.button?.contentTintColor = active ? liveCyan : nil
    }
}
