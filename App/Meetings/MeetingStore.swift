import AVFoundation
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
    ///
    /// Works on the reconciled meeting, so a crashed recording's files are
    /// found even though its manifest is empty.
    func audioChunks(for meeting: Meeting) -> (mic: [(URL, RecordedChunk)], system: [(URL, RecordedChunk)]) {
        let meeting = reconciled(meeting)
        let base = audioFolder(for: meeting.id)

        func pair(_ names: [String], _ offsets: [RecordedChunk]) -> [(URL, RecordedChunk)] {
            let urls = names.map { base.appendingPathComponent($0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !urls.isEmpty else { return [] }

            // An interrupted meeting has files but no offsets (they're written
            // at stop). zip() would silently return NOTHING here — the audio
            // would survive on disk and still never be transcribed. Fall back
            // to measuring the files and summing their durations.
            guard offsets.count == names.count else {
                let timeline = ChunkTimeline(durations: urls.map(Self.duration(of:)))
                return Array(zip(urls, timeline.chunks))
            }
            return zip(urls, offsets).map { ($0, $1) }
        }
        return (pair(meeting.micChunks, meeting.micOffsets), pair(meeting.systemChunks, meeting.systemOffsets))
    }

    private static func duration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
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

    /// Rebuilds a meeting's chunk manifest from what is actually on disk.
    ///
    /// The header only lists chunks after a CLEAN STOP — the recorder writes
    /// the files continuously, but `finalizeRecording` is what records their
    /// names. So a crashed meeting has real audio on disk and an *empty*
    /// manifest. Trusting the manifest made recovery classify it as an empty
    /// husk and delete it: the recovery destroying exactly what it exists to
    /// save. Observed in the field, 2026-07-16.
    func reconciled(_ meeting: Meeting) -> Meeting {
        guard meeting.micChunks.isEmpty, meeting.systemChunks.isEmpty, !meeting.audioDeleted else {
            return meeting
        }
        let folder = audioFolder(for: meeting.id)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let mic = files.filter { $0.hasPrefix("mic-") && $0.hasSuffix(".caf") }.sorted()
        let system = files.filter { $0.hasPrefix("system-") && $0.hasSuffix(".caf") }.sorted()
        guard !mic.isEmpty || !system.isEmpty else { return meeting }

        var out = meeting
        out.micChunks = mic
        out.systemChunks = system
        // Offsets are written at stop, so an interrupted meeting has none. Left
        // empty on purpose: `audioChunks` then measures the files and sums
        // their durations, which is exactly what ChunkTimeline's fallback
        // initialiser exists for.
        out.micOffsets = []
        out.systemOffsets = []
        return out
    }

    /// Meetings worth telling the user about at launch: interrupted recordings,
    /// un-transcribed audio, retryable failures. The rules live in
    /// `MeetingRecovery` so they're testable without a filesystem — but they're
    /// asked about RECONCILED meetings, or a crashed one looks empty.
    func needingRecovery() -> [Meeting] {
        MeetingRecovery.needingAttention(list().map(reconciled))
    }

    /// Deletes husks that are genuinely empty — a header from a start that
    /// failed before a single byte was written. Silent because there is, by
    /// definition, nothing to lose.
    ///
    /// Deliberately paranoid: it re-checks the filesystem itself rather than
    /// trusting any manifest, because the cost of being wrong here is somebody
    /// losing an hour of a call they cannot re-record.
    func pruneDisposable() {
        let disposable = list().map(reconciled).filter { meeting in
            guard MeetingRecovery.isDisposable(meeting) else { return false }
            let hasAudio = !((try? FileManager.default.contentsOfDirectory(atPath: audioFolder(for: meeting.id).path))?
                .filter { $0.hasSuffix(".caf") } ?? []).isEmpty
            let hasTranscript = !transcript(for: meeting.id).isEmpty
            if hasAudio || hasTranscript {
                VoicelyLog.meeting.warning("refusing to prune \(meeting.id): it still has audio or a transcript")
                return false
            }
            return true
        }
        guard !disposable.isEmpty else { return }
        for meeting in disposable { delete(meeting.id) }
        VoicelyLog.meeting.info("pruned \(disposable.count) empty meeting folder(s)")
    }

    /// Free space on the volume the meetings live on — not the boot volume,
    /// which may be a different disk entirely.
    func freeBytes() -> Int64 {
        let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? .max
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
