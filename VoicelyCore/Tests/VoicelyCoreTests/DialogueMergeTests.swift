import XCTest
@testable import VoicelyCore

final class DialogueMergeTests: XCTestCase {
    private func me(_ text: String, _ start: TimeInterval, _ end: TimeInterval) -> TranscriptSegment {
        TranscriptSegment(speaker: .me, text: text, start: start, end: end)
    }
    private func them(_ text: String, _ start: TimeInterval, _ end: TimeInterval) -> TranscriptSegment {
        TranscriptSegment(speaker: .them, text: text, start: start, end: end)
    }

    // MARK: - Merge ordering

    func testAlternatingTurnsInterleaveByTime() {
        // Their two pieces are 1s apart — inside the coalesce gap — so they
        // become one turn, giving the me/them/me shape a reader expects.
        let merged = DialogueMerge.merge(
            me: [me("hello", 0, 1), me("sounds good", 6, 7)],
            them: [them("hi there", 2, 3), them("shall we start", 4, 5)])
        XCTAssertEqual(merged.map(\.speaker), [.me, .them, .me])
        XCTAssertEqual(merged.map(\.text), ["hello", "hi there shall we start", "sounds good"])
    }

    func testTurnsSeparatedByRealPausesStayDistinct() {
        // Same shape, but their pieces are 3s apart: two separate turns.
        let merged = DialogueMerge.merge(
            me: [me("hello", 0, 1), me("sounds good", 10, 11)],
            them: [them("hi there", 2, 3), them("shall we start", 6, 7)])
        XCTAssertEqual(merged.map(\.speaker), [.me, .them, .them, .me])
    }

    func testTracksAreOrderedByTimeNotByTrack() {
        // Them speaks first: the mic track must not win just by being passed first.
        let merged = DialogueMerge.merge(me: [me("second", 10, 11)], them: [them("first", 1, 2)])
        XCTAssertEqual(merged.map(\.text), ["first", "second"])
    }

    func testSimultaneousSpeechIsKeptAsSeparateLines() {
        // People talk over each other; a readable approximation beats a mangled
        // word-level interleave.
        let merged = DialogueMerge.merge(me: [me("no wait", 5, 7)], them: [them("so anyway", 5, 8)])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].speaker, .me)   // deterministic tie-break
        XCTAssertEqual(merged[1].speaker, .them)
    }

    func testEmptyAndWhitespaceSegmentsAreDropped() {
        let merged = DialogueMerge.merge(
            me: [me("", 0, 1), me("   ", 1, 2), me("real words", 3, 4)],
            them: [them("\n\t", 5, 6)])
        XCTAssertEqual(merged.map(\.text), ["real words"])
    }

    func testOneSidedMeetingStillProducesATranscript() {
        // The degraded mic-only case (tap refused) must still merge cleanly.
        let merged = DialogueMerge.merge(me: [me("just me", 0, 2)], them: [])
        XCTAssertEqual(merged.map(\.speaker), [.me])
    }

    func testBothTracksEmpty() {
        XCTAssertTrue(DialogueMerge.merge(me: [], them: []).isEmpty)
    }

    // MARK: - Coalescing

    func testAdjacentSameSpeakerSegmentsJoinIntoOneUtterance() {
        // ASR emits per-token/per-VAD pieces; without this the transcript reads
        // as one line per breath.
        let merged = DialogueMerge.merge(me: [me("so", 0, 0.4), me("I think", 0.6, 1.2), me("we should ship", 1.4, 2.5)],
                                         them: [])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].text, "so I think we should ship")
        XCTAssertEqual(merged[0].start, 0)
        XCTAssertEqual(merged[0].end, 2.5)
    }

    func testAPauseLongerThanTheGapStartsANewLine() {
        let merged = DialogueMerge.merge(me: [me("first thought", 0, 1), me("new thought", 5, 6)], them: [])
        XCTAssertEqual(merged.count, 2)
    }

    func testDifferentSpeakersNeverCoalesceEvenBackToBack() {
        let merged = DialogueMerge.merge(me: [me("yes", 1.0, 1.2)], them: [them("right", 1.3, 1.5)])
        XCTAssertEqual(merged.count, 2)
    }

    func testCoalescingNeverMovesTheEndTimeBackwards() {
        // Overlapping ASR windows can emit a later segment that ends earlier.
        let merged = DialogueMerge.coalesce([me("long bit", 0, 10), me("tail", 1, 2)])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].end, 10)
    }

    func testGapIsConfigurable() {
        let segments = [me("a", 0, 1), me("b", 3, 4)]
        XCTAssertEqual(DialogueMerge.coalesce(segments, gap: 0.5).count, 2)
        XCTAssertEqual(DialogueMerge.coalesce(segments, gap: 5).count, 1)
    }

    // MARK: - Rendering

    func testRenderProducesReadableMarkdown() {
        let merged = DialogueMerge.merge(me: [me("hello", 0, 1)], them: [them("hi", 2, 3)])
        XCTAssertEqual(DialogueMerge.render(merged), "**Me:** hello\n\n**Them:** hi")
    }

    func testRenderWithTimestamps() {
        let merged = [them("later on", 3_725, 3_730)]   // 1:02:05
        XCTAssertEqual(DialogueMerge.render(merged, includeTimestamps: true), "[1:02:05] **Them:** later on")
    }

    func testTimestampFormatting() {
        XCTAssertEqual(DialogueMerge.timestamp(0), "0:00")
        XCTAssertEqual(DialogueMerge.timestamp(5), "0:05")
        XCTAssertEqual(DialogueMerge.timestamp(65), "1:05")
        XCTAssertEqual(DialogueMerge.timestamp(599), "9:59")
        XCTAssertEqual(DialogueMerge.timestamp(3_600), "1:00:00")
        XCTAssertEqual(DialogueMerge.timestamp(3_661), "1:01:01")
    }

    // MARK: - Realistic shape

    func testATypicalCallReadsAsDialogue() {
        let merged = DialogueMerge.merge(
            me: [me("hey", 0.0, 0.3), me("can you hear me", 0.5, 1.6), me("great", 8.0, 8.4)],
            them: [them("yep", 2.0, 2.3), them("loud and clear", 2.5, 3.6),
                   them("so about the launch", 4.0, 5.5)])
        XCTAssertEqual(DialogueMerge.render(merged), """
        **Me:** hey can you hear me

        **Them:** yep loud and clear so about the launch

        **Me:** great
        """)
    }
}
