import SwiftUI
import VoicelyCore

// MARK: - Tab model
private enum Tab: CaseIterable {
    case general, cleanup, vocabulary, monsters
    var label: String {
        switch self { case .general: "General"; case .cleanup: "AI Cleanup"
                      case .vocabulary: "Vocabulary"; case .monsters: "Monsters" }
    }
    var icon: String {
        switch self { case .general: "gearshape"; case .cleanup: "sparkles"
                      case .vocabulary: "text.book.closed"; case .monsters: "gamecontroller" }
    }
}

// MARK: - Colour tokens
private extension Color {
    static let fpBg       = Color(red: 0.980, green: 0.988, blue: 0.996)
    static let fpSurface  = Color(red: 0.953, green: 0.969, blue: 0.980)
    static let fpSurface2 = Color(red: 0.910, green: 0.937, blue: 0.957)
    static let fpText     = Color(red: 0.055, green: 0.102, blue: 0.141)
    static let fpMuted    = Color(red: 0.352, green: 0.420, blue: 0.471)
    static let fpAccent   = Color(red: 0.227, green: 0.659, blue: 0.788)
    static let fpHairline = Color(red: 0.055, green: 0.102, blue: 0.141).opacity(0.10)
    static let fpLive     = Color(red: 0.133, green: 0.827, blue: 0.933)
}

