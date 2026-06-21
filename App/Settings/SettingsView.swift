import SwiftUI
import VoicelyCore

// MARK: - Tab model
private enum Tab: CaseIterable {
    case general, cleanup, vocabulary, monsters

    var label: String {
        switch self {
        case .general:   return "General"
        case .cleanup:   return "AI Cleanup"
        case .vocabulary: return "Vocabulary"
        case .monsters:  return "Monsters"
        }
    }
    var icon: String {
        switch self {
        case .general:    return "gearshape"
        case .cleanup:    return "sparkles"
        case .vocabulary: return "text.book.closed"
        case .monsters:   return "gamecontroller"
        }
    }
}

// MARK: - Colour tokens (Frostpane)
private extension Color {
    static let fpBg       = Color(red: 0.980, green: 0.988, blue: 0.996)  // #FBFDFE
    static let fpSurface  = Color(red: 0.953, green: 0.969, blue: 0.980)  // #F3F7FA
    static let fpSurface2 = Color(red: 0.910, green: 0.937, blue: 0.957)  // #E8EFF4
    static let fpText     = Color(red: 0.055, green: 0.102, blue: 0.141)  // #0E1A24
    static let fpMuted    = Color(red: 0.352, green: 0.420, blue: 0.471)  // #5A6B78
    static let fpAccent   = Color(red: 0.227, green: 0.659, blue: 0.788)  // #3AA8C9
    static let fpHairline = Color(red: 0.055, green: 0.102, blue: 0.141).opacity(0.10)
}

// MARK: - Settings View (Flow-style two-column)
struct SettingsView: View {
    @StateObject private var model = SettingsViewModel()
    @State private var selectedTab: Tab = .general
    var onClose: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            // ── Sidebar ──────────────────────────────────────────────────
            sidebar
                .frame(width: 200)

            // ── Divider ──────────────────────────────────────────────────
            Rectangle()
                .fill(Color.fpHairline)
                .frame(width: 0.5)

