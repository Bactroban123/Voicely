import SwiftUI

@main
struct VoicelyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The app is menu-bar-only; the real settings open from the status menu
        // via SettingsWindowController (the SwiftUI Settings scene's openSettings
        // is broken on macOS 26 Tahoe). This empty scene just satisfies App.
        Settings { EmptyView() }
    }
}
