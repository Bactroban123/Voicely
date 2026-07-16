import XCTest
@testable import VoicelyCore

final class SpeechConfidenceTests: XCTestCase {
    private func confident(_ noSpeech: Float = 0.02, _ logProb: Float = -0.25) -> SegmentConfidence {
        SegmentConfidence(noSpeechProbability: noSpeech, averageLogProbability: logProb)
    }

    /// The case from the first real meeting: a silent system track produced
    /// three "Thank you." lines that nobody said. Left in, the summarizer would
    /// treat invented filler as something a participant actually said.
    func testTheThankYouHallucinationIsRejected() {
        XCTAssertFalse(SpeechConfidence.isSpeech(text: "Thank you.", confidence: confident(0.92, -0.9)))
        XCTAssertFalse(SpeechConfidence.isSpeech(text: " Thanks for watching! ", confidence: confident(0.8, -0.7)))
        XCTAssertFalse(SpeechConfidence.isSpeech(text: "Please subscribe", confidence: confident(0.7, -0.6)))
    }

    func testStockPhrasesAreRejectedEvenWhenTheEngineIsConfident() {
        // Whisper sometimes reports high confidence in its own filler, so the
        // numbers alone don't catch every case.
        XCTAssertFalse(SpeechConfidence.isSpeech(text: "Thank you.", confidence: confident(0.01, -0.1)))
        XCTAssertFalse(SpeechConfidence.isSpeech(text: "you", confidence: confident(0.01, -0.1)))
    }

    func testHighNoSpeechProbabilityIsRejected() {
        XCTAssertFalse(SpeechConfidence.isSpeech(text: "some words here", confidence: confident(0.85, -0.2)))
    }

    func testVeryLowConfidenceTokensAreRejected() {
        XCTAssertFalse(SpeechConfidence.isSpeech(text: "mumbled guesswork", confidence: confident(0.1, -2.5)))
    }

    // MARK: - What must NOT be thrown away

    func testRealSpeechIsKept() {
        XCTAssertTrue(SpeechConfidence.isSpeech(text: "Can you hear me okay?", confidence: confident()))
    }

    func testARealThankYouInASentenceSurvives() {
        // The giveaway is a standalone stock phrase, not the words themselves —
        // people do thank each other on calls.
        XCTAssertTrue(SpeechConfidence.isSpeech(
            text: "Thank you for sending that over, I'll review it tonight.", confidence: confident()))
        XCTAssertTrue(SpeechConfidence.isSpeech(
            text: "Okay thank you, so about the launch date", confidence: confident()))
    }

    func testHebrewSpeechIsKept() {
        // The filter must not become an English-only gate on a bilingual app.
        XCTAssertTrue(SpeechConfidence.isSpeech(text: "שלום, אני שמח לדבר איתך", confidence: confident()))
        XCTAssertTrue(SpeechConfidence.isSpeech(text: "תודה רבה", confidence: confident()))
    }

    func testSegmentsWithoutConfidenceDataAreKept() {
        // Parakeet reports no such signals — absence of evidence must not
        // silently delete a whole engine's output.
        XCTAssertTrue(SpeechConfidence.isSpeech(text: "a normal sentence", confidence: nil))
        XCTAssertFalse(SpeechConfidence.isSpeech(text: "Thank you.", confidence: nil), "the phrase list still applies")
    }

    func testEmptyAndWhitespaceRejected() {
        XCTAssertFalse(SpeechConfidence.isSpeech(text: "", confidence: confident()))
        XCTAssertFalse(SpeechConfidence.isSpeech(text: "   \n", confidence: confident()))
    }

    func testBoundaries() {
        // Exactly at the ceiling/floor is still speech; past it isn't.
        XCTAssertTrue(SpeechConfidence.isSpeech(text: "words",
                                                confidence: confident(SpeechConfidence.noSpeechCeiling, -0.1)))
        XCTAssertFalse(SpeechConfidence.isSpeech(text: "words",
                                                 confidence: confident(SpeechConfidence.noSpeechCeiling + 0.01, -0.1)))
        XCTAssertTrue(SpeechConfidence.isSpeech(text: "words",
                                                confidence: confident(0.1, SpeechConfidence.logProbFloor)))
        XCTAssertFalse(SpeechConfidence.isSpeech(text: "words",
                                                 confidence: confident(0.1, SpeechConfidence.logProbFloor - 0.01)))
    }
}
