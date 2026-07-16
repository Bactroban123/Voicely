import XCTest
@testable import VoicelyCore

final class TokenGroupingTests: XCTestCase {
    /// Verbatim token stream captured from Parakeet v3 transcribing real speech
    /// ("Hey, can you hear me okay?"). Note the leading spaces inside the
    /// tokens — this fixture is the whole point of the file.
    private let realTokens: [TimedToken] = [
        TimedToken(text: " He", start: 0.00, end: 0.24),
        TimedToken(text: "y", start: 0.16, end: 0.32),
        TimedToken(text: ",", start: 0.32, end: 0.48),
        TimedToken(text: " can", start: 0.48, end: 0.64),
        TimedToken(text: " you", start: 0.64, end: 0.80),
        TimedToken(text: " he", start: 0.80, end: 0.96),
        TimedToken(text: "ar", start: 0.96, end: 1.12),
        TimedToken(text: " me", start: 1.12, end: 1.28),
        TimedToken(text: " o", start: 1.28, end: 1.52),
        TimedToken(text: "kay", start: 1.52, end: 1.76),
        TimedToken(text: "?", start: 1.76, end: 1.92),
    ]

    /// The regression this file exists for: trimming each token before joining
    /// welds every word together. It compiles, it passes any test written from
    /// hand-made segments, and only real audio exposes it.
    func testTokensAreJoinedVerbatimAndKeepTheirSpacing() {
        let segments = TokenGrouping.segments(from: realTokens, speaker: .me)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].text, "Hey, can you hear me okay?")
        XCTAssertFalse(segments[0].text.contains("Hey,can"), "tokens were trimmed before joining")
    }

    func testSubwordTokensJoinWithoutSpaces() {
        // "he" + "ar" must be "hear", not "he ar".
        let segments = TokenGrouping.segments(from: [
            TimedToken(text: " he", start: 0, end: 0.2),
            TimedToken(text: "ar", start: 0.2, end: 0.4),
        ], speaker: .me)
        XCTAssertEqual(segments[0].text, "hear")
    }

    func testLeadingWhitespaceIsTrimmedFromTheSegmentNotTheTokens() {
        let segments = TokenGrouping.segments(from: [TimedToken(text: " Hello", start: 0, end: 1)], speaker: .me)
        XCTAssertEqual(segments[0].text, "Hello")
    }

    // MARK: - Utterance splitting

    func testAPauseStartsANewUtterance() {
        let segments = TokenGrouping.segments(from: [
            TimedToken(text: " Hello", start: 0.0, end: 0.5),
            TimedToken(text: " there", start: 0.5, end: 1.0),
            TimedToken(text: " Anyway", start: 5.0, end: 5.5),   // 4s pause
            TimedToken(text: " moving", start: 5.5, end: 6.0),
        ], speaker: .them)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].text, "Hello there")
        XCTAssertEqual(segments[1].text, "Anyway moving")
        XCTAssertEqual(segments[0].start, 0.0)
        XCTAssertEqual(segments[0].end, 1.0)
        XCTAssertEqual(segments[1].start, 5.0)
    }

    func testShortGapsDoNotSplit() {
        let segments = TokenGrouping.segments(from: [
            TimedToken(text: " um", start: 0.0, end: 0.3),
            TimedToken(text: " so", start: 0.9, end: 1.2),   // 0.6s < 0.8 gap
        ], speaker: .me)
        XCTAssertEqual(segments.count, 1)
    }

    func testGapIsConfigurable() {
        let tokens = [
            TimedToken(text: " a", start: 0.0, end: 0.2),
            TimedToken(text: " b", start: 1.2, end: 1.4),   // 1.0s pause
        ]
        XCTAssertEqual(TokenGrouping.segments(from: tokens, speaker: .me, gap: 0.5).count, 2)
        XCTAssertEqual(TokenGrouping.segments(from: tokens, speaker: .me, gap: 2.0).count, 1)
    }

    func testTimestampsSpanTheUtterance() {
        let segments = TokenGrouping.segments(from: realTokens, speaker: .me)
        XCTAssertEqual(segments[0].start, 0.00)
        XCTAssertEqual(segments[0].end, 1.92)
    }

    func testOverlappingTokenWindowsNeverRewindTheEndTime() {
        let segments = TokenGrouping.segments(from: [
            TimedToken(text: " long", start: 0, end: 5),
            TimedToken(text: " tail", start: 1, end: 2),   // ends before the previous
        ], speaker: .me)
        XCTAssertEqual(segments[0].end, 5)
    }

    // MARK: - Degenerate input

    func testEmptyTokens() {
        XCTAssertTrue(TokenGrouping.segments(from: [], speaker: .me).isEmpty)
    }

    func testWhitespaceOnlyTokensProduceNoSegment() {
        let segments = TokenGrouping.segments(from: [
            TimedToken(text: " ", start: 0, end: 1),
            TimedToken(text: "\n", start: 1, end: 2),
        ], speaker: .me)
        XCTAssertTrue(segments.isEmpty)
    }

    func testASilentGapBetweenWhitespaceDoesNotEmitEmptySegments() {
        let segments = TokenGrouping.segments(from: [
            TimedToken(text: " ", start: 0, end: 1),
            TimedToken(text: " real", start: 9, end: 10),
        ], speaker: .me)
        XCTAssertEqual(segments.map(\.text), ["real"])
    }

    // MARK: - Realistic end-to-end shape

    func testAFullExchangeGroupsAndMergesIntoDialogue() {
        let me = TokenGrouping.segments(from: realTokens, speaker: .me)
        let them = TokenGrouping.segments(from: [
            TimedToken(text: " Yes", start: 2.5, end: 2.8),
            TimedToken(text: " I", start: 2.8, end: 2.9),
            TimedToken(text: " can", start: 2.9, end: 3.1),
            TimedToken(text: " hear", start: 3.1, end: 3.4),
            TimedToken(text: " you", start: 3.4, end: 3.6),
        ], speaker: .them)
        let merged = DialogueMerge.merge(me: me, them: them)
        XCTAssertEqual(DialogueMerge.render(merged), """
        **Me:** Hey, can you hear me okay?

        **Them:** Yes I can hear you
        """)
    }
}
