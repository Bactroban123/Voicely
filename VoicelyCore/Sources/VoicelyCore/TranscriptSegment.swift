import Foundation

/// Who said it. There are exactly two, and they're decided by *which audio
/// track a sample landed in* — the microphone is you, the system output mixdown
/// is everyone else. No diarization, no clustering, no guessing.
///
/// The cost of that simplicity is honest: "them" is one bucket, so a four-person
/// call reads as a single other voice. Splitting it needs real diarization
/// (both pinned ML packages ship one), which is deliberately out of v1.
public enum Speaker: String, Codable, Equatable, CaseIterable {
    case me
    case them

    /// Label used in the transcript view and the Markdown export.
    public var label: String {
        switch self {
        case .me: return "Me"
        case .them: return "Them"
        }
    }
}

/// A contiguous run of speech from one speaker, positioned on the meeting's
/// timeline (seconds from the moment recording started, not from the start of
/// whatever chunk it came out of).
public struct TranscriptSegment: Codable, Equatable {
    public let speaker: Speaker
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(speaker: Speaker, text: String, start: TimeInterval, end: TimeInterval) {
        self.speaker = speaker
        self.text = text
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { max(0, end - start) }

    /// Same-speaker segments this close together are one utterance, not two.
    public func adjoins(_ other: TranscriptSegment, within gap: TimeInterval) -> Bool {
        speaker == other.speaker && other.start - end <= gap
    }
}
