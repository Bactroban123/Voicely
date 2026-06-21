import SwiftUI

/// First-run welcome (Frostpane). Explains Voicely, grants the two permissions,
/// and optionally takes an OpenRouter key for cleanup + translation.
struct OnboardingView: View {
    var onDone: () -> Void

    @State private var apiKey = KeychainStore.openRouterKey() ?? ""
    private let glacier = Color(red: 0.227, green: 0.659, blue: 0.788)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Voicely")
                    .font(.system(size: 30, weight: .semibold))
                Text("Speak any language. Type it in another. Privately, on your Mac.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Two quick permissions")
                    .font(.headline)
                permissionRow("Microphone", "so it can hear you") {
                    PermissionManager.requestMicrophone { _ in }
                }
                permissionRow("Input Monitoring", "so it can detect your hotkey") {
                    PermissionManager.requestInputMonitoring()
                    PermissionManager.openSystemSettings(.inputMonitoring)
                }
                permissionRow("Accessibility", "so it can type at your cursor") {
                    _ = PermissionManager.accessibilityTrusted(prompt: true)
                    PermissionManager.openSystemSettings(.accessibility)
                }
                Text("After flipping a switch in System Settings, quit and reopen Voicely.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("AI cleanup & translation")
                    .font(.headline)
                Text("Optional. Paste an OpenRouter key to enable cleanup and English ⇄ Hebrew translation. Plain dictation works free without one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("OpenRouter API key (optional)", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            Spacer(minLength: 4)

            HStack(spacing: 12) {
                Text("Then hold Right-Option (⌥), speak, release.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Start dictating") {
                    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !key.isEmpty { KeychainStore.setOpenRouterKey(key) }
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: 480, height: 540)
        .tint(glacier)
    }

    @ViewBuilder
    private func permissionRow(_ title: String, _ subtitle: String, _ action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.medium)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Grant", action: action)
        }
    }
}