            // ── Content ──────────────────────────────────────────────────
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 760, height: 520)
        .background(Color.fpBg)
        .tint(Color.fpAccent)
    }

    // MARK: Sidebar
    private var sidebar: some View {
        VStack(spacing: 0) {
            // App header
            HStack(spacing: 10) {
                MascotView(pixelSize: 4)
                    .frame(width: 48, height: 72)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Voicely")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.fpText)
                    Text("frostpane")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.fpAccent)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Rectangle()
                .fill(Color.fpHairline)
                .frame(height: 0.5)
                .padding(.horizontal, 14)

            // Nav items
            VStack(spacing: 2) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    NavRow(tab: tab, isSelected: selectedTab == tab) {
                        selectedTab = tab
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Spacer()

            // Stats footer
            statsFooter

            // Done button
            Button("Done") {
                model.save()
                onClose?()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.bottom, 16)
        }
        .background(Color.fpSurface2)
    }

    // MARK: Stats footer
    private var statsFooter: some View {
        VStack(spacing: 8) {
            Rectangle()
                .fill(Color.fpHairline)
                .frame(height: 0.5)
                .padding(.horizontal, 14)
                .padding(.bottom, 4)

            statRow(label: "Total dictations",
                    value: "\(HistoryStore.shared.entries.count)")
            statRow(label: "Recent",
                    value: HistoryStore.shared.entries.first
                        .map { History.preview($0.text, max: 20) } ?? "—")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.fpMuted)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.fpText)
                .lineLimit(1)
        }
    }

    // MARK: Content area
    @ViewBuilder
    private var contentArea: some View {
        ScrollView {
            switch selectedTab {
            case .general:    generalPage
            case .cleanup:    cleanupPage
            case .vocabulary: vocabularyPage
            case .monsters:   monstersPage
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Pages

    private var generalPage: some View {
        PageShell(title: "General", icon: "gearshape") {
            FormCard {
                Section {
                    Picker("Dictation hotkey", selection: $model.hotKeyCode) {
                        Text("Right Option ⌥").tag(61)
                        Text("Left Option ⌥").tag(58)
                        Text("Right Command ⌘").tag(54)
                        Text("fn / Globe").tag(63)
                        Text("F5").tag(96)
                    }
                    Toggle("Launch at login", isOn: $model.launchAtLogin)
                } footer: {
                    Text("Tap to toggle · hold for push-to-talk · esc to cancel")
                }
            }
            FormCard {
                Section("On-device transcription") {
                    Picker("Model", selection: $model.transcriptionModelID) {
                        ForEach(ModelCatalog.transcription) { Text($0.name).tag($0.id) }
                    }
                }
            }
        }
    }

    private var cleanupPage: some View {
        PageShell(title: "AI Cleanup", icon: "sparkles") {
            FormCard {
                Section {
                    Toggle("Clean up transcripts", isOn: $model.cleanupEnabled)
                    Picker("Mode", selection: $model.cleanupModeID) {
                        ForEach(CleanupModes.all) { Text($0.name).tag($0.id) }
                    }
                    .disabled(!model.cleanupEnabled)
                    if let mode = CleanupModes.mode(id: model.cleanupModeID) {
                        Text(mode.detail).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Mode")
                }
            }
            FormCard {
                Section {
                    Picker("Cleanup model", selection: $model.cleanupModelID) {
                        ForEach(ModelCatalog.cleanup) { Text($0.name).tag($0.id) }
                    }
                    .disabled(!model.cleanupEnabled)
                    SecureField("OpenRouter API key", text: $model.apiKey)
                    Toggle("Zero data retention", isOn: $model.zeroRetention)
                        .disabled(!model.cleanupEnabled)
                } header: {
                    Text("Provider")
                }
            }
        }
    }

    private var vocabularyPage: some View {
        PageShell(title: "Vocabulary & Snippets", icon: "text.book.closed") {
            FormCard {
                Section {
                    TextEditor(text: $model.vocabularyText)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minHeight: 100)
                } header: {
                    Text("Vocabulary")
                } footer: {
                    Text("One word per line. Add misheard variants after a colon: Collabo: colab, kollabo")
                }
            }
            FormCard {
                Section {
                    TextEditor(text: $model.snippetsText)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minHeight: 90)
                } header: {
                    Text("Snippets")
                } footer: {
                    Text("Say the trigger, get the expansion. Format: trigger => expansion")
                }
            }
        }
    }

    private var monstersPage: some View {
        PageShell(title: "Monsters", icon: "gamecontroller") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your pixel army")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.fpText)

                Text("Tap the arena to summon a new warrior. They fight each other in their own little world.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.fpMuted)
                    .fixedSize(horizontal: false, vertical: true)

                MonsterArenaView()

                // Class legend
                classLegend
            }
            .padding(20)
        }
    }

    private var classLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The roster")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.fpMuted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 4) {
                ForEach(MonsterClass.allCases, id: \.self) { class_ in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.fpAccent.opacity(0.2))
                            .frame(width: 6, height: 6)
                        Text(class_.rawValue)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.fpMuted)
                        Spacer()
                    }
                }
            }
        }
        .padding(12)
        .background(Color.fpSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.fpHairline, lineWidth: 0.5)
        )
    }
}

// MARK: - Sidebar NavRow
private struct NavRow: View {
    let tab: Tab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? Color.fpAccent : Color.fpMuted)
                Text(tab.label)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.fpText : Color.fpMuted)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? Color.fpAccent.opacity(0.10)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Page shell
private struct PageShell<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Page header
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.fpAccent)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.fpText)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 16)

            Rectangle()
                .fill(Color.fpHairline)
                .frame(height: 0.5)
                .padding(.horizontal, 20)

            content()
        }
    }
}

// MARK: - Form card wrapper (opaque, hairline, radius 12)
private struct FormCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Form { content() }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: nil)
    }
}
