import Foundation

/// Where a recorded chunk sits on the meeting's timeline.
///
/// `startOffset` is wall-clock seconds since the meeting began, captured when
/// the chunk took its first sample — **not** derived by summing the durations
/// of everything before it. That distinction is the whole point of this type:
///
/// - The two tracks don't start together. The mic engine starts before the
///   system tap (creating the aggregate device takes time), so summing
///   durations gives each track a *different* t=0 and biases one speaker's
///   timestamps early by a few hundred ms — fabricating overlap where the
///   reply politely waited.
/// - Recorded audio is not the same as elapsed time. A device switch rebuilds
///   the mic engine, a full disk fails a chunk open, a ring overflow drops
///   samples: in each case the clock advances but the file doesn't grow. Summed
///   durations then run *early* by the lost time, on one track only, which
///   doesn't merely shift the transcript — it interleaves the wrong speaker's
///   turns. Wall-clock offsets absorb every one of those, silently and
///   correctly.
public struct RecordedChunk: Equatable {
    /// Seconds from the start of the meeting to this chunk's first sample.
    public let startOffset: TimeInterval
    /// Measured length of the chunk's audio, for reference/diagnostics.
    public let duration: TimeInterval

    public init(startOffset: TimeInterval, duration: TimeInterval) {
        self.startOffset = startOffset
        self.duration = duration
    }
}

/// Maps positions inside per-chunk transcripts onto the meeting's timeline.
///
/// Each chunk is transcribed on its own, so every engine result starts its clock
/// at zero; placing it means adding that chunk's offset.
public struct ChunkTimeline: Equatable {
    public let chunks: [RecordedChunk]

    /// Preferred: offsets measured against the meeting's own clock.
    public init(chunks: [RecordedChunk]) {
        self.chunks = chunks
    }

    /// Fallback for when only durations are known (no wall-clock stamps).
    /// Accumulates them, and treats a non-positive duration as `assumedDuration`
    /// rather than zero — a chunk that couldn't be measured occupied real time,
    /// and advancing by 0 would put everything after it wildly early.
    public init(durations: [TimeInterval], assumedDuration: TimeInterval = 300) {
        var running: TimeInterval = 0
        var chunks: [RecordedChunk] = []
        chunks.reserveCapacity(durations.count)
        for duration in durations {
            let effective = duration > 0 ? duration : assumedDuration
            chunks.append(RecordedChunk(startOffset: running, duration: effective))
            running += effective
        }
        self.chunks = chunks
    }

    /// Offsets of each chunk, in order.
    public var offsets: [TimeInterval] { chunks.map(\.startOffset) }

    /// End of the last chunk on the meeting timeline.
    public var total: TimeInterval {
        chunks.map { $0.startOffset + max(0, $0.duration) }.max() ?? 0
    }

    /// Where chunk `index` starts; nil if out of range.
    public func offset(ofChunk index: Int) -> TimeInterval? {
        chunks.indices.contains(index) ? chunks[index].startOffset : nil
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
