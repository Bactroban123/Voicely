import Foundation

/// A recorded meeting: what it is, how far it got, and what's on disk for it.
///
/// Stored per-meeting rather than in one big list (the way history is) because
/// a meeting owns files — audio chunks, a transcript, notes — and because the
/// list view must stay fast when there are a hundred of them: reading a
/// meeting's header must not mean parsing an hour of transcript.
public struct Meeting: Codable, Equatable, Identifiable {
    /// How far this meeting got. Persisted so an interrupted meeting is
    /// recognisable on the next launch instead of looking finished.
    public enum Status: String, Codable, Equatable {
        /// Recording was still in progress — i.e. the app died mid-meeting.
        case recording
        /// Audio is on disk, not yet transcribed.
        case recorded
        case transcribing
        case transcribed
        case summarizing
        case complete
        case failed
    }

    public let id: UUID
    public var title: String
    public let startedAt: Date
    public var endedAt: Date?
    public var status: Status
    /// False when the system-audio tap was unavailable, so only "Me" was
    /// captured. Worth surfacing: it explains a one-sided transcript.
    public var capturedSystemAudio: Bool
    /// Audio chunk filenames (inside the meeting's own folder), in order.
    public var micChunks: [String]
    public var systemChunks: [String]
    /// Wall-clock offsets for those chunks, so transcription can place them.
    public var micOffsets: [RecordedChunk]
    public var systemOffsets: [RecordedChunk]
    /// Set once the audio has been transcribed and is safe to delete.
    public var audioDeleted: Bool
    public var failureReason: String?

    public init(id: UUID = UUID(),
                title: String,
                startedAt: Date,
                endedAt: Date? = nil,
                status: Status = .recording,
                capturedSystemAudio: Bool = true,
                micChunks: [String] = [],
                systemChunks: [String] = [],
                micOffsets: [RecordedChunk] = [],
                systemOffsets: [RecordedChunk] = [],
                audioDeleted: Bool = false,
                failureReason: String? = nil) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.capturedSystemAudio = capturedSystemAudio
        self.micChunks = micChunks
        self.systemChunks = systemChunks
        self.micOffsets = micOffsets
        self.systemOffsets = systemOffsets
        self.audioDeleted = audioDeleted
        self.failureReason = failureReason
    }

    public var duration: TimeInterval {
        guard let endedAt else { return 0 }
        return max(0, endedAt.timeIntervalSince(startedAt))
    }

    /// A meeting whose recording never finished — the app was killed or crashed
    /// mid-call. The chunks it did write are still valid audio.
    public var wasInterrupted: Bool { status == .recording }

    /// Whether re-running transcription is possible from what's on disk.
    public var canTranscribe: Bool {
        !audioDeleted && !(micChunks.isEmpty && systemChunks.isEmpty)
    }

    /// A default title from the start time — "Meeting at 2:14 PM". Users can
    /// rename; nothing derives meaning from this.
    public static func defaultTitle(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "Meeting at \(formatter.string(from: date))"
    }
}

extension RecordedChunk: Codable {
    enum CodingKeys: String, CodingKey { case startOffset, duration }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(startOffset: try container.decode(TimeInterval.self, forKey: .startOffset),
                  duration: try container.decode(TimeInterval.self, forKey: .duration))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startOffset, forKey: .startOffset)
        try container.encode(duration, forKey: .duration)
    }
}
