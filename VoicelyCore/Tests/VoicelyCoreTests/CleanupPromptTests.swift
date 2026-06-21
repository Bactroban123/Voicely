import XCTest
@testable import VoicelyCore

final class CleanupPromptTests: XCTestCase {
    func testEmptyVocabularyRendersNone() {
        XCTAssertEqual(CleanupPrompt.renderVocabulary([]), "(none)")
    }

    func testBareTermRendersOneBullet() {
        XCTAssertEqual(CleanupPrompt.renderVocabulary([VocabularyEntry(term: "Collabo")]), "- Collabo")
    }

    func testVariantsRenderAsHeardAsList() {
        let rendered = CleanupPrompt.renderVocabulary([
            VocabularyEntry(term: "Keswadee", variants: ["kes wadi", "case wadi"]),
        ])
        XCTAssertEqual(rendered, "- Keswadee (heard as: kes wadi, case wadi)")
    }

    func testMultipleEntriesNewlineJoined() {
        let rendered = CleanupPrompt.renderVocabulary([
            VocabularyEntry(term: "Collabo"),
            VocabularyEntry(term: "kubectl", variants: ["cube cuddle"]),
        ])
        XCTAssertEqual(rendered, "- Collabo\n- kubectl (heard as: cube cuddle)")
    }

    func testSystemPromptCarriesGuardrailsAndVocabulary() {
        let sys = CleanupPrompt.system(vocabulary: [VocabularyEntry(term: "Collabo")])
        XCTAssertTrue(sys.contains("editor, not an assistant"))
        XCTAssertTrue(sys.contains("Output ONLY the cleaned text"))
        XCTAssertTrue(sys.contains("DO NOT add, invent"))
        XCTAssertTrue(sys.contains("- Collabo"))
    }

    func testSystemPromptWithEmptyVocabularyIsWellFormed() {
        XCTAssertTrue(CleanupPrompt.system(vocabulary: []).contains("(none)"))
    }
}
