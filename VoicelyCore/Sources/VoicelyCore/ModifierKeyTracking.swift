import Foundation

/// Derives a modifier key's down/up phase from the event's own flags bitmask
/// instead of remembering prior events.
///
/// Modifier-only hotkeys (⌥, ⌘, fn…) arrive as `flagsChanged` with no phase.
/// The old approach toggled membership in a Set — one dropped or coalesced
/// event permanently inverted down/up parity until another drop happened to
/// re-sync it ("recording won't start / won't stop" until relaunch). Reading
/// the bit for the key out of each event's raw flags is stateless, so a
/// dropped event can never cause lasting drift: the next event is always
/// interpreted correctly by construction.
///
/// The device bits are the left/right-distinguishing NX masks from IOKit's
/// IOLLEvent.h (`NX_DEVICE[LR]{CMD,SHIFT,ALT,CTL}KEYMASK`, `NX_SECONDARYFNMASK`),
/// which the public `CGEventFlags` cases don't expose — and the hotkey settings
/// offer Left vs Right Option as distinct choices. Verified against the SDK
/// headers (keycodes cross-checked against HIToolbox's `kVK_*`).
public enum ModifierKeyTracking {
    private struct Entry {
        /// This exact key's bit (left/right specific).
        let deviceBit: UInt64
        /// The device-independent mask for the key's family (⌘, ⇧, ⌥, ⌃, fn).
        let familyMask: UInt64
        /// The other side's device bit; 0 when the key has no sibling.
        let siblingBit: UInt64
    }

    private static let entries: [UInt16: Entry] = [
        // Command: NX_DEVICE{R,L}CMDKEYMASK, family = CGEventFlags.maskCommand
        54: Entry(deviceBit: 0x0000_0010, familyMask: 0x0010_0000, siblingBit: 0x0000_0008),
        55: Entry(deviceBit: 0x0000_0008, familyMask: 0x0010_0000, siblingBit: 0x0000_0010),
        // Shift: NX_DEVICE{L,R}SHIFTKEYMASK, family = maskShift
        56: Entry(deviceBit: 0x0000_0002, familyMask: 0x0002_0000, siblingBit: 0x0000_0004),
        60: Entry(deviceBit: 0x0000_0004, familyMask: 0x0002_0000, siblingBit: 0x0000_0002),
        // Option: NX_DEVICE{L,R}ALTKEYMASK, family = maskAlternate
        58: Entry(deviceBit: 0x0000_0020, familyMask: 0x0008_0000, siblingBit: 0x0000_0040),
        61: Entry(deviceBit: 0x0000_0040, familyMask: 0x0008_0000, siblingBit: 0x0000_0020),
        // Control: NX_DEVICE{L,R}CTLKEYMASK, family = maskControl
        59: Entry(deviceBit: 0x0000_0001, familyMask: 0x0004_0000, siblingBit: 0x0000_2000),
        62: Entry(deviceBit: 0x0000_2000, familyMask: 0x0004_0000, siblingBit: 0x0000_0001),
        // fn/Globe: NX_SECONDARYFNMASK is the same bit as maskSecondaryFn, no sibling.
        63: Entry(deviceBit: 0x0080_0000, familyMask: 0x0080_0000, siblingBit: 0),
    ]

    /// Whether the modifier identified by `keyCode` is held, per `rawFlags`
    /// (`CGEventFlags.rawValue`). `nil` for a keycode this table doesn't know —
    /// the caller should fall back to its legacy inference for those.
    public static func isDown(keyCode: UInt16, rawFlags: UInt64) -> Bool? {
        guard let entry = entries[keyCode] else { return nil }
        if rawFlags & entry.deviceBit != 0 { return true }
        // Synthetic events (some automation tools post via CGEventPost) can set
        // only the device-independent family bit. If the family says a key of
        // this kind is held and the other side definitively isn't, attribute it
        // here rather than reading "up" forever and killing the hotkey.
        if rawFlags & entry.familyMask != 0, rawFlags & entry.siblingBit == 0 {
            return true
        }
        return false
    }
}
