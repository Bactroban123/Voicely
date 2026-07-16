import Foundation

/// Maps positions inside per-chunk transcripts onto the meeting's timeline.
///
/// Each track is recorded as a sequence of chunk files and transcribed one
/// chunk at a time, so every engine result starts its clock at zero. To place a
/// segment on the meeting's timeline you add the total duration of everything
/// before its chunk.
///
/// The durations must be *measured*, never assumed: chunks are nominally 5
/// minutes, but the last one is short, and a rotation failure or a device
/// change can make any of them short. Assuming the nominal length would drift
/// every timestamp after the first anomaly — and drift is silent, which is the
/// failure mode this project keeps finding the hard way.
public struct ChunkTimeline: Equatable {
    /// Measured duration of each chunk, in recording order.
    public let durations: [TimeInterval]
    /// Cumulative start offset of each chunk on the meeting timeline.
    public let offsets: [TimeInterval]

    public init(durations: [TimeInterval]) {
        self.durations = durations
        var running: TimeInterval = 0
        var offsets: [TimeInterval] = []
        offsets.reserveCapacity(durations.count)
        for duration in durations {
            offsets.append(running)
            running += max(0, duration)
        }
        self.offsets = offsets
    }

    /// Total measured length of the track.
    public var total: TimeInterval { durations.reduce(0) { $0 + max(0, $1) } }

    /// Where chunk `index` starts on the meeting timeline; nil if out of range.
    public func offset(ofChunk index: Int) -> TimeInterval? {
        offsets.indices.contains(index) ? offsets[index] : nil
    }

    /// Shifts a chunk-relative segment onto the meeting timeline.
    /// Returns nil for an unknown chunk rather than silently placing it at zero.
    public func place(_ segment: TranscriptSegment, fromChunk index: Int) -> TranscriptSegment? {
        guard let offset = offset(ofChunk: index) else { return nil }
        return TranscriptSegment(speaker: segment.speaker,
                                 text: segment.text,
                                 start: segment.start + offset,
                                 end: segment.end + offset)
    }

    /// Shifts a whole chunk's worth of segments onto the meeting timeline.
    public func place(_ segments: [TranscriptSegment], fromChunk index: Int) -> [TranscriptSegment] {
        guard let offset = offset(ofChunk: index) else { return [] }
        return segments.map {
            TranscriptSegment(speaker: $0.speaker, text: $0.text,
                              start: $0.start + offset, end: $0.end + offset)
        }
    }
}
