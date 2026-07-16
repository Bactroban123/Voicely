import XCTest
@testable import VoicelyCore

final class MeetingRecoveryTests: XCTestCase {
    private func meeting(_ status: Meeting.Status,
                         chunks: Bool = true,
                         audioDeleted: Bool = false) -> Meeting {
        Meeting(title: "Call",
                startedAt: Date(),
                status: status,
                micChunks: chunks ? ["mic-0000.caf"] : [],
                systemChunks: chunks ? ["system-0000.caf"] : [],
                micOffsets: chunks ? [RecordedChunk(startOffset: 0, duration: 300)] : [],
                systemOffsets: chunks ? [RecordedChunk(startOffset: 0, duration: 300)] : [],
                audioDeleted: audioDeleted)
    }

    // MARK: - The case this exists for

    func testAMeetingInterruptedMidCallOffersItsAudioBack() {
        // The app was killed during a call. Chunks only reach the header once
        // they're closed, so whatever's listed is valid audio — it must not be
        // silently binned.
        XCTAssertEqual(MeetingRecovery.action(for: meeting(.recording)), .offerInterrupted)
    }

    func testAnInterruptedMeetingThatNeverGotAChunkIsNotOfferedAsRecoverable() {
        // The header is written before recording starts (so a crash is
        // findable), which means an immediate failure leaves an empty husk.
        // Offering to "recover" nothing would be a lie.
        XCTAssertEqual(MeetingRecovery.action(for: meeting(.recording, chunks: false)), .offerCleanup)
    }

    /// THE BUG THIS FILE MISSED, and it cost a real recording.
    ///
    /// These rules are only correct on a RECONCILED meeting — one whose
    /// manifest has been rebuilt from the audio folder. The recorder writes
    /// chunk files continuously but only records their names at a clean stop,
    /// so a crashed meeting has real audio on disk and an EMPTY manifest.
    /// `.offerCleanup` then meant "delete", and the crash recovery destroyed
    /// exactly what it exists to save.
    ///
    /// The original test passed because its fixture planted a manifest a crash
    /// never produces — testing the assumption instead of the reality.
    func testAnEmptyManifestIsIndistinguishableFromAnEmptyHuskHere() {
        // Same input, two very different meetings on disk. This type cannot
        // tell them apart — which is precisely why MeetingStore must reconcile
        // from the filesystem BEFORE asking, and why pruning re-checks the
        // filesystem itself rather than trusting any manifest.
        let crashedWithAudioOnDisk = meeting(.recording, chunks: false)
        XCTAssertEqual(MeetingRecovery.action(for: crashedWithAudioOnDisk), .offerCleanup)

        // Reconciled (manifest rebuilt from the audio folder), the same meeting
        // is correctly recoverable.
        let reconciled = meeting(.recording, chunks: true)
        XCTAssertEqual(MeetingRecovery.action(for: reconciled), .offerInterrupted)
        XCTAssertFalse(MeetingRecovery.isDisposable(reconciled))
    }

    func testDiedMidTranscriptionJustDoesItAgain() {
        // Transcription is idempotent and costs minutes; the audio is still
        // there, so there's nothing to ask about.
        XCTAssertEqual(MeetingRecovery.action(for: meeting(.transcribing)), .resumeTranscription)
    }

    func testRecordedButNeverTranscribedResumes() {
        XCTAssertEqual(MeetingRecovery.action(for: meeting(.recorded)), .resumeTranscription)
    }

    func testASavedTranscriptWithoutNotesOffersARetryWithoutNeedingAudio() {
        // Audio is deleted once the transcript exists — retrying the summary
        // must not require it.
        XCTAssertEqual(MeetingRecovery.action(for: meeting(.transcribed, chunks: false, audioDeleted: true)),
                       .offerRetry)
        XCTAssertEqual(MeetingRecovery.action(for: meeting(.summarizing, chunks: false, audioDeleted: true)),
                       .offerRetry)
    }

    func testAFailedMeetingAlwaysOffersARetry() {
        XCTAssertEqual(MeetingRecovery.action(for: meeting(.failed)), .offerRetry)
        XCTAssertEqual(MeetingRecovery.action(for: meeting(.failed, chunks: false, audioDeleted: true)), .offerRetry)
    }