// MARK: - Hot key name
private func hotKeyName(_ code: Int) -> (symbol: String, label: String) {
    switch code {
    case 61: return ("⌥", "Right Option")
    case 58: return ("⌥", "Left Option")
    case 54: return ("⌘", "Right Command")
    case 63: return ("fn", "Globe / fn")
    case 96: return ("F5", "F5")
    default: return ("?", "Unknown")
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @StateObject private var model = SettingsViewModel()
    @State private var selectedTab: Tab = .general
    var onClose: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 200)
            Rectangle().fill(Color.fpHairline).frame(width: 0.5)
            contentArea.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 760, height: 520)
        .background(Color.fpBg)
        .tint(Color.fpAccent)
    }

    // MARK: Sidebar
    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                MascotView(pixelSize: 4).frame(width: 48, height: 72)
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
            .padding(.horizontal, 14).padding(.top, 20).padding(.bottom, 16)

            Rectangle().fill(Color.fpHairline).frame(height: 0.5).padding(.horizontal, 14)

            VStack(spacing: 2) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    NavRow(tab: tab, isSelected: selectedTab == tab) { selectedTab = tab }
                }
            }
            .padding(.horizontal, 8).padding(.top, 8)

            Spacer()

            // Stats footer
            VStack(spacing: 6) {
                Rectangle().fill(Color.fpHairline).frame(height: 0.5).padding(.bottom, 2)
                statRow("Dictations", value: "\(HistoryStore.shared.entries.count)")
                statRow("Model", value: ModelCatalog.transcriptionModel(id: model.transcriptionModelID)
                    .map { shortModelName($0.name) } ?? "—")
                statRow("Cleanup", value: model.cleanupEnabled
                    ? (CleanupModes.mode(id: model.cleanupModeID)?.name ?? "On") : "Off")
            }
            .padding(.horizontal, 14).padding(.bottom, 10)

            Button("Done") { model.save(); onClose?() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14).padding(.bottom, 16)
        }
        .background(Color.fpSurface2)
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(Color.fpMuted)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.fpText).lineLimit(1)
        }
    }

    private func shortModelName(_ name: String) -> String {
        name.components(separatedBy: " ").prefix(2).joined(separator: " ")
    }

    // MARK: Content
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

    // ────────────────────────────────────────────────────────────────────────────
    // MARK: General Page
    // ────────────────────────────────────────────────────────────────────────────
    private var generalPage: some View {
        PageShell(title: "General", icon: "gearshape") {
            VStack(spacing: 0) {
                // Hotkey hero
                FPCard {
                    HStack(spacing: 16) {
                        // Key badge
                        let key = hotKeyName(model.hotKeyCode)
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.fpSurface2)
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.fpHairline, lineWidth: 1))
                                .shadow(color: .black.opacity(0.08), radius: 0, x: 0, y: 3)
                                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
                            Text(key.symbol)
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.fpText)
                        }
                        .frame(width: 54, height: 48)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Dictation hotkey")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.fpText)
                            Text("Currently: \(key.label) · tap to toggle, hold to push-to-talk")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.fpMuted)
                        }
                        Spacer()
                        Picker("", selection: $model.hotKeyCode) {
                            Text("Right ⌥").tag(61)
                            Text("Left ⌥").tag(58)
                            Text("Right ⌘").tag(54)
                            Text("fn / Globe").tag(63)
                            Text("F5").tag(96)
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                    .padding(16)
                }

                FPCard {
                    Toggle(isOn: $model.launchAtLogin) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Launch at login")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.fpText)
                                Text("Starts in the menu bar when you log in")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.fpMuted)
                            }
                        } icon: {
                            Image(systemName: "power")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.fpAccent)
                                .frame(width: 20)
                        }
                    }
                    .padding(16)
                }

                // Transcription model cards
                FPCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Transcription engine", systemImage: "waveform")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.fpMuted)
                            .padding(.horizontal, 16).padding(.top, 14)

                        Divider().padding(.horizontal, 12)

                        VStack(spacing: 4) {
                            ForEach(ModelCatalog.transcription) { option in
                                ModelRow(option: option,
                                         isSelected: model.transcriptionModelID == option.id,
                                         badge: option.id == "parakeet-en" ? "default" : nil) {
                                    model.transcriptionModelID = option.id
                                }
                            }
                        }
                        .padding(.horizontal, 8).padding(.bottom, 8)
                    }
                }
            }
            .padding(16)
        }
    }

    // ────────────────────────────────────────────────────────────────────────────
    // MARK: AI Cleanup Page
    // ────────────────────────────────────────────────────────────────────────────
    private var cleanupPage: some View {
        PageShell(title: "AI Cleanup", icon: "sparkles") {
            VStack(spacing: 0) {
                // Power toggle — big and prominent
                FPCard {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(model.cleanupEnabled
                                      ? Color.fpAccent.opacity(0.15)
                                      : Color.fpSurface2)
                                .frame(width: 40, height: 40)
                            Image(systemName: "sparkles")
                                .font(.system(size: 16))
                                .foregroundStyle(model.cleanupEnabled ? Color.fpAccent : Color.fpMuted)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI cleanup")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.fpText)
                            Text(model.cleanupEnabled
                                 ? "Transcript is polished before pasting"
                                 : "Raw transcript is pasted directly")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.fpMuted)
                        }
                        Spacer()
                        Toggle("", isOn: $model.cleanupEnabled).labelsHidden()
                    }
                    .padding(16)
                }
                .opacity(1.0)

                // Mode pills
                FPCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Mode", systemImage: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(model.cleanupEnabled ? Color.fpMuted : Color.fpMuted.opacity(0.5))
                            .padding(.horizontal, 16).padding(.top, 14)

                        Divider().padding(.horizontal, 12)

                        VStack(spacing: 4) {
                            ForEach(CleanupModes.all) { mode in
                                ModePill(mode: mode,
                                         isSelected: model.cleanupModeID == mode.id,
                                         isEnabled: model.cleanupEnabled) {
                                    if model.cleanupEnabled { model.cleanupModeID = mode.id }
                                }
                            }
                        }
                        .padding(.horizontal, 8).padding(.bottom, 8)
                    }
                }
                .disabled(!model.cleanupEnabled)
                .opacity(model.cleanupEnabled ? 1 : 0.45)

                // Provider
                FPCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Model (via OpenRouter)", systemImage: "cpu")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(model.cleanupEnabled ? Color.fpMuted : Color.fpMuted.opacity(0.5))
                            .padding(.horizontal, 16).padding(.top, 14)

                        Divider().padding(.horizontal, 12)

                        VStack(spacing: 4) {
                            ForEach(ModelCatalog.cleanup) { option in
                                ModelRow(option: option,
                                         isSelected: model.cleanupModelID == option.id,
                                         badge: option.id == "google/gemini-2.5-flash-lite" ? "default" : nil) {
                                    model.cleanupModelID = option.id
                                }
                            }
                        }
                        .padding(.horizontal, 8)

                        Divider().padding(.horizontal, 12)

                        // API key row
                        HStack(spacing: 10) {
                            Image(systemName: "key")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.fpMuted)
                                .frame(width: 20)
                            SecureField("OpenRouter API key", text: $model.apiKey)
                                .font(.system(size: 13, design: .monospaced))
                                .textContentType(.password)
                            if !model.apiKey.isEmpty {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.fpAccent)
                                    .font(.system(size: 14))
                            }
                        }
                        .padding(.horizontal, 16)

                        // Zero retention toggle
                        HStack(spacing: 10) {
                            Image(systemName: "eye.slash")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.fpMuted)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Zero data retention")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.fpText)
                                Text("Adds `no-store` header — OpenRouter won't log your text")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.fpMuted)
                            }
                            Spacer()
                            Toggle("", isOn: $model.zeroRetention).labelsHidden()
                        }
                        .padding(.horizontal, 16).padding(.bottom, 14)
                    }
                }
                .disabled(!model.cleanupEnabled)
                .opacity(model.cleanupEnabled ? 1 : 0.45)
            }
            .padding(16)
        }
    }

    // ────────────────────────────────────────────────────────────────────────────
    // MARK: Vocabulary Page
    // ────────────────────────────────────────────────────────────────────────────
    @State private var vocabSubTab: VocabSubTab = .vocabulary

    private enum VocabSubTab { case vocabulary, snippets }

    private var vocabularyPage: some View {
        PageShell(title: "Vocabulary & Snippets", icon: "text.book.closed") {
            VStack(spacing: 0) {
                // Sub-tab picker
                HStack(spacing: 0) {
                    vocabTabButton("Vocabulary",
                                   count: vocabCount,
                                   isSelected: vocabSubTab == .vocabulary) {
                        vocabSubTab = .vocabulary
                    }
                    vocabTabButton("Snippets",
                                   count: snippetCount,
                                   isSelected: vocabSubTab == .snippets) {
                        vocabSubTab = .snippets
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.bottom, 12)

                if vocabSubTab == .vocabulary {
                    FPCard {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Label("Words & corrections", systemImage: "character.cursor.ibeam")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.fpMuted)
                                Spacer()
                                Text("\(vocabCount) \(vocabCount == 1 ? "entry" : "entries")")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.fpMuted)
                            }
                            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)

                            Divider().padding(.horizontal, 12)

                            TextEditor(text: $model.vocabularyText)
                                .font(.system(size: 13, design: .monospaced))
                                .frame(minHeight: 120)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                                .padding(.horizontal, 12).padding(.vertical, 8)

                            Divider().padding(.horizontal, 12)

                            Text("One word per line · add misheard variants after a colon: Voicely: Voicley, voicly")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.fpMuted)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                        }
                    }

                    // Live chip preview
                    if vocabCount > 0 {
                        vocabChips
                    }

                } else {
                    FPCard {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Label("Text expansions", systemImage: "arrow.right.square")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.fpMuted)
                                Spacer()
                                Text("\(snippetCount) \(snippetCount == 1 ? "snippet" : "snippets")")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.fpMuted)
                            }
                            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)

                            Divider().padding(.horizontal, 12)

                            TextEditor(text: $model.snippetsText)
                                .font(.system(size: 13, design: .monospaced))
                                .frame(minHeight: 120)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                                .padding(.horizontal, 12).padding(.vertical, 8)

                            Divider().padding(.horizontal, 12)

                            Text("Say the trigger → get the expansion · format: trigger => expansion")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.fpMuted)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                        }
                    }

                    // Live snippet preview
                    if snippetCount > 0 {
                        snippetPreview
                    }
                }
            }
            .padding(16)
        }
    }

    private var vocabCount: Int {
        model.vocabularyText.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    private var snippetCount: Int {
        model.snippetsText.split(separator: "\n")
            .filter { $0.contains("=>") }.count
    }

    private func vocabTabButton(_ label: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(isSelected ? Color.fpAccent.opacity(0.15) : Color.fpSurface2)
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(isSelected ? Color.fpAccent : Color.fpMuted)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(isSelected ? Color.fpAccent.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var vocabChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.fpMuted)
                .padding(.horizontal, 4)

            FlowLayout(spacing: 6) {
                ForEach(Array(model.vocabularyText.split(separator: "\n")
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    .prefix(20).enumerated()), id: \.offset) { _, line in
                    let term = String(line.split(separator: ":").first ?? line)
                        .trimmingCharacters(in: .whitespaces)
                    Text(term)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.fpAccent)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.fpAccent.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.fpAccent.opacity(0.20), lineWidth: 0.5)
                        )
                }
            }
        }
        .padding(.top, 8)
    }

    private var snippetPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preview")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.fpMuted)
                .padding(.horizontal, 4)

            VStack(spacing: 4) {
                ForEach(Array(model.snippetsText.split(separator: "\n")
                    .filter { $0.contains("=>") }
                    .prefix(8).enumerated()), id: \.offset) { _, line in
                    let parts = line.components(separatedBy: "=>")
                    if parts.count >= 2 {
                        let trigger = parts[0].trimmingCharacters(in: .whitespaces)
                        let expansion = parts[1...].joined(separator: "=>").trimmingCharacters(in: .whitespaces)
                        HStack(spacing: 8) {
                            Text(trigger)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.fpAccent)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color.fpAccent.opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.fpMuted)
                            Text(expansion)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.fpText)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    // ────────────────────────────────────────────────────────────────────────────
    // MARK: Monsters Page
    // ────────────────────────────────────────────────────────────────────────────
    private var monstersPage: some View {
        PageShell(title: "Monsters", icon: "gamecontroller") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your pixel army")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.fpText)
                Text("Tap the arena to summon a new warrior. They hunt each other down and fight to the death.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.fpMuted)
                    .fixedSize(horizontal: false, vertical: true)

                MonsterArenaView()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 4) {
                    ForEach(MonsterClass.allCases, id: \.self) { class_ in
                        HStack(spacing: 5) {
                            Circle().fill(Color.fpAccent.opacity(0.25)).frame(width: 5, height: 5)
                            Text(class_.rawValue)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.fpMuted)
                            Spacer()
                        }
                    }
                }
                .padding(12)
                .background(Color.fpSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.fpHairline, lineWidth: 0.5))
            }
            .padding(20)
        }
    }
}

