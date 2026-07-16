import Foundation
import VoicelyCore

/// Meetings on disk, one folder each:
///
///     Meetings/<uuid>/
///       meeting.json      — header: title, times, status, chunk manifest
///       transcript.json   — [TranscriptSegment]
///       summary.json      — MeetingSummary
///       audio/            — mic-0000.caf, system-0000.caf, … (deleted after
///                           transcription unless the user keeps them)
///
/// A folder per meeting rather than one big file (the way dictation history
/// works) because a meeting owns files, and because `list()` must stay fast
/// with a hundred of them — showing the list must not mean parsing an hour of
/// transcript. Each part loads only when opened.
@available(macOS 14.2, *)
final class MeetingStore {
    static let shared = MeetingStore()

    private let root: URL
    private let queue = DispatchQueue(label: "com.voicely.meeting.store")

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.root = support.appendingPathComponent("Voicely/Meetings", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    // MARK: - Layout

    func folder(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func audioFolder(for id: UUID) -> URL { folder(for: id).appendingPathComponent("audio", isDirectory: true) }
    private func headerURL(_ id: UUID) -> URL { folder(for: id).appendingPathComponent("meeting.json") }
    private func transcriptURL(_ id: UUID) -> URL { folder(for: id).appendingPathComponent("transcript.json") }
    private func summaryURL(_ id: UUID) -> URL { folder(for: id).appendingPathComponent("summary.json") }

    // MARK: - Headers

    /// Every meeting, newest first. Reads only the headers.
    func list() -> [Meeting] {
        queue.sync {
            let folders = (try? FileManager.default.contentsOfDirectory(at: root,
                                                                        includingPropertiesForKeys: nil)) ?? []
            return folders
                .compactMap { folder -> Meeting? in
                    let url = folder.appendingPathComponent("meeting.json")
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return try? JSONDecoder().decode(Meeting.self, from: data)
                }
                .sorted { $0.startedAt > $1.startedAt }
        }
    }

    func load(_ id: UUID) -> Meeting? {
        queue.sync {
            guard let data = try? Data(contentsOf: headerURL(id)) else { return nil }
            return try? JSONDecoder().decode(Meeting.self, from: data)
        }
    }

    @discardableResult
    func save(_ meeting: Meeting) -> Bool {
        queue.sync {
            do {
                try FileManager.default.createDirectory(at: audioFolder(for: meeting.id),
                                                        withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                // Atomic: a half-written header on a crash would make the
                // meeting unreadable, losing a recording that's on disk.
                try encoder.encode(meeting).write(to: headerURL(meeting.id), options: .atomic)
                return true
            } catch {
                VoicelyLog.meeting.error("couldn't save meeting header — \(error)")
                return false
            }
        }
    }

    // MARK: - Parts

    func saveTranscript(_ segments: [TranscriptSegment], for id: UUID) {
        queue.sync {
            do {
                try JSONEncoder().encode(segments).write(to: transcriptURL(id), options: .atomic)
            } catch {
                VoicelyLog.meeting.error("couldn't save transcript — \(error)")
            }
        }
    }

    func transcript(for id: UUID) -> [TranscriptSegment] {
        queue.sync {
            guard let data = try? Data(contentsOf: transcriptURL(id)) else { return [] }
            return (try? JSONDecoder().decode([TranscriptSegment].self, from: data)) ?? []
        }
    }

    func saveSummary(_ summary: MeetingSummary, for id: UUID) {
        queue.sync {
            do {
                try JSONEncoder().encode(summary).write(to: summaryURL(id), options: .atomic)
            } catch {
                VoicelyLog.meeting.error("couldn't save summary — \(error)")
            }
        }
    }

    func summary(for id: UUID) -> MeetingSummary? {
        queue.sync {
            guard let data = try? Data(contentsOf: summaryURL(id)) else { return nil }
            return try? JSONDecoder().decode(MeetingSummary.self, from: data)
        }
    }

    // MARK: - Audio lifecycle

    /// Chunk URLs paired with their offsets, for transcription.
    func audioChunks(for meeting: Meeting) -> (mic: [(URL, RecordedChunk)], system: [(URL, RecordedChunk)]) {
        let base = audioFolder(for: meeting.id)
        func pair(_ names: [String], _ offsets: [RecordedChunk]) -> [(URL, RecordedChunk)] {
            zip(names, offsets).compactMap { name, offset in
                let url = base.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                return (url, offset)
            }
        }
        return (pair(meeting.micChunks, meeting.micOffsets), pair(meeting.systemChunks, meeting.systemOffsets))
    }

    /// Deletes the audio once a transcript exists.
    ///
    /// Keyed on the transcript, not on the summary: re-running summarization
    /// never needs the audio again, so there's no gap — but deleting before a
    /// transcript exists would destroy a meeting that can't be re-recorded.
    func deleteAudio(for id: UUID) {
        queue.sync {
            guard var meeting = try? JSONDecoder().decode(Meeting.self, from: Data(contentsOf: headerURL(id))),
                  FileManager.default.fileExists(atPath: transcriptURL(id).path) else {
                VoicelyLog.meeting.warning("refusing to delete audio for \(id): no transcript on disk")
                return
            }
            try? FileManager.default.removeItem(at: audioFolder(for: id))
            try? FileManager.default.createDirectory(at: audioFolder(for: id), withIntermediateDirectories: true)
            meeting.audioDeleted = true
            if let data = try? JSONEncoder().encode(meeting) {
                try? data.write(to: headerURL(id), options: .atomic)
            }
        }
    }

    func delete(_ id: UUID) {
        queue.sync { try? FileManager.default.removeItem(at: folder(for: id)) }
    }

    // MARK: - Recovery

    /// Meetings whose recording never finished — the app was killed or crashed
    /// mid-call. Their chunks are still valid audio, so the user is offered a
    /// choice rather than having the meeting silently vanish or silently resume.
    func needingRecovery() -> [Meeting] {
        list().filter { $0.wasInterrupted || ($0.status == .recorded && $0.canTranscribe) }
    }

    /// Bytes used by all meeting audio, for the retention UI.
    func audioBytes() -> Int64 {
        list().reduce(0) { total, meeting in
            let folder = audioFolder(for: meeting.id)
            let files = (try? FileManager.default.contentsOfDirectory(at: folder,
                                                                      includingPropertiesForKeys: [.fileSizeKey])) ?? []
            return total + files.reduce(0) { sum, url in
                sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
    }
}
