import XCTest
@testable import VoicelyCore

final class SnippetExpanderTests: XCTestCase {
    private let email = [Snippet(trigger: "my email", expansion: "gal@example.com")]

    func testWholeUtteranceExpands() {
        XCTAssertEqual(SnippetExpander.expand("my email", snippets: email), "gal@example.com")
    }
    func testInlineExpansion() {
        XCTAssertEqual(SnippetExpander.expand("send it to my email please", snippets: email),
                       "send it to gal@example.com please")
    }
    func testCaseInsensitive() {
        XCTAssertEqual(SnippetExpander.expand("My Email", snippets: email), "gal@example.com")
    }
    func testNoMatchUnchanged() {
        XCTAssertEqual(SnippetExpander.expand("nothing here", snippets: email), "nothing here")
    }
    func testLongerTriggerWins() {
        let s = [Snippet(trigger: "email", expansion: "E"), Snippet(trigger: "my email", expansion: "FULL")]
        XCTAssertEqual(SnippetExpander.expand("my email", snippets: s), "FULL")
    }
    func testSpecialCharsInExpansionAreLiteral() {
        let s = [Snippet(trigger: "price", expansion: "$5 (50% off)")]
        XCTAssertEqual(SnippetExpander.expand("the price", snippets: s), "the $5 (50% off)")
    }
}

final class CleanupModesTests: XCTestCase {
    private let vocab = [VocabularyEntry(term: "Vercel")]

    func testThreePresetsWithDefault() {
        XCTAssertEqual(CleanupModes.all.count, 3)
        XCTAssertNotNil(CleanupModes.mode(id: CleanupModes.defaultID))
    }
    func testCleanUsesConservativePrompt() {
        XCTAssertTrue(CleanupModes.system(modeID: "clean", vocabulary: vocab).contains("editor, not an assistant"))
    }
    func testPolishTightensAndInjectsVocab() {
        let p = CleanupModes.system(modeID: "polish", vocabulary: vocab)
        XCTAssertTrue(p.contains("concise") || p.contains("Tighten"))
        XCTAssertTrue(p.contains("- Vercel"))
    }
    func testPromptReshapesAndInjectsVocab() {
        let p = CleanupModes.system(modeID: "prompt", vocabulary: vocab)
        XCTAssertTrue(p.contains("prompt-engineering"))
        XCTAssertTrue(p.contains("- Vercel"))
    }
    func testUnknownModeFallsBackToClean() {
        XCTAssertTrue(CleanupModes.system(modeID: "nope", vocabulary: vocab).contains("editor, not an assistant"))
    }
}
