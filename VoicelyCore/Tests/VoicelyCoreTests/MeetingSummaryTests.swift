import XCTest
@testable import VoicelyCore

final class MeetingSummaryParsingTests: XCTestCase {
    private let good = """
    {"summary":"Discussed the launch.","key_points":["Ship Friday"],"decisions":["Ship on Friday"],
     "action_items":[{"title":"Send the deck","owner":"Sarah","due":"Friday"},
                     {"title":"Follow up with legal","owner":null,"due":null}],
     "followups":["Confirm pricing"]}
    """

    func testCleanJSONParses() {
        guard case .parsed(let summary) = MeetingSummaryParsing.parse(good) else {
            return XCTFail("expected a clean parse")
        }
        XCTAssertEqual(summary.summary, "Discussed the launch.")
        XCTAssertEqual(summary.decisions, ["Ship on Friday"])
        XCTAssertEqual(summary.actionItems.count, 2)
        XCTAssertEqual(summary.actionItems[0].owner, "Sarah")
        XCTAssertNil(summary.actionItems[1].owner, "null owner must stay null, not become a guess")
        XCTAssertFalse(summary.parseDegraded)
    }

    func testFencedJSONParses() {
        // Providers add these despite JSON mode.
        let fenced = "```json\n\(good)\n```"
        guard case .parsed = MeetingSummaryParsing.parse(fenced) else {
            return XCTFail("fences must be stripped")
        }
    }

    func testChattyPreambleIsIgnored() {
        guard case .parsed = MeetingSummaryParsing.parse("Sure! Here are your notes:\n\n\(good)") else {
            return XCTFail("a preamble must not defeat the parse")
        }
    }

    func testMissingFieldsDefaultRatherThanFailing() {
        guard case .parsed(let summary) = MeetingSummaryParsing.parse(#"{"summary":"Short call."}"#) else {
            return XCTFail("a partial object is still usable")
        }
        XCTAssertEqual(summary.summary, "Short call.")
        XCTAssertTrue(summary.decisions.isEmpty)
        XCTAssertTrue(summary.actionItems.isEmpty)
    }

    func testAMeetingThatDecidedNothingIsValid() {
        let json = #"{"summary":"Casual catch-up.","key_points":[],"decisions":[],"action_items":[],"followups":[]}"#
        guard case .parsed(let summary) = MeetingSummaryParsing.parse(json) else {
            return XCTFail("empty lists are a correct answer, not a failure")
        }
        XCTAssertTrue(summary.decisions.isEmpty)
        XCTAssertFalse(summary.parseDegraded)
    }

    // MARK: - Failure handling

    func testGarbageIsRetryableOnTheFirstAttempt() {
        XCTAssertEqual(MeetingSummaryParsing.parse("I'm sorry, I can't do that."), .retryable)
    }

    func testGarbageDegradesRatherThanVanishingOnTheFinalAttempt() {
        // The prose is kept: a wall of text the user can read beats a blank page
        // pretending the meeting had no content.
        guard case .degraded(let summary) =
                MeetingSummaryParsing.parse("The team talked about shipping.", isFinalAttempt: true) else {
            return XCTFail("expected degradation")
        }
        XCTAssertTrue(summary.parseDegraded)
        XCTAssertEqual(summary.summary, "The team talked about shipping.")
    }

