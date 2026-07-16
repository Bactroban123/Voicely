import XCTest
@testable import VoicelyCore

final class TapDisableTrackerTests: XCTestCase {
    func testIsolatedDisablesRecoverQuietly() {
        var t = TapDisableTracker()
        XCTAssertEqual(t.record(at: 0), .recovered)
        XCTAssertEqual(t.record(at: 10), .recovered)
        XCTAssertEqual(t.recentCount, 2)
    }

    func testThirdDisableInsideTheWindowWarnsOnce() {
        var t = TapDisableTracker()
        XCTAssertEqual(t.record(at: 0), .recovered)
        XCTAssertEqual(t.record(at: 1), .recovered)
        XCTAssertEqual(t.record(at: 2), .recoveredUnreliable)
        // Latched: a burst must not spam the notice on every subsequent disable.
        XCTAssertEqual(t.record(at: 3), .recovered)
        XCTAssertEqual(t.record(at: 4), .recovered)
    }

    func testDisablesOlderThanTheWindowAreForgotten() {
        var t = TapDisableTracker()
        _ = t.record(at: 0)
        _ = t.record(at: 1)
        // 61s later the first two have aged out: this is a lone event.
        XCTAssertEqual(t.record(at: 62), .recovered)
        XCTAssertEqual(t.recentCount, 1)
    }

    func testExactlyAtWindowEdgeIsStillCounted() {
        var t = TapDisableTracker(window: 60, threshold: 3)
        _ = t.record(at: 0)
        _ = t.record(at: 30)
        // now - 60 == 0 is NOT older than the window, so all three count.
        XCTAssertEqual(t.record(at: 60), .recoveredUnreliable)
        XCTAssertEqual(t.recentCount, 3)
    }

    func testAFreshBurstWarnsAgainAfterTheFirstSubsides() {
        var t = TapDisableTracker()
        _ = t.record(at: 0); _ = t.record(at: 1)
        XCTAssertEqual(t.record(at: 2), .recoveredUnreliable)
        // Quiet period ages everything out, then a new burst starts.
        XCTAssertEqual(t.record(at: 200), .recovered)
        XCTAssertEqual(t.record(at: 201), .recovered)
        XCTAssertEqual(t.record(at: 202), .recoveredUnreliable)
    }

    func testResetForgetsEverything() {
        var t = TapDisableTracker()
        _ = t.record(at: 0); _ = t.record(at: 1); _ = t.record(at: 2)
        t.reset()
        XCTAssertEqual(t.recentCount, 0)
        XCTAssertEqual(t.record(at: 3), .recovered) // latch cleared too
    }

    func testCustomThreshold() {
        var t = TapDisableTracker(window: 10, threshold: 2)
        XCTAssertEqual(t.record(at: 0), .recovered)
        XCTAssertEqual(t.record(at: 1), .recoveredUnreliable)
    }
}
