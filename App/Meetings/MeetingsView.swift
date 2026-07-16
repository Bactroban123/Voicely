import AppKit
import SwiftUI
import VoicelyCore

/// The Meetings window: a list on the left, the selected meeting on the right.
///
/// Reuses the Frostpane primitives extracted during stabilization, so this
/// looks like the rest of the app without duplicating its tokens.
@available(macOS 14.2, *)
struct MeetingsView: View {
    @State private var meetings: [Meeting] = []
    @State private var selection: UUID?
    @State private var audioBytes: Int64 = 0
    var onClose: (() -> Void)?

    private let store = MeetingStore.shared

    var body: some View {
        HStack(spacing: 0) {
            list.frame(width: 260)
            Rectangle().fill(Color.fpHairline).frame(width: 0.5)
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 860, height: 560)
        .background(Color.fpBg)
        .tint(Color.fpAccent)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .voicelyMeetingsChanged)) { _ in reload() }
    }

    private func reload() {
        meetings = store.list()
        audioBytes = store.audioBytes()
        if selection == nil || !meetings.contains(where: { $0.id == selection }) {
            selection = meetings.first?.id
        }
    }

    /// Only shown when audio is actually being kept — meetings are the only
    /// feature that writes hundreds of MB, so it shouldn't be a surprise.
    @ViewBuilder
    private var storageFooter: some View {
        if audioBytes > 0 {
            VStack(spacing: 4) {
                Rectangle().fill(Color.fpHairline).frame(height: 0.5)
                HStack {
                    Text("Audio kept")
                        .font(.system(size: 10)).foregroundStyle(Color.fpMuted)
                    Spacer()
                    Text(DiskGuard.format(bytes: audioBytes))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.fpMuted)
                }
                .padding(.horizontal, 14)
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - List

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Meetings")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.fpText)
                Spacer()
                Text("\(meetings.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.fpMuted)
            }
            .padding(.horizontal, 14).padding(.top, 18).padding(.bottom, 12)

            Rectangle().fill(Color.fpHairline).frame(height: 0.5).padding(.horizontal, 14)

            if meetings.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "person.2.wave.2")
                        .font(.system(size: 22)).foregroundStyle(Color.fpMuted.opacity(0.6))
                    Text("No meetings yet")
                        .font(.system(size: 12)).foregroundStyle(Color.fpMuted)
                    Text("Start one from the menu bar during a call.")
                        .font(.system(size: 11)).foregroundStyle(Color.fpMuted.opacity(0.8))
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding(.horizontal, 20)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(meetings) { meeting in
                            MeetingRow(meeting: meeting, isSelected: selection == meeting.id) {
                                selection = meeting.id
                            }
                        }
                    }
                    .padding(.horizontal, 8).padding(.top, 8)
                }
            }

            Spacer(minLength: 0)
            storageFooter
            Button("Done") { onClose?() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14).padding(.bottom, 16)
        }
        .background(Color.fpSurface2)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let meeting = meetings.first(where: { $0.id == id }) {
            MeetingDetailView(meeting: meeting, onChanged: reload)
                .id(id)   // rebuild when the selection changes
        } else {
            VStack {
                Spacer()
                Text("Select a meeting")
                    .font(.system(size: 13)).foregroundStyle(Color.fpMuted)
                Spacer()
            }
        }
    }
}

@available(macOS 14.2, *)
private struct MeetingRow: View {
    let meeting: Meeting
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(meeting.title)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.fpText : Color.fpMuted)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(meeting.startedAt, style: .date)
                        .font(.system(size: 10)).foregroundStyle(Color.fpMuted)
                    if meeting.duration > 0 {
                        Text(DialogueMerge.timestamp(meeting.duration))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.fpMuted)
                    }
                    Spacer()
                    StatusPill(meeting: meeting)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.fpAccent.opacity(0.10) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

@available(macOS 14.2, *)
private struct StatusPill: View {
    let meeting: Meeting

    var body: some View {
        let (text, color) = label
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var label: (String, Color) {
        switch meeting.status {
        case .recording: return ("interrupted", .orange)   // only persists if the app died mid-call
        case .recorded: return ("not transcribed", .orange)
        case .transcribing: return ("transcribing", Color.fpAccent)
        case .transcribed, .summarizing: return ("summarizing", Color.fpAccent)
        case .complete: return meeting.capturedSystemAudio ? ("done", Color.fpAccent) : ("mic only", .orange)
        case .failed: return ("failed", .orange)
        }
    }
}

extension Notification.Name {
    /// Posted when stored meetings change, so an open window refreshes.
    static let voicelyMeetingsChanged = Notification.Name("voicelyMeetingsChanged")
}
