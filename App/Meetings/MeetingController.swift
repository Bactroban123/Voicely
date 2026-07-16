import AppKit
import VoicelyCore

/// Drives one meeting: record → transcribe → summarize → saved.
///
/// The meeting-side analogue of `RecordingController`, and deliberately its
/// peer rather than its collaborator: `AppDelegate` holds both, and neither
/// references the other. A meeting can record while the user dictates, and a
/// bug in one vertical must not be able to wedge the other.
@available(macOS 14.2, *)
@MainActor
final class MeetingController {
    /// UI state, published to the menu bar and the Meetings window.
    private(set) var session = MeetingSession()
    private(set) var activeMeeting: Meeting?

    var onStateChange: ((MeetingSession.State) -> Void)?
    var onNotice: ((String) -> Void)?
    /// Fires when a meeting's stored data changes, so an open list refreshes.
    var onMeetingsChanged: (() -> Void)?

    private let store = MeetingStore.shared
    private let settings = SettingsStore.shared
    private var recorder: MeetingRecorder?

    // MARK: - Intent

    func start() { apply(session.handle(.start)) }
    func stop() { apply(session.handle(.stop)) }
    func pause() { apply(session.handle(.pause)) }
    func resume() { apply(session.handle(.resume)) }
    func retry() { apply(session.handle(.retry)) }
    func discard() { apply(session.handle(.discard)) }

    var isRecording: Bool { session.isRecording }

    // MARK: - Effects

    private func apply(_ effect: MeetingSession.Effect) {
        onStateChange?(session.state)
        switch effect {
        case .none:
            break

        case .rejected(let reason):
            onNotice?(reason)

        case .beginRecording(let token):
            beginRecording(token)

        case .pauseRecording, .resumeRecording:
            // v1 records continuously; pause is reserved for the UI that lands
            // with the Meetings window. Nothing to drive yet.
            break

        case .finalizeRecording(let token):
            finalizeRecording(token)

        case .beginTranscription(let token):
            runTranscription(token)

        case .beginSummarization(let token):
            runSummarization(token)

        case .notifyComplete:
            notifyComplete()

        case .discard(let token):
            discardMeeting(token)
        }
    }

    // MARK: - Recording

    private func beginRecording(_ token: MeetingSession.Token) {
        let meeting = Meeting(title: Meeting.defaultTitle(at: Date()), startedAt: Date())
        activeMeeting = meeting
        // Persist the header BEFORE any audio exists: if the app dies mid-call,
        // the next launch finds a meeting stuck in `.recording` and can offer
        // the chunks that were written. Without this, an interrupted meeting is
        // an orphan folder nobody knows about.
        store.save(meeting)
        onMeetingsChanged?()

        let recorder = MeetingRecorder(directory: store.audioFolder(for: meeting.id))
        self.recorder = recorder
        recorder.start { [weak self] result in
            Task { @MainActor in
                guard let self, self.session.isCurrent(token) else { return }
                switch result {
                case .success(let outcome):
                    if case .micOnly(let reason) = outcome {
                        // Never silent: a one-sided recording is the useless
                        // product the previous attempt shipped.
                        self.activeMeeting?.capturedSystemAudio = false
                        if let meeting = self.activeMeeting { self.store.save(meeting) }
                        self.onNotice?("Recording your mic only — couldn't hear the call's audio")
                        VoicelyLog.meeting.warning("system audio unavailable — \(reason)")
                    }
                case .failure(let error):
                    self.apply(self.session.handle(.transcriptionFailed(String(describing: error))))
                    self.onNotice?("Couldn't start recording — \(error)")
                }
            }
        }
    }

    private func finalizeRecording(_ token: MeetingSession.Token) {
        guard let recorder, var meeting = activeMeeting else {
            apply(session.handle(.recordingFinalized(hasAudio: false)))
            return
        }
        recorder.stop { [weak self] mic, system in
            Task { @MainActor in
                guard let self, self.session.isCurrent(token) else { return }
                meeting.endedAt = Date()
                meeting.micChunks = mic.map { $0.0.lastPathComponent }
                meeting.systemChunks = system.map { $0.0.lastPathComponent }
                meeting.micOffsets = mic.map(\.1)
                meeting.systemOffsets = system.map(\.1)
                meeting.status = .recorded
                self.activeMeeting = meeting
                self.store.save(meeting)
                self.onMeetingsChanged?()
                self.recorder = nil
                self.apply(self.session.handle(.recordingFinalized(hasAudio: !mic.isEmpty || !system.isEmpty)))
            }
        }
    }

