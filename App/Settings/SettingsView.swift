import SwiftUI
import VoicelyCore

// MARK: - Branded Header
private struct SettingsHeader: View {
    private let navy   = Color(red: 0.059, green: 0.090, blue: 0.141)
    private let mid    = Color(red: 0.090, green: 0.133, blue: 0.200)
    private let glacier = Color(red: 0.227, green: 0.659, blue: 0.788)
    private let cyan   = Color(red: 0.133, green: 0.827, blue: 0.933)

    // Pixel sparkles — fixed positions inside the 460×130 header
    private struct Spark: Identifiable {
        let id: Int; let x: CGFloat; let y: CGFloat; let r: CGFloat; let color: Color
    }
    private let sparks: [Spark] = [
        Spark(id:0, x:290, y:18,  r:2,   color:.white.opacity(0.55)),
        Spark(id:1, x:340, y:52,  r:3,   color: Color(red:0.133,green:0.827,blue:0.933).opacity(0.7)),
        Spark(id:2, x:390, y:22,  r:1.5, color:.white.opacity(0.35)),
        Spark(id:3, x:415, y:75,  r:2.5, color: Color(red:0.227,green:0.659,blue:0.788).opacity(0.6)),
        Spark(id:4, x:360, y:100, r:2,   color:.white.opacity(0.4)),
        Spark(id:5, x:430, y:42,  r:1.5, color: Color(red:1.0,green:0.843,blue:0.0).opacity(0.5)),
        Spark(id:6, x:450, y:108, r:1.5, color: Color(red:0.133,green:0.827,blue:0.933).opacity(0.4)),
        Spark(id:7, x:310, y:88,  r:1,   color:.white.opacity(0.3)),
    ]

    var body: some View {
        ZStack(alignment: .leading) {
            // Background gradient
            LinearGradient(
                colors: [navy, mid],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle grid lines (pixel aesthetic)
            Canvas { ctx, size in
                let step: CGFloat = 20
                var x: CGFloat = 0
                while x < size.width {
                    ctx.stroke(
                        Path { p in p.move(to: .init(x:x,y:0)); p.addLine(to: .init(x:x,y:size.height)) },
                        with: .color(.white.opacity(0.03)), lineWidth: 1
                    )
                    x += step
                }
                var y: CGFloat = 0
                while y < size.height {
                    ctx.stroke(
                        Path { p in p.move(to: .init(x:0,y:y)); p.addLine(to: .init(x:size.width,y:y)) },
                        with: .color(.white.opacity(0.03)), lineWidth: 1
                    )
                    y += step
                }
            }

            // Pixel sparkle dots
            ForEach(sparks) { s in
                Circle().fill(s.color)
                    .frame(width: s.r*2, height: s.r*2)
                    .position(x: s.x, y: s.y)
            }

            // Mascot + title
            HStack(spacing: 18) {
                MascotView(pixelSize: 5)
                    .frame(width: 60, height: 90)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Voicely")
                        .font(.system(size: 30, weight: .black))
                        .foregroundStyle(.white)

                    Text("speak · clean · translate")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(cyan)

                    Spacer(minLength: 6)

                    Text("✦ frostpane edition ✦")
                        .font(.system(size: 9, weight: .light, design: .monospaced))
                        .foregroundStyle(glacier.opacity(0.65))
                }

                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .frame(height: 130)
        .clipped()
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @StateObject private var model = SettingsViewModel()
    var onClose: (() -> Void)?

    private let glacier = Color(red: 0.227, green: 0.659, blue: 0.788)

    private let hotkeyOptions: [(name: String, code: Int)] = [
        ("Right Option ⌥", 61),
        ("Left Option ⌥",  58),
        ("Right Command ⌘", 54),
        ("fn / Globe 🌐",   63),
        ("F5",              96),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // ── Branded header ──────────────────────────────────────────────
            SettingsHeader()

            // ── Form ────────────────────────────────────────────────────────
            Form {
                Section {
                    Picker("Hotkey", selection: $model.hotKeyCode) {
                        ForEach(hotkeyOptions, id: \.code) { Text($0.name).tag($0.code) }
                    }
                    Toggle("Launch at login", isOn: $model.launchAtLogin)
                    Text("Tap to toggle · hold for push-to-talk · esc to cancel")
                        .font(.caption).foregroundStyle(.secondary)
                } header: {
                    Label("General", systemImage: "gearshape.fill")
                }

                Section {
                    Picker("Model", selection: $model.transcriptionModelID) {
                        ForEach(ModelCatalog.transcription) { Text($0.name).tag($0.id) }
                    }
                } header: {
                    Label("On-device transcription", systemImage: "waveform.circle.fill")
                }

                Section {
                    Toggle("Clean up transcripts", isOn: $model.cleanupEnabled)
                    Picker("Mode", selection: $model.cleanupModeID) {
                        ForEach(CleanupModes.all) { Text($0.name).tag($0.id) }
                    }
                    .disabled(!model.cleanupEnabled)
                    if let mode = CleanupModes.mode(id: model.cleanupModeID) {
                        Text(mode.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Model", selection: $model.cleanupModelID) {
                        ForEach(ModelCatalog.cleanup) { Text($0.name).tag($0.id) }
                    }
                    .disabled(!model.cleanupEnabled)
                    SecureField("OpenRouter API key", text: $model.apiKey)
                    Toggle("Zero data retention", isOn: $model.zeroRetention)
                        .disabled(!model.cleanupEnabled)
                } header: {
                    Label("AI cleanup & translation", systemImage: "sparkles")
                }

                Section {
                    Text("One per line. Optional misheard variants after a colon, e.g. Collabo: colab, kollabo")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $model.vocabularyText)
                        .font(.body).frame(minHeight: 70)
                } header: {
                    Label("Vocabulary", systemImage: "text.book.closed.fill")
                }

                Section {
                    Text("Say the trigger, get the text. One per line: trigger => expansion.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $model.snippetsText)
                        .font(.body).frame(minHeight: 60)
                } header: {
                    Label("Snippets", systemImage: "bolt.fill")
                }
            }
            .formStyle(.grouped)

            Divider()

            // ── Done button ─────────────────────────────────────────────────
            HStack {
                Spacer()
                Button("Done") {
                    model.save()
                    onClose?()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 460, height: 710)
        .tint(glacier)
    }
}
