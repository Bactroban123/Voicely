import AppKit
import SwiftUI

/// Diagnostics tab: permission health, session health, and the recent log
/// tail, with one-click "Copy Diagnostics" for bug reports. Everything is
/// read locally; nothing is ever transmitted.
struct DiagnosticsPage: View {
    @State private var micGranted = false
    @State private var accessibilityGranted = false
    @State private var inputMonitoringGranted = false
    @State private var logLines: [String] = []
    @State private var copied = false

    var body: some View {
        PageShell(title: "Diagnostics", icon: "stethoscope") {
            VStack(alignment: .leading, spacing: 0) {
                sessionCard
                permissionsCard
                logCard

                HStack {
                    Button {
                        copyDiagnostics()
                    } label: {
                        Label(copied ? "Copied" : "Copy Diagnostics", systemImage: "doc.on.doc")
                    }
                    Button {
                        refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    Spacer()
                    Text("Stays on this Mac — paste it wherever you report the issue.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.fpMuted)
                }
                .padding(.top, 2)
            }
            .padding(20)
        }
        .onAppear { refresh() }
    }

    // MARK: - Cards

    private var sessionCard: some View {
        FPCard {
            VStack(alignment: .leading, spacing: 6) {
                row("App version", appVersion)
                row("macOS", ProcessInfo.processInfo.operatingSystemVersionString)
                HStack {
                    label("Previous session")
                    Spacer()
                    switch CrashReporter.shared.lastRunEndedCleanly {
                    case .some(true):
                        badge("exited cleanly", ok: true)
                    case .some(false):
                        badge("didn't exit cleanly", ok: false)
                    case .none:
                        value("—")
                    }
                }
                if let detail = CrashReporter.shared.lastCrashDetail {
                    Text(detail)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.fpMuted)
                        .lineLimit(4)
                }
            }
            .padding(14)
        }
        .padding(.top, 14)
    }

    private var permissionsCard: some View {
        FPCard {
            VStack(spacing: 0) {
                permissionRow("Microphone", granted: micGranted, target: .microphone)
                Rectangle().fill(Color.fpHairline).frame(height: 0.5)
                permissionRow("Accessibility", granted: accessibilityGranted, target: .accessibility)
                Rectangle().fill(Color.fpHairline).frame(height: 0.5)
                permissionRow("Input Monitoring", granted: inputMonitoringGranted, target: .inputMonitoring)
            }
        }
    }

    private var logCard: some View {
        FPCard {
            VStack(alignment: .leading, spacing: 6) {
                label("Recent activity (last \(logLines.count) log lines)")
                ScrollView {
                    Text(logLines.isEmpty ? "No log lines yet this session." : logLines.joined(separator: "\n"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.fpMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 140)
            }
            .padding(14)
        }
    }

    // MARK: - Pieces

    private func permissionRow(_ name: String, granted: Bool, target: VoicelyPermission) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(granted ? Color.fpAccent : Color.orange)
                .frame(width: 7, height: 7)
            Text(name).font(.system(size: 12)).foregroundStyle(Color.fpText)
            Spacer()
            if granted {
                Text("granted")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.fpMuted)
            } else {
                Button("Open System Settings") {
                    PermissionManager.openSystemSettings(target)
                }
                .font(.system(size: 11))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func row(_ name: String, _ text: String) -> some View {
        HStack { label(name); Spacer(); value(text) }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Color.fpMuted)
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.fpText)
    }

    private func badge(_ text: String, ok: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(ok ? Color.fpAccent : Color.orange)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background((ok ? Color.fpAccent : Color.orange).opacity(0.10))
            .clipShape(Capsule())
    }

    // MARK: - Actions

    private func refresh() {
        micGranted = PermissionManager.microphoneAuthorized()
        accessibilityGranted = PermissionManager.accessibilityTrusted(prompt: false)
        inputMonitoringGranted = PermissionManager.inputMonitoringGranted()
        logLines = FileLogMirror.shared.recentLines(50)
        copied = false
    }

    private func copyDiagnostics() {
        let settings = SettingsStore.shared
        let blob = """
        Voicely diagnostics — \(Date())
        App: \(appVersion)  ·  macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        Permissions: mic=\(micGranted) accessibility=\(accessibilityGranted) inputMonitoring=\(inputMonitoringGranted)
        Transcription model: \(settings.transcriptionModelID)
        Cleanup: enabled=\(settings.cleanupEnabled) model=\(settings.cleanupModelID) mode=\(settings.cleanupModeID)
        Previous session: \(CrashReporter.shared.lastRunEndedCleanly.map { $0 ? "clean exit" : "didn't exit cleanly" } ?? "unknown")
        \(CrashReporter.shared.lastCrashDetail.map { "Last crash detail:\n\($0)\n" } ?? "")
        --- recent log ---
        \(FileLogMirror.shared.recentLines(200).joined(separator: "\n"))
        """
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(blob, forType: .string)
        copied = true
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }
}
