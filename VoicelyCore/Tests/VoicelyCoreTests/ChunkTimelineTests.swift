import XCTest
@testable import VoicelyCore

final class ChunkTimelineTests: XCTestCase {
    private func seg(_ text: String, _ start: TimeInterval, _ end: TimeInterval) -> TranscriptSegment {
        TranscriptSegment(speaker: .them, text: text, start: start, end: end)
    }

    func testDurationFallbackAccumulatesWhenNoWallClockIsAvailable() {
        let timeline = ChunkTimeline(durations: [300, 300, 120])
        XCTAssertEqual(timeline.offsets, [0, 300, 600])
        XCTAssertEqual(timeline.total, 720)
    }

    func testShortChunksDoNotDriftLaterTimestamps() {
        // The failure this type exists to prevent: chunk 1 was cut short (a
        // rotation failure or a device change). Assuming the nominal 5 minutes
        // would put everything after it 120s late, silently and forever.
        let timeline = ChunkTimeline(durations: [300, 180, 300])
        XCTAssertEqual(timeline.offset(ofChunk: 2), 480)          // not 600
        let placed = timeline.place(seg("hello", 10, 12), fromChunk: 2)
        XCTAssertEqual(placed?.start, 490)
    }

    func testPlaceShiftsSegmentsOntoTheMeetingTimeline() {
        let timeline = ChunkTimeline(durations: [300, 300])
        let placed = timeline.place([seg("a", 0, 1), seg("b", 5, 6)], fromChunk: 1)
        XCTAssertEqual(placed.map(\.start), [300, 305])
        XCTAssertEqual(placed.map(\.end), [301, 306])
        XCTAssertEqual(placed.map(\.text), ["a", "b"])
        XCTAssertEqual(placed.map(\.speaker), [.them, .them])
    }

    func testFirstChunkIsUnshifted() {
        let timeline = ChunkTimeline(durations: [300])
        XCTAssertEqual(timeline.place(seg("x", 4, 5), fromChunk: 0)?.start, 4)
    }

    func testUnknownChunkReturnsNilRatherThanPlacingAtZero() {
        // Silently placing an unknown chunk at 0 would scramble the dialogue
        // order instead of failing visibly.
        let timeline = ChunkTimeline(durations: [300])
        XCTAssertNil(timeline.place(seg("x", 0, 1), fromChunk: 5))
        XCTAssertNil(timeline.offset(ofChunk: 5))
        XCTAssertNil(timeline.offset(ofChunk: -1))
        XCTAssertTrue(timeline.place([seg("x", 0, 1)], fromChunk: 5).isEmpty)
    }

    func testEmptyTimeline() {
        let timeline = ChunkTimeline(durations: [])
        XCTAssertEqual(timeline.total, 0)
        XCTAssertNil(timeline.offset(ofChunk: 0))
    }

    func testUnmeasurableChunksAssumeTheNominalLengthRatherThanCollapsing() {
        // A chunk that can't be measured (unreadable file, or one that opened
        // but never took a write) still occupied real time. Advancing by 0
        // would put every later segment ~5 min early on THIS track only —
        // which doesn't just shift the transcript, it interleaves the wrong
        // speaker's turns into the merged dialogue.
        let timeline = ChunkTimeline(durations: [300, 0, 300], assumedDuration: 300)
        XCTAssertEqual(timeline.offsets, [0, 300, 600])
        let negative = ChunkTimeline(durations: [300, -50, 100], assumedDuration: 300)
        XCTAssertEqual(negative.offsets, [0, 300, 600])
    }

    func testWallClockChunksArePreferredOverSummedDurations() {
        // The real path: offsets measured against the meeting's own clock, so a
        // gap in recorded audio (device switch, dropped samples) can't drift
        // later timestamps.
        let timeline = ChunkTimeline(chunks: [
            RecordedChunk(startOffset: 0, duration: 300),
            RecordedChunk(startOffset: 305, duration: 295),   // 5s gap: device switch
        ])
        XCTAssertEqual(timeline.offset(ofChunk: 1), 305)      // not 300
        XCTAssertEqual(timeline.place(seg("x", 10, 11), fromChunk: 1)?.start, 315)
    }

    func testBothTracksShareOneClockSoTheyCannotDriftApart() {
        // The tap comes up after the mic, so the system track's first chunk
        // starts later — measured against the SAME t=0, not its own.
        let mic = ChunkTimeline(chunks: [RecordedChunk(startOffset: 0, duration: 300)])
        let system = ChunkTimeline(chunks: [RecordedChunk(startOffset: 0.4, duration: 299.6)])
        let me = mic.place([TranscriptSegment(speaker: .me, text: "hi", start: 0, end: 1)], fromChunk: 0)
        let them = system.place([TranscriptSegment(speaker: .them, text: "hello", start: 0.2, end: 1.2)], fromChunk: 0)
        let merged = DialogueMerge.merge(me: me, them: them)
        XCTAssertEqual(merged.first?.speaker, .me)            // me really did speak first
        XCTAssertEqual(them.first?.start ?? 0, 0.6, accuracy: 1e-9)   // 0.4 skew + 0.2 in-chunk
    }

    func testTwoTracksOfDifferingLengthsPlaceIndependently() {
        // The tap can start slightly after the mic, so the tracks' chunk
        // boundaries need not line up — each track owns its own timeline.
        let mic = ChunkTimeline(durations: [300, 300])
        let system = ChunkTimeline(durations: [298, 300])
        XCTAssertEqual(mic.offset(ofChunk: 1), 300)
        XCTAssertEqual(system.offset(ofChunk: 1), 298)
    }

    /// The end-to-end shape S2 relies on: per-chunk engine output placed onto
    /// the timeline, then merged into a dialogue.
    func testPlacedChunksMergeIntoACoherentDialogue() {
        let micTimeline = ChunkTimeline(durations: [300, 300])
        let systemTimeline = ChunkTimeline(durations: [300, 300])

        // Each engine result starts its clock at zero within its own chunk.
        let meChunk0 = [TranscriptSegment(speaker: .me, text: "kicking off", start: 1, end: 2)]
        let themChunk0 = [TranscriptSegment(speaker: .them, text: "go ahead", start: 3, end: 4)]
        let meChunk1 = [TranscriptSegment(speaker: .me, text: "wrapping up", start: 10, end: 11)]

        let me = micTimeline.place(meChunk0, fromChunk: 0) + micTimeline.place(meChunk1, fromChunk: 1)
        let them = systemTimeline.place(themChunk0, fromChunk: 0)
        let merged = DialogueMerge.merge(me: me, them: them)

        XCTAssertEqual(merged.map(\.text), ["kicking off", "go ahead", "wrapping up"])
        XCTAssertEqual(merged.last?.start, 310)   // chunk 1 offset + 10
    }
}
