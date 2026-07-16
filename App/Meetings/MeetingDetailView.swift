import AppKit
import SwiftUI
import VoicelyCore

/// One meeting: its notes, its transcript, and its tasks.
@available(macOS 14.2, *)
struct MeetingDetailView: View {
    let meeting: Meeting
    var onChanged: () -> Void
    /// Set by AppDelegate so the detail view can act on a meeting. Weak: the
    /// controller outlives any window, and this must never keep one alive.
    static weak var controller: MeetingController?

    private enum Tab: String, CaseIterable { case summary = "Summary", transcript = "Transcript", tasks = "Tasks" }
    @State private var tab: Tab = .summary
    @State private var copied = false

    private let store = MeetingStore.shared
    private var summary: MeetingSummary? { store.summary(for: meeting.id) }
    private var transcript: [TranscriptSegment] { store.transcript(for: meeting.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.fpHairline).frame(height: 0.5)
            picker
            ScrollView {
                Group {
                    switch tab {
                    case .summary: summaryPage
                    case .transcript: transcriptPage
                    case .tasks: tasksPage
                    }
                }
                .padding(20)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meeting.title)
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.fpText)
            HStack(spacing: 8) {
                Text(meeting.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11)).foregroundStyle(Color.fpMuted)
                if meeting.duration > 0 {
                    Text("· \(DialogueMerge.timestamp(meeting.duration))")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.fpMuted)
                }
                Spacer()
                Button {
                    copyMarkdown()
                } label: {
                    Label(copied ? "Copied" : "Copy as Markdown", systemImage: "doc.on.doc")
                }
                .font(.system(size: 11))
                Button {
                    exportMarkdown()
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                .font(.system(size: 11))
            }

            // Anything that would otherwise make a result look wrong for no
            // visible reason gets said out loud here.
            if !meeting.capturedSystemAudio {
                notice("Only your microphone was captured — Voicely couldn't hear the other side of this call.")
            }
            if let reason = meeting.failureReason, meeting.status == .failed {
                notice("Couldn't finish: \(reason)")
            }
            if summary?.parseDegraded == true {
                notice("The notes couldn't be structured, so the model's raw reply is shown below.")
            }
            recoveryBar
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
    }

    /// Without this, an interrupted meeting is visible but unrecoverable — the
    /// audio sits on disk with no way to act on it.
    @ViewBuilder
    private var recoveryBar: some View {
        let action = MeetingRecovery.action(for: meeting)
        if action != .none {
            HStack(spacing: 8) {
                switch action {
                case .offerInterrupted:
                    Text("This recording was interrupted — its audio is still here.")
                        .font(.system(size: 11)).foregroundStyle(Color.fpMuted)
                    Button("Transcribe it") { Self.controller?.resume(meeting); onChanged() }
                        .font(.system(size: 11))
                case .resumeTranscription:
                    Text("Recorded but not transcribed.")
                        .font(.system(size: 11)).foregroundStyle(Color.fpMuted)
                    Button("Transcribe") { Self.controller?.resume(meeting); onChanged() }
                        .font(.system(size: 11))
                case .offerRetry:
                    Button("Retry") { Self.controller?.resume(meeting); onChanged() }
                        .font(.system(size: 11))
                case .offerCleanup, .none:
                    EmptyView()
                }
                // Through the controller, never straight to the store: the
                // session has to learn the meeting is gone, or its
                // "finish the unfinished one first" guard blocks every new
                // recording forever.
                Button("Discard") {
                    Self.controller?.discard(meeting)
                    onChanged()
                }
                .font(.system(size: 11))
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    private func notice(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9)).foregroundStyle(.orange)
            Text(text).font(.system(size: 11)).foregroundStyle(Color.fpMuted)
        }
        .padding(.top, 2)
    }

    private var picker: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button {
                    tab = item
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 12, weight: tab == item ? .medium : .regular))
                        .foregroundStyle(tab == item ? Color.fpText : Color.fpMuted)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(tab == item ? Color.fpAccent.opacity(0.10) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    // MARK: - Pages

    @ViewBuilder
    private var summaryPage: some View {
        if let summary {
            VStack(alignment: .leading, spacing: 14) {
                if !summary.summary.isEmpty {
                    Text(summary.summary)
                        .font(.system(size: 13)).foregroundStyle(Color.fpText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                bullets("Key points", summary.keyPoints)
                bullets("Decisions", summary.decisions)
                bullets("Follow-ups", summary.followups)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            empty("No notes for this meeting yet.")
        }
    }

    @ViewBuilder
    private var transcriptPage: some View {
        let segments = transcript
        if segments.isEmpty {
            empty("No transcript for this meeting.")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(segment.speaker.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(segment.speaker == .me ? Color.fpAccent : Color.fpText)
                            Text(DialogueMerge.timestamp(segment.start))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.fpMuted)
                        }
                        Text(segment.text)
                            .font(.system(size: 12)).foregroundStyle(Color.fpText)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var tasksPage: some View {
        if let items = summary?.actionItems, !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "square")
                            .font(.system(size: 11)).foregroundStyle(Color.fpMuted)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 12)).foregroundStyle(Color.fpText)
                                .textSelection(.enabled)
                            // Only shown when the transcript actually said them.
                            if item.owner != nil || item.due != nil {
                                HStack(spacing: 6) {
                                    if let owner = item.owner {
                                        tag(owner, icon: "person")
                                    }
                                    if let due = item.due {
                                        tag(due, icon: "calendar")
                                    }
                                }
                            }
                        }
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            empty("No action items — nothing in this meeting read as a task.")
        }
    }

    private func tag(_ text: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8))
            Text(text).font(.system(size: 10))
        }
        .foregroundStyle(Color.fpMuted)
        .padding(.horizontal, 5).padding(.vertical, 1)
        .background(Color.fpSurface2)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func bullets(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.fpMuted)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").font(.system(size: 12)).foregroundStyle(Color.fpAccent)
                        Text(item).font(.system(size: 12)).foregroundStyle(Color.fpText)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func empty(_ text: String) -> some View {
        VStack {
            Text(text).font(.system(size: 12)).foregroundStyle(Color.fpMuted)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
        }
    }

    // MARK: - Export

    private var markdown: String {
        MeetingMarkdownExporter.export(meeting: meeting, summary: summary, transcript: transcript)
    }

    private func copyMarkdown() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
        copied = true
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = MeetingMarkdownExporter.filename(for: meeting)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? markdown.write(to: url, atomically: true, encoding: .utf8)
    }
}
