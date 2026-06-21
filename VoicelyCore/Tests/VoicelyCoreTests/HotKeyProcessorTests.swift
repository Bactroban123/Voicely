import XCTest
@testable import VoicelyCore

/// The heart of Voicely's activation model: one key, three behaviors.
/// Quick tap = toggle on (keep recording); tap again = stop. Hold = push-to-talk
/// (stop on release). Esc = cancel. Autorepeat + unrelated keys are ignored.
final class HotKeyProcessorTests: XCTestCase {
    let hk: UInt16 = 61   // Right Option
    let esc: UInt16 = 53

    private func makeProcessor() -> HotKeyProcessor {
        HotKeyProcessor(config: HotKeyConfig(hotKeyCode: hk, cancelKeyCode: esc, tapThreshold: 0.25))
    }
    private func down(_ t: TimeInterval, code: UInt16? = nil, repeat r: Bool = false) -> KeyEvent {
        KeyEvent(keyCode: code ?? hk, phase: .down, timestamp: t, isRepeat: r)
    }
    private func up(_ t: TimeInterval, code: UInt16? = nil) -> KeyEvent {
        KeyEvent(keyCode: code ?? hk, phase: .up, timestamp: t)
    }

    func testHoldStartsOnDownAndStopsOnRelease() {
        var p = makeProcessor()
        XCTAssertEqual(p.process(down(0)), .startRecording)
        XCTAssertEqual(p.process(up(0.5)), .stopRecording)
        XCTAssertEqual(p.mode, .idle)
    }

    func testQuickTapTogglesRecordingOn() {
        var p = makeProcessor()
        XCTAssertEqual(p.process(down(0)), .startRecording)
        XCTAssertNil(p.process(up(0.1)))
        XCTAssertEqual(p.mode, .lockedRecording)
    }

    func testSecondTapStopsLockedRecording() {
        var p = makeProcessor()
        _ = p.process(down(0))
        _ = p.process(up(0.1))
        XCTAssertEqual(p.process(down(1.0)), .stopRecording)
        XCTAssertEqual(p.mode, .idle)
        XCTAssertNil(p.process(up(1.05)))
    }

    func testEscCancelsWhileHolding() {
        var p = makeProcessor()
        _ = p.process(down(0))
        XCTAssertEqual(p.process(down(0.1, code: esc)), .cancel)
        XCTAssertEqual(p.mode, .idle)
    }

    func testEscCancelsWhileLocked() {
        var p = makeProcessor()
        _ = p.process(down(0))
        _ = p.process(up(0.1))
        XCTAssertEqual(p.process(down(0.5, code: esc)), .cancel)
        XCTAssertEqual(p.mode, .idle)
    }

    func testEscWhileIdleDoesNothing() {
        var p = makeProcessor()
        XCTAssertNil(p.process(down(0, code: esc)))
        XCTAssertEqual(p.mode, .idle)
    }

    func testAutorepeatIgnoredWhileHolding() {
        var p = makeProcessor()
        XCTAssertEqual(p.process(down(0)), .startRecording)
        XCTAssertNil(p.process(down(0.05, repeat: true)))
        XCTAssertNil(p.process(down(0.1, repeat: true)))
        XCTAssertEqual(p.mode, .holding)
        XCTAssertEqual(p.process(up(0.5)), .stopRecording)
    }

    func testUnrelatedKeysIgnored() {
        var p = makeProcessor()
        XCTAssertNil(p.process(down(0, code: 40)))
        XCTAssertNil(p.process(up(0.1, code: 40)))
        XCTAssertEqual(p.mode, .idle)
    }

    func testThresholdBoundaryCountsAsHold() {
        var p = makeProcessor()
        _ = p.process(down(0))
        XCTAssertEqual(p.process(up(0.25)), .stopRecording)
        XCTAssertEqual(p.mode, .idle)
    }

    func testLockedThenAnotherPressStops() {
        var p = makeProcessor()
        _ = p.process(down(0)); _ = p.process(up(0.1))
        XCTAssertEqual(p.process(down(1.0)), .stopRecording)
        XCTAssertEqual(p.mode, .idle)
    }
}
