import SwiftUI

@main
struct VoicelyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            SettingsPlaceholderView()
        }
    }
}

private struct SettingsPlaceholderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Voicely")
                .font(.title2)
                .fontWeight(.medium)
            Text("Settings coming soon.")
                .foregroundStyle(.secondary)
        }
        .frame(width: 380, height: 220)
        .padding()
    }
}
