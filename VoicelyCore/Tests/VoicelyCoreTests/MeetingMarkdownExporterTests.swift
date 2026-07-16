import XCTest
@testable import VoicelyCore

final class MeetingMarkdownExporterTests: XCTestCase {
    private let started = Date(timeIntervalSince1970: 1_784_000_000)   // fixed, so output is pinnable

    private func meeting(title: String = "Weekly sync",
                         systemAudio: Bool = true,
                         duration: TimeInterval = 1_800) -> Meeting {
        Meeting(title: title,
                startedAt: started,
                endedAt: started.addingTimeInterval(duration),
                status: .complete,
                capturedSystemAudio: systemAudio)
    }

    private let summary = MeetingSummary(
        summary: "Talked through the launch and agreed a date.",
        keyPoints: ["Beta feedback was positive"],
        decisions: ["Ship on Friday"],
        actionItems: [
            .init(title: "Send the updated deck", owner: "Sarah", due: "Friday"),
            .init(title: "Follow up with legal"),
        ],
        followups: ["Confirm pricing"])

    private let transcript = [
        TranscriptSegment(speaker: .me, text: "Are we ready to ship?", start: 5, end: 7),
        TranscriptSegment(speaker: .them, text: "Yes, Friday works.", start: 8, end: 10),
    ]

    /// The whole file, pinned. An export that silently drops a section or
    /// mangles the frontmatter isn't noticed until someone needs the file.
    func testGoldenExport() {
        let output = MeetingMarkdownExporter.export(meeting: meeting(), summary: summary, transcript: transcript)
        XCTAssertTrue(output.hasPrefix("---\ntitle: \"Weekly sync\"\n"), "frontmatter must open the file")
        XCTAssertTrue(output.contains("duration_minutes: 30"))
        XCTAssertTrue(output.contains("tags: [meeting, voicely]"))
        XCTAssertTrue(output.contains("# Weekly sync"))
        XCTAssertTrue(output.contains("## Summary\n\nTalked through the launch and agreed a date."))
        XCTAssertTrue(output.contains("## Key points\n\n- Beta feedback was positive"))
        XCTAssertTrue(output.contains("## Decisions\n\n- Ship on Friday"))
        XCTAssertTrue(output.contains("## Follow-ups\n\n- Confirm pricing"))
        XCTAssertTrue(output.contains("## Transcript"))
        XCTAssertTrue(output.contains("**Me** (0:05): Are we ready to ship?"))
        XCTAssertTrue(output.contains("**Them** (0:08): Yes, Friday works."))
    }

    func testActionItemsRenderAsCheckboxesWithDetailsOnlyWhenKnown() {
        let output = MeetingMarkdownExporter.export(meeting: meeting(), summary: summary, transcript: [])
        XCTAssertTrue(output.contains("- [ ] Send the updated deck (Owner: Sarah, Due: Friday)"))
        // No owner/due in the transcript means no parenthetical invented for it.
        XCTAssertTrue(output.contains("- [ ] Follow up with legal\n"))
        XCTAssertFalse(output.contains("Follow up with legal ("))
    }

    func testMicOnlyMeetingExplainsItselfInTheFile() {
        // A one-sided transcript with no note reads like a broken transcription.
        let output = MeetingMarkdownExporter.export(meeting: meeting(systemAudio: false),
                                                    summary: summary, transcript: transcript)
        XCTAssertTrue(output.contains("Only the microphone was captured"))
    }

    func testDegradedNotesSaySo() {
        var degraded = summary
        degraded.parseDegraded = true
        let output = MeetingMarkdownExporter.export(meeting: meeting(), summary: degraded, transcript: [])
        XCTAssertTrue(output.contains("couldn't be structured"))
    }

    func testEmptySectionsAreOmittedNotLeftAsEmptyHeadings() {
        let sparse = MeetingSummary(summary: "Quick catch-up, nothing decided.")
        let output = MeetingMarkdownExporter.export(meeting: meeting(), summary: sparse, transcript: [])
        XCTAssertFalse(output.contains("## Decisions"))
        XCTAssertFalse(output.contains("## Action items"))
        XCTAssertFalse(output.contains("## Follow-ups"))
        XCTAssertTrue(output.contains("## Summary"))
    }

    func testATranscriptOnlyMeetingStillExports() {
        // Summarization failed; the transcript is the meeting and must survive.
        let output = MeetingMarkdownExporter.export(meeting: meeting(), summary: nil, transcript: transcript)
        XCTAssertTrue(output.contains("## Transcript"))
        XCTAssertTrue(output.contains("Are we ready to ship?"))
        XCTAssertFalse(output.contains("## Summary"))
    }

    func testQuotesInTheTitleCannotBreakTheFrontmatter() {
        // An unescaped quote silently kills YAML parsing, and the note loses
        // every property.
        let output = MeetingMarkdownExporter.export(meeting: meeting(title: #"The "big" launch"#),
                                                    summary: nil, transcript: [])
        XCTAssertTrue(output.contains(#"title: "The \"big\" launch""#))
    }

    func testHebrewSurvivesTheExport() {
        let hebrew = [TranscriptSegment(speaker: .them, text: "שלום, אני שמח לדבר איתך", start: 0, end: 2)]
        let output = MeetingMarkdownExporter.export(meeting: meeting(), summary: nil, transcript: hebrew)
        XCTAssertTrue(output.contains("שלום, אני שמח לדבר איתך"))
    }

    // MARK: - Filenames

    /// The date is deliberately LOCAL (people look for "the meeting I had on
    /// Tuesday"), so the expectation is computed the same way rather than
    /// hardcoded — otherwise this test only passes in one timezone.
    func testFilenameSortsChronologically() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let expected = "\(formatter.string(from: started)) Weekly sync.md"
        XCTAssertEqual(MeetingMarkdownExporter.filename(for: meeting()), expected)
        XCTAssertTrue(expected.hasPrefix("2026-07-1"), "sanity: the fixture is mid-July 2026")
    }

    func testFilenameStripsCharactersThatWouldBreakAPath() {
        let name = MeetingMarkdownExporter.filename(for: meeting(title: "Q3/Q4: plan?"))
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(":"))
        XCTAssertFalse(name.contains("?"))
        XCTAssertTrue(name.hasSuffix(".md"))
    }

    func testAnUntitledMeetingStillGetsAUsableFilename() {
        // A title of only illegal characters must fall back to "Meeting" —
        // stripping them naively leaves "---".
        for title in ["///", "", "   ", ":?*"] {
            let name = MeetingMarkdownExporter.filename(for: meeting(title: title))
            XCTAssertTrue(name.hasSuffix(" Meeting.md"), "got \(name) for title \(title.debugDescription)")
        }
    }
}
