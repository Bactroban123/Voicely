import XCTest
@testable import VoicelyCore

final class WhisperTextTests: XCTestCase {
    /// Verbatim output captured from WhisperKit large-v3-turbo transcribing real
    /// Hebrew speech. Without stripping, this whole string — control tokens and
    /// all — lands in the meeting transcript.
    func testRealHebrewSegmentIsCleaned() {
        let raw = "<|startoftranscript|><|he|><|transcribe|><|0.00|> שלום, אני שמח לדבר איתך היום.<|2.42|><|endoftext|>"
        XCTAssertEqual(WhisperText.strippingSpecialTokens(raw), "שלום, אני שמח לדבר איתך היום.")
    }

    func testHebrewCharactersSurviveStripping() {
        let raw = "<|startoftranscript|><|he|><|transcribe|><|0.00|> שלום<|1.00|><|endoftext|>"
        let cleaned = WhisperText.strippingSpecialTokens(raw)
        let hebrew = cleaned.unicodeScalars.filter { (0x0590...0x05FF).contains($0.value) }
        XCTAssertEqual(hebrew.count, 4, "stripping must not eat the actual script")
        XCTAssertFalse(cleaned.contains("<|"))
        XCTAssertFalse(cleaned.contains("|>"))
    }

    func testEnglishSegment() {
        let raw = "<|startoftranscript|><|en|><|transcribe|><|0.00|> Hey, can you hear me okay?<|3.20|><|endoftext|>"
        XCTAssertEqual(WhisperText.strippingSpecialTokens(raw), "Hey, can you hear me okay?")
    }

    func testTimestampTokensBetweenWordsAreRemoved() {
        let raw = "<|0.00|> first part<|2.00|><|2.00|> second part<|4.00|>"
        XCTAssertEqual(WhisperText.strippingSpecialTokens(raw), "first part second part")
    }

    func testTextWithoutTokensIsUnchangedApartFromTrimming() {
        XCTAssertEqual(WhisperText.strippingSpecialTokens("  plain text  "), "plain text")
        XCTAssertEqual(WhisperText.strippingSpecialTokens("plain text"), "plain text")
    }

    func testCollapsesTheWhitespaceStrippingLeavesBehind() {
        XCTAssertEqual(WhisperText.strippingSpecialTokens("a <|x|> <|y|> b"), "a b")
    }

    func testTokenOnlySegmentBecomesEmpty() {
        // A silent segment is all control tokens; it must not become a blank
        // dialogue line.
        XCTAssertEqual(WhisperText.strippingSpecialTokens("<|startoftranscript|><|nospeech|><|endoftext|>"), "")
        XCTAssertEqual(WhisperText.strippingSpecialTokens(""), "")
    }

    func testAngleBracketsInRealSpeechAreNotEaten() {
        // "<" and ">" only vanish as part of a <|…|> token.
        XCTAssertEqual(WhisperText.strippingSpecialTokens("use a < b and c > d"), "use a < b and c > d")
        XCTAssertEqual(WhisperText.strippingSpecialTokens("<|en|> compare a < b"), "compare a < b")
    }
}
