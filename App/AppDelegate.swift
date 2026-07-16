import AppKit
import VoicelyCore

/// Menu-bar-only app. Owns the status item, the recording controller, the
/// floating HUD, and the settings window, and reflects recording state in the icon.
///
/// @MainActor because every AppKit delegate callback and menu action here is
/// main-thread by contract — stating it lets the compiler check the boundary
/// with the meeting vertical instead of taking our word for it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var statusLabel: NSMenuItem?
    private var modeMenu: NSMenu?
    private let recentMenu = NSMenu()
    private let controller = RecordingController()
    /// Meetings live in their own vertical: their own controller, their own
    /// status item. Nothing here is shared with dictation, so a meeting can
    /// record while the user dictates.
    private var meetings: AnyObject?
    private var meetingStatusItem: NSStatusItem?
    private var meetingMenuItem: NSMenuItem?
    private var meetingsWindow: AnyObject?
    private let hud = HUDController()
    private let settingsWindow = SettingsWindowController()
    private let onboarding = OnboardingWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        CrashReporter.shared.install()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        VoicelyLog.lifecycle.info("Voicely \(version) launched")
        if CrashReporter.shared.lastRunEndedCleanly == false {
            VoicelyLog.lifecycle.warning("previous session didn't exit cleanly — details in Settings → Diagnostics")
        }

        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        buildMenu(on: item)
        updateIcon(.idle)

        controller.onStateChange = { [weak self] state in
            guard let self else { return }
            self.hudFlashGeneration += 1 // a state change outranks a pending flash restore
            self.refreshHUD(for: state)
        }
        controller.onLevel = { [weak self] level in self?.hud.update(level: level) }
        controller.onNotice = { [weak self] text in self?.flashHUD(text) }
        DiagnosticsPage.controller = controller

        // Existing users (already have a key) skip onboarding; only fresh installs see it.
        let onboarded = SettingsStore.shared.hasOnboarded
            || (KeychainStore.openRouterKey()?.isEmpty == false)
        if onboarded {
            // Returning user: make sure the permissions are registered (prompts if needed).
            PermissionManager.requestMicrophone { _ in }
            _ = PermissionManager.accessibilityTrusted(prompt: true)
            PermissionManager.requestInputMonitoring()
        } else {
            // First run: a guided Frostpane welcome drives the permissions + key.
            onboarding.show { SettingsStore.shared.hasOnboarded = true }
        }

        if #available(macOS 14.2, *) { setUpMeetings() }

        let started = controller.start()
        if onboarded && !started {
            PermissionManager.openSystemSettings(.inputMonitoring)
        }
        VoicelyLog.lifecycle.info("event tap \(started ? "started" : "NOT started (Input Monitoring missing?)")")
    }

    func applicationWillTerminate(_ notification: Notification) {
        VoicelyLog.lifecycle.info("clean exit")
        CrashReporter.shared.markCleanExit()
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

        if #available(macOS 14.2, *) {
            menu.addItem(.separator())
            let meeting = NSMenuItem(title: "Start Meeting Recording",
                                     action: #selector(toggleMeeting), keyEquivalent: "")
            meeting.target = self
            menu.addItem(meeting)
            meetingMenuItem = meeting

            let list = NSMenuItem(title: "Meetings…", action: #selector(openMeetings), keyEquivalent: "")
            list.target = self
            menu.addItem(list)
        }

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

    // MARK: - Meetings

    @available(macOS 14.2, *)
    private var meetingController: MeetingController? { meetings as? MeetingController }

    @available(macOS 14.2, *)
    private func setUpMeetings() {
        let controller = MeetingController()
        meetings = controller
        meetingsWindow = MeetingsWindowController()
        // The list refreshes itself when stored meetings change, so a window
        // left open during a call stays honest.
        controller.onMeetingsChanged = { NotificationCenter.default.post(name: .voicelyMeetingsChanged, object: nil) }
        controller.onNotice = { [weak self] text in self?.flashHUD(text) }
        controller.onStateChange = { [weak self] state in self?.refreshMeetingUI(state) }
        MeetingDetailView.controller = controller
        // Anything the app was part-way through when it last died gets offered
        // back rather than left as an orphan folder.
        controller.recoverInterruptedMeetings()
    }

    @objc private func openMeetings() {
        guard #available(macOS 14.2, *) else { return }
        (meetingsWindow as? MeetingsWindowController)?.show()
    }

    @objc private func toggleMeeting() {
        guard #available(macOS 14.2, *), let meetings = meetingController else { return }
        meetings.isRecording ? meetings.stop() : meetings.start()
    }

    @available(macOS 14.2, *)
    private func refreshMeetingUI(_ state: MeetingSession.State) {
        switch state {
        case .recording:
            meetingMenuItem?.title = "Stop & Save Meeting"
            showMeetingIndicator(true)
        case .stopping, .transcribing, .summarizing:
            meetingMenuItem?.title = "Finishing the meeting…"
            showMeetingIndicator(true)
        case .idle, .complete, .failed:
            meetingMenuItem?.title = "Start Meeting Recording"
            showMeetingIndicator(false)
        }
    }

    /// A second status item, deliberately: DESIGN.md reserves the live-cyan
    /// tint for dictation capture, so reusing it would make "recording a
    /// meeting" and "listening to you" indistinguishable — and both can be true
    /// at once.
    private func showMeetingIndicator(_ visible: Bool) {
        guard visible else {
            if let item = meetingStatusItem { NSStatusBar.system.removeStatusItem(item) }
            meetingStatusItem = nil
            return
        }
        guard meetingStatusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Meeting recording")
        image?.isTemplate = false
        item.button?.image = image
        // Terracotta from DESIGN.md's danger token — unmistakably not live-cyan.
        item.button?.contentTintColor = NSColor(srgbRed: 0.86, green: 0.42, blue: 0.30, alpha: 1)
        item.button?.toolTip = "Voicely is recording this meeting"
        meetingStatusItem = item
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

    // MARK: - HUD

    private var hudFlashGeneration = 0

    /// State-driven HUD appearance; also the restore point after a flash.
    private func refreshHUD(for state: RecordingController.UIState) {
        updateIcon(state)
        switch state {
        case .idle:
            statusLabel?.title = "Voicely — idle"
            hud.hide()
        case .recording:
            statusLabel?.title = "Voicely — listening"
            hud.show(phase: .recording, label: "Listening")
        case .processing:
            statusLabel?.title = "Voicely — transcribing…"
            hud.show(phase: .processing, label: "Transcribing…")
        }
    }

    /// Briefly surfaces a notice ("Still finishing your last dictation…"),
    /// then restores the state-driven appearance unless a newer state change
    /// or flash superseded it.
    private func flashHUD(_ text: String) {
        hudFlashGeneration += 1
        let generation = hudFlashGeneration
        hud.show(phase: .processing, label: text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self, generation == self.hudFlashGeneration else { return }
            self.refreshHUD(for: self.controller.state)
        }
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
