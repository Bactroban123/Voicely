import AppKit
import CoreGraphics
import Foundation
import os
import VoicelyCore

/// Listens to global key events via a CGEventTap and feeds them to the pure
/// `HotKeyProcessor`. Requires Input Monitoring permission; `start()` returns
/// false if the tap couldn't be created (i.e. permission not granted yet).
final class KeyEventMonitor {
    /// Why macOS disabled the tap, for the app layer to surface.
    enum TapIssue {
        /// Our callback was too slow to service events; the OS cut the tap off.
        case timeout
        /// The user's own input disabled it (a documented macOS behaviour).
        case userInput
    }

    private static let signposter = OSSignposter(subsystem: "com.voicely.app", category: "tap")

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Fallback only, for modifier keycodes not in the device-bit table.
    private var heldModifiers: Set<Int64> = []
    private var disableTracker = TapDisableTracker()
    private let onEvent: (KeyEvent) -> Void

    /// Called on the main run loop when macOS disables the tap and we re-enable
    /// it. `repeatedly` is true once disables cluster (3+ inside a minute),
    /// meaning self-healing isn't keeping up and the user should know.
    var onTapIssue: ((TapIssue, _ repeatedly: Bool) -> Void)?

    init(onEvent: @escaping (KeyEvent) -> Void) {
        self.onEvent = onEvent
    }

    func start() -> Bool {
        let mask: CGEventMask =
            CGEventMask(1 << CGEventType.keyDown.rawValue) |
            CGEventMask(1 << CGEventType.keyUp.rawValue) |
            CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            if let refcon = refcon {
                let monitor = Unmanaged<KeyEventMonitor>.fromOpaque(refcon).takeUnretainedValue()
                // Canary: a slow tap callback delays keyboard delivery for every
                // app in the session, and macOS force-disables taps that stall
                // (~1s). Apple's responsiveness guidance is single-digit ms, so
                // anything past 8ms is logged as an early warning. The log call
                // itself is non-blocking (async file mirror).
                let interval = KeyEventMonitor.signposter.beginInterval("tapCallback")
                let started = CFAbsoluteTimeGetCurrent()
                monitor.handle(type: type, event: event)
                let elapsedMs = (CFAbsoluteTimeGetCurrent() - started) * 1000
                KeyEventMonitor.signposter.endInterval("tapCallback", interval)
                if elapsedMs > 8 {
                    VoicelyLog.hotkey.warning("tap callback took \(Int(elapsedMs))ms (budget 8ms)")
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        // Don't carry stale key/disable state into the next tap.
        heldModifiers.removeAll()
        disableTracker.reset()
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // These two arrive on the same callback when macOS shuts the tap down.
        // Without re-enabling, the hotkey silently dies until the app is
        // relaunched — which is exactly what a stalled callback used to cause.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            handleTapDisabled(type == .tapDisabledByTimeout ? .timeout : .userInput)
            return
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let now = ProcessInfo.processInfo.systemUptime

        switch type {
        case .keyDown:
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            emit(keyCode, .down, now, isRepeat)
        case .keyUp:
            emit(keyCode, .up, now, false)
        case .flagsChanged:
            emitModifier(keyCode, flags: event.flags.rawValue, at: now)
        default:
            break
        }
    }

    /// Modifier keys arrive as flagsChanged with no phase. Read the key's own
    /// bit out of this event's flags rather than remembering prior events: a
    /// dropped or coalesced event then can't invert down/up parity for good
    /// (the old Set-toggle approach wedged until relaunch when that happened).
    private func emitModifier(_ keyCode: Int64, flags: UInt64, at now: TimeInterval) {
        guard let isDown = ModifierKeyTracking.isDown(keyCode: UInt16(truncatingIfNeeded: keyCode),
                                                      rawFlags: flags) else {
            // Unmapped modifier: fall back to the legacy inference.
            if heldModifiers.contains(keyCode) {
                heldModifiers.remove(keyCode)
                emit(keyCode, .up, now, false)
            } else {
                heldModifiers.insert(keyCode)
                emit(keyCode, .down, now, false)
            }
            return
        }
        emit(keyCode, isDown ? .down : .up, now, false)
    }

    private func handleTapDisabled(_ issue: TapIssue) {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)

        let response = disableTracker.record(at: ProcessInfo.processInfo.systemUptime)
        VoicelyLog.hotkey.warning(
            "event tap disabled by \(issue == .timeout ? "timeout" : "user input") — re-enabled"
                + " (\(disableTracker.recentCount) in the last minute)")

        // Hand off asynchronously: the callback owes the OS a fast return (a
        // timeout notice must not help cause the next timeout), and the
        // handler shows UI.
        let notify = onTapIssue
        DispatchQueue.main.async { notify?(issue, response == .recoveredUnreliable) }
    }

    private func emit(_ keyCode: Int64, _ phase: KeyPhase, _ ts: TimeInterval, _ isRepeat: Bool) {
        onEvent(KeyEvent(keyCode: UInt16(truncatingIfNeeded: keyCode),
                         phase: phase, timestamp: ts, isRepeat: isRepeat))
    }
}