// MARK: - Sub-components

private struct NavRow: View {
    let tab: Tab; let isSelected: Bool; let action: () -> Void
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
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(isSelected ? Color.fpAccent.opacity(0.10) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

private struct PageShell<Content: View>: View {
    let title: String; let icon: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Color.fpAccent)
                Text(title)
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.fpText)
            }
            .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 14)

            Rectangle().fill(Color.fpHairline).frame(height: 0.5).padding(.horizontal, 20)

            content()
        }
    }
}

/// Clean opaque card with hairline border
private struct FPCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 0) { content() }
            .background(Color.fpSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.fpHairline, lineWidth: 0.5))
            .padding(.bottom, 10)
    }
}

/// Single-model selectable row inside a card
private struct ModelRow: View {
    let option: ModelOption
    let isSelected: Bool
    let badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.fpAccent : Color.fpHairline, lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                    if isSelected {
                        Circle().fill(Color.fpAccent).frame(width: 8, height: 8)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(option.name)
                            .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                            .foregroundStyle(Color.fpText)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.fpAccent)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.fpAccent.opacity(0.10))
                                .clipShape(Capsule())
                        }
                    }
                    Text(option.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.fpMuted)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(isSelected ? Color.fpAccent.opacity(0.05) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}

/// Cleanup mode selectable row
private struct ModePill: View {
    let mode: CleanupMode
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    private var modeIcon: String {
        switch mode.id {
        case "clean":        return "text.badge.checkmark"
        case "polish":       return "wand.and.stars"
        case "prompt":       return "chevron.left.forwardslash.chevron.right"
        case "translate-en": return "globe"
        case "translate-he": return "globe.asia.australia"
        default:             return "sparkles"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: modeIcon)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Color.fpAccent : Color.fpMuted)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.name)
                        .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(Color.fpText)
                    Text(mode.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.fpMuted)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.fpAccent)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(isSelected ? Color.fpAccent.opacity(0.07) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}

/// Simple flow layout for chips
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0; var y: CGFloat = 0; var rowH: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > width && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            rowH = max(rowH, s.height); x += s.width + spacing
        }
        return CGSize(width: width, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX; var y = bounds.minY; var rowH: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            rowH = max(rowH, s.height); x += s.width + spacing
        }
    }
}
