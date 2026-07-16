import XCTest
@testable import VoicelyCore

final class ModifierKeyTrackingTests: XCTestCase {
    // Device-independent family masks (CGEventFlags), spelled out so the tests
    // read like the real events they stand in for.
    private let maskShift: UInt64     = 0x0002_0000
    private let maskControl: UInt64   = 0x0004_0000
    private let maskAlternate: UInt64 = 0x0008_0000
    private let maskCommand: UInt64   = 0x0010_0000
    private let maskSecondaryFn: UInt64 = 0x0080_0000
    /// Every real event carries this; it must never affect the answer.
    private let nonCoalesced: UInt64  = 0x0000_0100

    func testRealRightOptionPressAndRelease() {
        // A real ⌥-right press: device bit + family mask + non-coalesced flag.
        let pressed = 0x40 | maskAlternate | nonCoalesced
        XCTAssertEqual(ModifierKeyTracking.isDown(keyCode: 61, rawFlags: pressed), true)
        // Release: only the non-coalesced flag survives.
        XCTAssertEqual(ModifierKeyTracking.isDown(keyCode: 61, rawFlags: nonCoalesced), false)
    }

    func testRightOptionBitIsolatedFromOtherModifiers() {
        // Holding ⌘ and ⇧ (with their family masks) must not read as ⌥-right.
        let others = 0x08 | maskCommand | 0x02 | maskShift | nonCoalesced
        XCTAssertEqual(ModifierKeyTracking.isDown(keyCode: 61, rawFlags: others), false)
    }

    func testLeftAndRightOfTheSameFamilyAreDistinct() {
        // A real LEFT-option press must not read as RIGHT option down…
        let leftDown = 0x20 | maskAlternate | nonCoalesced
        XCTAssertEqual(ModifierKeyTracking.isDown(keyCode: 61, rawFlags: leftDown), false)
        XCTAssertEqual(ModifierKeyTracking.isDown(keyCode: 58, rawFlags: leftDown), true)
        // …and vice versa.
        let rightDown = 0x40 | maskAlternate | nonCoalesced
        XCTAssertEqual(ModifierKeyTracking.isDown(keyCode: 58, rawFlags: rightDown), false)
    }

    func testEveryMappedKeyRoundTrips() {
        let expected: [UInt16: UInt64] = [
            54: 0x10, 55: 0x08, 56: 0x02, 58: 0x20,
            59: 0x01, 60: 0x04, 61: 0x40, 62: 0x2000, 63: 0x80_0000,
        ]
        for (code, bit) in expected {
            XCTAssertEqual(ModifierKeyTracking.isDown(keyCode: code, rawFlags: bit), true, "keyCode \(code)")
            XCTAssertEqual(ModifierKeyTracking.isDown(keyCode: code, rawFlags: 0), false, "keyCode \(code)")
        }
    }

    func testFnKeyUsesTheSharedSecondaryFnBit() {
        XCTAssertEqual(ModifierKeyTracking.isDown(keyCode: 63, rawFlags: maskSecondaryFn | nonCoalesced), true)
        XCTAssertEqual(ModifierKeyTracking.isDown(keyCode: 63, rawFlags: nonCoalesced), false)
        // Another modifier being held must not read as fn.
        XCTAssertEqual(ModifierKeyTracking.isDown(keyCode: 63, rawFlags: 0x40 | maskAlternate), false)
    }

    func testSyntheticEventWithOnlyFamilyMaskIsTreatedAsHeld() {
        // Some automation tools post flagsChanged with only the
        // device-independent bit. Reading that as "up" would kill the hotkey
        // outright, so attribute it when the other side is definitively clear.
        XCTAssertEqual(ModifierKeyTracking.isDown(keyCode: 61, rawFlags: maskAlternate), true)
        XCTAssertEqual(ModifierKeyTracking.isDown(keyCode: 58, rawFlags: maskAlternate), true)
        // But when the sibling's device bit IS present, the family bit belongs
        // to the sibling, not to us.
        XCTAssertEqual(ModifierKeyTracking.isDown(keyCode: 61, rawFlags: maskAlternate | 0x20), false)
    }

    func testSameFlagsTwiceGiveSameAnswer() {
        // The property the old Set-toggle approach violated: feeding the same
        // event twice must not flip the answer. Stateless by construction.
        let flags = 0x40 | maskAlternate | nonCoalesced
        let first = ModifierKeyTracking.isDown(keyCode: 61, rawFlags: flags)
        let second = ModifierKeyTracking.isDown(keyCode: 61, rawFlags: flags)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, true)
    }

    func testDroppedReleaseSelfHealsOnTheNextPress() {
        // The P1-5 regression case: a release event never arrives, then the key
        // is pressed again. Stateless reading must report the press as .down —
        // the Set toggle would have reported .up and inverted parity for good.
        let pressed = 0x40 | maskAlternate | nonCoalesced
        XCTAssertEqual(ModifierKeyTracking.isDown(keyCode: 61, rawFlags: pressed), true)
        // (release dropped — no call happens for it)
        XCTAssertEqual(ModifierKeyTracking.isDown(keyCode: 61, rawFlags: pressed), true)
    }

    func testUnmappedKeyCodesReturnNilForFallback() {
        XCTAssertNil(ModifierKeyTracking.isDown(keyCode: 57, rawFlags: 0xFFFF))  // caps lock
        XCTAssertNil(ModifierKeyTracking.isDown(keyCode: 96, rawFlags: 0x40))    // F5: not a modifier
        XCTAssertNil(ModifierKeyTracking.isDown(keyCode: 0, rawFlags: 0x40))     // 'a'
    }
}
