import XCTest
@testable import VoicelyCore

final class AutoLearnVocabularyTests: XCTestCase {
    func testLearnsRecurringProperNounsIgnoresOneOffsAndPronouns() {
        let ts = [
            "I met Keswadee at the studio in Bangkok.",
            "Keswadee runs the Bangkok shop.",
            "We deployed to Vercel today.",
        ]
        let names = AutoLearn.vocabularyTerms(from: ts, minDistinct: 2).map { $0.term }
        XCTAssertTrue(names.contains("Keswadee"))       // learns proper noun even when later sentence-initial
        XCTAssertTrue(names.contains("Bangkok"))        // learns recurring place name
        XCTAssertFalse(names.contains("Vercel"))        // ignores a one-off term (minDistinct 2)
        XCTAssertFalse(names.contains("I"))              // skips pronouns / short tokens
    }

    func testLearnsPascalCaseProductNameAndAcronym() {
        let ts = ["The API returned an error.", "Our API is fast.",
                  "OpenRouter is great.", "I love OpenRouter."]
        let names = AutoLearn.vocabularyTerms(from: ts, minDistinct: 2).map { $0.term }
        XCTAssertTrue(names.contains("API"))            // learns acronym (internal caps)
        XCTAssertTrue(names.contains("OpenRouter"))     // learns PascalCase product name
    }

    func testLearnsTwoWordCapitalizedName() {
        let ts = ["I work at Tattoo Genesis downtown.", "Tattoo Genesis is hiring.", "love Tattoo Genesis"]
        let names = AutoLearn.vocabularyTerms(from: ts, minDistinct: 2).map { $0.term }
        XCTAssertTrue(names.contains("Tattoo Genesis")) // learns a two-word capitalized name
    }

    func testBigramAcrossSentenceBoundaryIsNotCounted() {
        let ts = ["I love Tattoo Genesis here.", "We went to Tattoo. Genesis was closed."]
        let names = AutoLearn.vocabularyTerms(from: ts, minDistinct: 2).map { $0.term }
        XCTAssertFalse(names.contains("Tattoo Genesis")) // bigram count respects sentence boundaries
    }

    func testSkipsCapitalizedInterjectionStopword() {
        let ts = ["He said Hello there.", "She said Hello again."]
        let names = AutoLearn.vocabularyTerms(from: ts, minDistinct: 2).map { $0.term }
        XCTAssertFalse(names.contains("Hello")) // skips capitalized interjections (stopword)
    }

    func testExcludesExistingVocabularyAndDismissedTermsCaseInsensitive() {
        let ts = ["I met Keswadee in Bangkok.", "Keswadee called from Bangkok."]
        let withExisting = AutoLearn.vocabularyTerms(
            from: ts, existing: [VocabularyEntry(term: "bangkok")], minDistinct: 2).map { $0.term.lowercased() }
        XCTAssertFalse(withExisting.contains("bangkok")) // excludes terms already in vocabulary
        let withDismissed = AutoLearn.vocabularyTerms(
            from: ts, dismissed: ["keswadee"], minDistinct: 2).map { $0.term.lowercased() }
        XCTAssertFalse(withDismissed.contains("keswadee")) // excludes dismissed terms
    }
}

final class AutoLearnSnippetsTests: XCTestCase {
    func testSuggestsRepeatedPhrasePreferringLongest() {
        let ts = [
            "Please book a consultation with the artist.",
            "Can you please book a consultation today?",
            "please book a consultation",
        ]
        let sug = AutoLearn.snippetSuggestions(from: ts, minDistinct: 2)
        XCTAssertFalse(sug.isEmpty)  // surfaces a recurring phrase
        XCTAssertTrue(sug.contains { $0.phrase.lowercased().contains("book a consultation") })
            // suggestion contains the repeated phrase
        XCTAssertGreaterThanOrEqual(sug[0].count, 2)     // counts the repeats
        XCTAssertFalse(sug[0].suggestedTrigger.isEmpty)  // proposes an editable trigger
    }

    func testNGramsDoNotGlueAcrossSentenceBoundary() {
        let ts = ["The shop was closed. Please call again.", "The shop was closed. Please call again."]
        let sug = AutoLearn.snippetSuggestions(from: ts, minDistinct: 2)
        XCTAssertFalse(sug.contains { $0.phrase.lowercased().contains("closed please") })
            // snippet n-grams respect sentence boundaries
    }

    func testIgnoresNonRepeatedPhrases() {
        let once = AutoLearn.snippetSuggestions(
            from: ["a totally unique sentence that only appears one single time"], minDistinct: 2)
        XCTAssertTrue(once.isEmpty) // ignores phrases that do not repeat
    }

    func testExcludesExistingSnippetExpansionDespitePunctuationAndCasing() {
        let ts = ["call me at the studio", "call me at the studio", "call me at the studio"]
        let withExisting = AutoLearn.snippetSuggestions(
            from: ts, existing: [Snippet(trigger: "studio", expansion: "Call me at the studio.")], minDistinct: 2)
        XCTAssertFalse(withExisting.contains { $0.phrase.lowercased().contains("call me at the studio") })
    }
}
