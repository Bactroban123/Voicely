import XCTest
@testable import VoicelyCore

final class PipelineTests: XCTestCase {
    func testHappyPathWithCleanup() {
        var p = Pipeline(cleanupEnabled: true)
        XCTAssertEqual(p.handle(.startedRecording), .none)
        XCTAssertEqual(p.state, .recording)
        XCTAssertEqual(p.handle(.stoppedRecording), .beginTranscription)
        XCTAssertEqual(p.handle(.transcript("hello")), .beginCleanup("hello"))
        XCTAssertEqual(p.state, .refining)
        XCTAssertEqual(p.handle(.cleaned("Hello.")), .insert("Hello."))
        XCTAssertEqual(p.handle(.inserted), .none)
        XCTAssertEqual(p.state, .idle)
    }

    func testCleanupOffInsertsRaw() {
        var p = Pipeline(cleanupEnabled: false)
        _ = p.handle(.startedRecording); _ = p.handle(.stoppedRecording)
        XCTAssertEqual(p.handle(.transcript("raw text")), .insert("raw text"))
        XCTAssertEqual(p.state, .inserting)
    }

    func testCleanupFailureFallsBackToRaw() {
        var p = Pipeline(cleanupEnabled: true)
        _ = p.handle(.startedRecording); _ = p.handle(.stoppedRecording)
        _ = p.handle(.transcript("kept raw"))
        XCTAssertEqual(p.handle(.cleanupFailed), .insert("kept raw"))
    }

    func testCancelReturnsToIdle() {
        var p = Pipeline(cleanupEnabled: true)
        _ = p.handle(.startedRecording)
        XCTAssertEqual(p.handle(.cancelled), .none)
        XCTAssertEqual(p.state, .idle)
    }

    func testTranscriptionFailureGoesIdle() {
        var p = Pipeline(cleanupEnabled: true)
        _ = p.handle(.startedRecording); _ = p.handle(.stoppedRecording)
        XCTAssertEqual(p.handle(.transcriptionFailed), .none)
        XCTAssertEqual(p.state, .idle)
    }
}