    // MARK: - Transcription

    private func runTranscription(_ token: MeetingSession.Token) {
        guard var meeting = activeMeeting else { return }
        meeting.status = .transcribing
        store.save(meeting)
        activeMeeting = meeting

        let chunks = store.audioChunks(for: meeting)
        let service = MeetingTranscriptionService(modelID: settings.transcriptionModelID)
        let id = meeting.id
        let keepAudio = settings.keepMeetingAudio

        Task.detached(priority: .utility) { [weak self] in
            do {
                let segments = try await service.transcribe(mic: chunks.mic, system: chunks.system) { progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.session.isCurrent(token) else { return }
                        self.apply(self.session.handle(.transcriptionProgress(progress.fraction)))
                    }
                }
                await MainActor.run { [weak self] in
                    guard let self, self.session.isCurrent(token) else { return }
                    self.store.saveTranscript(segments, for: id)
                    self.activeMeeting?.status = .transcribed
                    if let meeting = self.activeMeeting { self.store.save(meeting) }
                    // Only now is the audio safe to delete: the transcript
                    // exists, and re-summarizing never needs the audio again.
                    if !keepAudio {
                        self.store.deleteAudio(for: id)
                        self.activeMeeting?.audioDeleted = true
                    }
                    self.onMeetingsChanged?()
                    self.apply(self.session.handle(.transcriptReady))
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.session.isCurrent(token) else { return }
                    // The audio survives — the FSM's retry re-transcribes it.
                    self.activeMeeting?.status = .failed
                    self.activeMeeting?.failureReason = String(describing: error)
                    if let meeting = self.activeMeeting { self.store.save(meeting) }
                    self.onMeetingsChanged?()
                    VoicelyLog.meeting.error("transcription failed — \(error)")
                    self.apply(self.session.handle(.transcriptionFailed(String(describing: error))))
                }
            }
        }
    }

    // MARK: - Summarization

    private func runSummarization(_ token: MeetingSession.Token) {
        guard var meeting = activeMeeting else { return }
        meeting.status = .summarizing
        store.save(meeting)
        activeMeeting = meeting

        let id = meeting.id
        let transcript = DialogueMerge.render(store.transcript(for: id))
        let service = MeetingSummaryService(modelID: settings.cleanupModelID,
                                            zeroRetention: settings.zeroRetention)

        Task.detached(priority: .utility) { [weak self] in
            do {
                let summary = try await service.summarize(transcript)
                await MainActor.run { [weak self] in
                    guard let self, self.session.isCurrent(token) else { return }
                    self.store.saveSummary(summary, for: id)
                    self.activeMeeting?.status = .complete
                    if let meeting = self.activeMeeting { self.store.save(meeting) }
                    self.onMeetingsChanged?()
                    self.apply(self.session.handle(.summaryReady))
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.session.isCurrent(token) else { return }
                    // The transcript is already saved. Notes are a nice to
                    // have; the meeting itself is not lost.
                    self.activeMeeting?.status = .failed
                    self.activeMeeting?.failureReason = String(describing: error)
                    if let meeting = self.activeMeeting { self.store.save(meeting) }
                    self.onMeetingsChanged?()
                    VoicelyLog.meeting.error("summarization failed — \(error)")
                    self.apply(self.session.handle(.summarizationFailed(String(describing: error))))
                }
            }
        }
    }

    // MARK: - Completion / discard

    private func notifyComplete() {
        guard let meeting = activeMeeting else { return }
        if case .failed(.summarization, _) = session.state {
            onNotice?("Transcript saved — couldn't write the notes")
        } else {
            onNotice?("Meeting notes ready")
        }
        VoicelyLog.meeting.info("meeting finished — \(meeting.id)")
    }

    private func discardMeeting(_ token: MeetingSession.Token) {
        recorder?.stop { _, _ in }
        recorder = nil
        if let meeting = activeMeeting {
            store.delete(meeting.id)
            onMeetingsChanged?()
        }
        activeMeeting = nil
        onStateChange?(session.state)
    }
}