    func testAFinishedMeetingIsLeftAlone() {
        XCTAssertEqual(MeetingRecovery.action(for: meeting(.complete)), .none)
    }

    func testDeletedAudioCannotBeTranscribedAgain() {
        // canTranscribe must reflect the audio actually being gone, or recovery
        // would offer to transcribe files that no longer exist.
        XCTAssertFalse(meeting(.recorded, audioDeleted: true).canTranscribe)
        XCTAssertEqual(MeetingRecovery.action(for: meeting(.recorded, audioDeleted: true)), .offerCleanup)
    }

    // MARK: - What the user is actually shown

    func testOnlyActionableMeetingsAreSurfacedAtLaunch() {
        // Nagging about husks on every launch trains people to dismiss the
        // dialog that actually matters.
        let all = [meeting(.complete), meeting(.recording), meeting(.recording, chunks: false),
                   meeting(.recorded), meeting(.failed)]
        let shown = MeetingRecovery.needingAttention(all)
        XCTAssertEqual(shown.count, 3)
        XCTAssertFalse(shown.contains { $0.status == .complete })
        XCTAssertFalse(shown.contains { $0.micChunks.isEmpty })
    }

    func testNothingToRecover() {
        XCTAssertTrue(MeetingRecovery.needingAttention([meeting(.complete)]).isEmpty)
        XCTAssertTrue(MeetingRecovery.needingAttention([]).isEmpty)
    }

    func testOnlyEmptyHusksAreDisposable() {
        XCTAssertTrue(MeetingRecovery.isDisposable(meeting(.recording, chunks: false)))
        XCTAssertFalse(MeetingRecovery.isDisposable(meeting(.recording)), "there's real audio here")
        XCTAssertFalse(MeetingRecovery.isDisposable(meeting(.complete)))
    }

    func testWasInterruptedOnlyMeansTheRecordingNeverFinished() {
        XCTAssertTrue(meeting(.recording).wasInterrupted)
        XCTAssertFalse(meeting(.recorded).wasInterrupted)
        XCTAssertFalse(meeting(.complete).wasInterrupted)
    }
}

final class DiskGuardTests: XCTestCase {
    private let gb: Int64 = 1_024 * 1_024 * 1_024

    func testPlentyOfRoom() {
        XCTAssertEqual(DiskGuard.check(freeBytes: 50 * gb), .ok)
    }

    func testRefusesBelowTheFloor() {
        // Running the disk dry mid-call would fail the recording AND whatever
        // else the user is doing. Refuse while it's still just a menu click.
        guard case .refuse = DiskGuard.check(freeBytes: 500 * 1_024 * 1_024) else {
            return XCTFail("half a gig is not enough to start an hour-long recording")
        }
        guard case .refuse = DiskGuard.check(freeBytes: 0) else { return XCTFail("empty disk must refuse") }
    }

    func testWarnsWhenThereIsRoomButNotMuch() {
        // 1GB floor + ~1 hour of headroom.
        guard case .tight(let hours) = DiskGuard.check(freeBytes: gb + DiskGuard.bytesPerHour) else {
            return XCTFail("expected a tight verdict")
        }
        XCTAssertEqual(hours, 1, accuracy: 0.1)
    }

    func testTheBoundaryIsNotOffByOne() {
        guard case .tight = DiskGuard.check(freeBytes: DiskGuard.minimumFreeBytes) else {
            return XCTFail("exactly at the floor is allowed, with zero headroom")
        }
        guard case .refuse = DiskGuard.check(freeBytes: DiskGuard.minimumFreeBytes - 1) else {
            return XCTFail("one byte below the floor must refuse")
        }
    }

    func testAnHourOfMeetingIsAboutWhatWeClaim() {
        // 230MB/hour: two 16kHz mono Int16 tracks. If this drifts, the
        // headroom maths and the retention UI both start lying.
        let perHour = Double(DiskGuard.bytesPerHour)
        let computed = 2.0 * 16_000 * 2 * 3_600   // tracks * samples/s * bytes * seconds
        XCTAssertEqual(perHour, computed, accuracy: computed * 0.05)
    }

    func testSizeFormatting() {
        XCTAssertTrue(DiskGuard.format(bytes: 230 * 1_024 * 1_024).contains("MB"))
        XCTAssertTrue(DiskGuard.format(bytes: 5 * 1_024 * 1_024 * 1_024).contains("GB"))
    }
}
