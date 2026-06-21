import SwiftUI
import VoicelyCore

struct SettingsView: View {
    @StateObject private var model = SettingsViewModel()
    var onClose: (() -> Void)?

    private let hotkeyOptions: [(name: String, code: Int)] = [
        ("Right Option", 61),
        ("Left Option", 58),
        ("Right Command", 54),
        ("fn / Globe", 63),
        ("F5", 96),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("General") {
                    Picker("Dictation hotkey", selection: $model.hotKeyCode) {
                        ForEach(hotkeyOptions, id: \.code) { Text($0.name).tag($0.code) }
                    }
                    Toggle("Launch at login", isOn: $model.launchAtLogin)
                    Text("Tap to toggle · hold to push-to-talk · esc to cancel")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Transcription (on-device)") {
                    Picker("Model", selection: $model.transcriptionModelID) {
                        ForEach(ModelCatalog.transcription) { Text($0.name).tag($0.id) }
                    }
                }

                Section("AI cleanup") {
                    Toggle("Clean up transcripts", isOn: $model.cleanupEnabled)
                    Picker("Mode", selection: $model.cleanupModeID) {
                        ForEach(CleanupModes.all) { Text($0.name).tag($0.id) }
                    }
                    .disabled(!model.cleanupEnabled)
                    if let mode = CleanupModes.mode(id: model.cleanupModeID) {
                        Text(mode.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Cleanup model", selection: $model.cleanupModelID) {
                        ForEach(ModelCatalog.cleanup) { Text($0.name).tag($0.id) }
                    }
                    .disabled(!model.cleanupEnabled)
                    SecureField("OpenRouter API key", text: $model.apiKey)
                    Toggle("Zero data retention", isOn: $model.zeroRetention)
                        .disabled(!model.cleanupEnabled)
                }

                Section("Vocabulary") {
                    Text("One per line. Optional misheard variants after a colon, e.g. Collabo: colab, kollabo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $model.vocabularyText)
                        .font(.body)
                        .frame(minHeight: 80)
                }

                Section("Snippets") {
                    Text("Say the trigger, get the text. One per line: trigger => expansion. e.g. my email => gal@example.com")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $model.snippetsText)
                        .font(.body)
                        .frame(minHeight: 70)
                }
            }
            .formStyle(.grouped)

            Divider()
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
        .frame(width: 460, height: 680)
        .tint(Color(red: 0.227, green: 0.659, blue: 0.788)) // Frostpane glacier #3AA8C9
    }
}