    func testAnEmptyObjectIsNotAcceptedAsSuccess() {
        // Would otherwise render as a completed summary of nothing.
        XCTAssertEqual(MeetingSummaryParsing.parse(#"{"summary":"","key_points":[]}"#), .retryable)
    }

    func testTruncatedJSONIsNotAccepted() {
        XCTAssertEqual(MeetingSummaryParsing.parse(#"{"summary":"It cut off mid-"#), .retryable)
    }

    // MARK: - Object extraction

    func testBracesInsideStringsDoNotTruncateTheObject() {
        // A transcript quoting a brace would otherwise cut the object short.
        let json = #"{"summary":"He said \"use {braces}\" then left.","decisions":[]}"#
        guard case .parsed(let summary) = MeetingSummaryParsing.parse(json) else {
            return XCTFail("brace-matching must ignore string contents")
        }
        XCTAssertTrue(summary.summary.contains("{braces}"))
    }

    func testNestedObjectsAreMatchedByDepth() {
        guard case .parsed(let summary) = MeetingSummaryParsing.parse(good) else {
            return XCTFail("nested action_items objects must not end the match early")
        }
        XCTAssertEqual(summary.actionItems.count, 2)
    }

    func testTrailingCommentaryAfterTheObjectIsIgnored() {
        guard case .parsed = MeetingSummaryParsing.parse("\(good)\n\nHope that helps!") else {
            return XCTFail("trailing chat must not defeat the parse")
        }
    }

    func testHebrewNotesSurviveParsing() {
        let json = #"{"summary":"דיברנו על ההשקה","key_points":["לשלוח ביום שישי"],"decisions":[],"action_items":[],"followups":[]}"#
        guard case .parsed(let summary) = MeetingSummaryParsing.parse(json) else {
            return XCTFail("Hebrew notes must parse")
        }
        XCTAssertEqual(summary.summary, "דיברנו על ההשקה")
    }
}

final class MeetingSummaryRequestTests: XCTestCase {
    private func json(_ request: MeetingSummaryRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: request.jsonData()) as? [String: Any])
    }

    func testBodyCarriesPromptAndTranscript() throws {
        let obj = try json(MeetingSummaryRequest(modelID: "m", systemPrompt: "SYS", content: "TRANSCRIPT"))
        XCTAssertEqual(obj["model"] as? String, "m")
        let messages = try XCTUnwrap(obj["messages"] as? [[String: Any]])
        XCTAssertEqual(messages[0]["content"] as? String, "SYS")
        XCTAssertEqual(messages[1]["content"] as? String, "TRANSCRIPT")
    }

    func testPrivacyPostureMatchesDictation() throws {
        let obj = try json(MeetingSummaryRequest(modelID: "m", systemPrompt: "s", content: "t"))
        let provider = try XCTUnwrap(obj["provider"] as? [String: Any])
        XCTAssertEqual(provider["data_collection"] as? String, "deny")
        XCTAssertEqual(provider["zdr"] as? Bool, true)
        XCTAssertEqual(provider["sort"] as? String, "latency")
    }

    func testZeroRetentionCanBeRelaxed() throws {
        let obj = try json(MeetingSummaryRequest(modelID: "m", systemPrompt: "s", content: "t", zeroRetention: false))
        let provider = try XCTUnwrap(obj["provider"] as? [String: Any])
        XCTAssertEqual(provider["zdr"] as? Bool, false)
    }

    func testJSONModeIsRequestedAndCanBeDisabledForTheMapStep() throws {
        let structured = try json(MeetingSummaryRequest(modelID: "m", systemPrompt: "s", content: "t"))
        let format = try XCTUnwrap(structured["response_format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_object")

        // The map step returns bullets, not JSON.
        let prose = try json(MeetingSummaryRequest(modelID: "m", systemPrompt: "s", content: "t", requireJSON: false))
        XCTAssertNil(prose["response_format"])
    }

    func testNotStreamedAndReasoningOff() throws {
        let obj = try json(MeetingSummaryRequest(modelID: "m", systemPrompt: "s", content: "t"))
        XCTAssertEqual(obj["stream"] as? Bool, false)
        let reasoning = try XCTUnwrap(obj["reasoning"] as? [String: Any])
        XCTAssertEqual(reasoning["enabled"] as? Bool, false)
    }

    func testBudgetIsSizedForNotesNotForTheTranscript() throws {
        // A huge transcript must not inflate the OUTPUT budget: a bigger
        // max_tokens shrinks OpenRouter's provider pool.
        let obj = try json(MeetingSummaryRequest(modelID: "m", systemPrompt: "s",
                                                 content: String(repeating: "word ", count: 50_000)))
        XCTAssertEqual(obj["max_tokens"] as? Int, 4_096)
    }

    func testDictationsBudgetIsUntouched() throws {
        // Meetings must not change dictation's routing or cost.
        let cleanup = try XCTUnwrap(JSONSerialization.jsonObject(
            with: CleanupRequest(modelID: "m", systemPrompt: "s", transcript: "hi").jsonData()) as? [String: Any])
        XCTAssertEqual(cleanup["max_tokens"] as? Int, 400)
    }
}

final class MeetingSummaryPlanTests: XCTestCase {
    func testATypicalMeetingGoesInOneCall() {
        // ~2 hours of speech (~18k words) still fits every catalog model.
        let transcript = String(repeating: "word ", count: 8_000)   // 40k chars
        guard case .single = MeetingSummaryPlan.plan(for: transcript) else {
            return XCTFail("map-reduce loses detail at the seams; it should be the exception")
        }
    }

    func testAVeryLongMeetingIsSliced() {
        let transcript = String(repeating: "word ", count: 20_000)  // 100k chars
        guard case .mapReduce(let slices) = MeetingSummaryPlan.plan(for: transcript) else {
            return XCTFail("expected slicing")
        }
        XCTAssertGreaterThan(slices.count, 1)
        XCTAssertTrue(slices.allSatisfy { $0.count <= MeetingSummaryPlan.sliceLength + 100 })
    }

    func testSlicesCoverTheWholeTranscript() {
        // ~110k chars: comfortably past the single-shot limit.
        let transcript = (0..<10_000).map { "line \($0)" }.joined(separator: "\n\n")
        XCTAssertGreaterThan(transcript.count, MeetingSummaryPlan.singleShotLimit)
        guard case .mapReduce(let slices) = MeetingSummaryPlan.plan(for: transcript) else {
            return XCTFail("expected slicing")
        }
        // Nothing may be dropped: the first and last words must survive.
        XCTAssertTrue(slices.first?.contains("line 0") ?? false)
        XCTAssertTrue(slices.last?.contains("line 9999") ?? false)
        // With overlap, the slices total more than the original, never less.
        XCTAssertGreaterThanOrEqual(slices.reduce(0) { $0 + $1.count }, transcript.count)
    }

    func testSlicingTerminatesOnAwkwardInput() {
        // A single unbroken blob with no paragraph breaks must not loop.
        let transcript = String(repeating: "a", count: 80_000)
        guard case .mapReduce(let slices) = MeetingSummaryPlan.plan(for: transcript) else {
            return XCTFail("expected slicing")
        }
        XCTAssertGreaterThan(slices.count, 1)
        XCTAssertLessThan(slices.count, 100)
    }

    func testEmptyTranscript() {
        XCTAssertEqual(MeetingSummaryPlan.plan(for: ""), .single(""))
    }
}

final class MeetingSummaryPromptTests: XCTestCase {
    func testTheSummarizerDoesNotInheritTheCleanupPromptsBanOnSummarizing() {
        // CleanupPrompt says "DO NOT ... summarize ..." — the opposite contract.
        let system = MeetingSummaryPrompt.system()
        XCTAssertFalse(system.contains("DO NOT add, invent, summarize"))
        XCTAssertTrue(system.contains("structured notes"))
    }

    func testGroundingRulesAreStatedInEveryStructuredPrompt() {
        for prompt in [MeetingSummaryPrompt.system(), MeetingSummaryPrompt.reduceSystem()] {
            XCTAssertTrue(prompt.contains("Invent nothing") || prompt.contains("Never invent"),
                          "a summary that invents commitments is worse than none")
            XCTAssertTrue(prompt.contains("null"), "owner/due must be null rather than guessed")
            XCTAssertTrue(prompt.contains("action_items"), "the JSON contract must be stated")
        }
    }

    func testPromptsForbidInventingParticipantNames() {
        XCTAssertTrue(MeetingSummaryPrompt.system().contains("Do not invent participant names"))
        XCTAssertTrue(MeetingSummaryPrompt.mapSystem().contains("Don't invent names"))
    }

    func testPromptsPreserveTheTranscriptsLanguage() {
        XCTAssertTrue(MeetingSummaryPrompt.system().contains("Hebrew"))
        XCTAssertTrue(MeetingSummaryPrompt.mapSystem().contains("own language"))
    }

    func testMapStepPreservesSpecificsRatherThanSummarizing() {
        // A summary of a summary loses the names and numbers that make notes useful.
        XCTAssertTrue(MeetingSummaryPrompt.mapSystem().contains("Preserve specifics"))
    }

    func testReduceStepMergesDuplicatesAcrossSlices() {
        XCTAssertTrue(MeetingSummaryPrompt.reduceSystem().contains("Merge duplicates"))
    }
}
