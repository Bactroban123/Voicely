import AppKit
import CoreGraphics
import Foundation
import VoicelyCore

/// Listens to global key events via a CGEventTap and feeds them to the pure
/// `HotKeyProcessor`. Requires Input Monitoring permission; `start()` returns
/// false if the tap couldn't be created (i.e. permission not granted yet).
final class KeyEventMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Modifier keys (fn, ⌥, etc.) arrive via flagsChanged with no up/down phase,
    /// so we track which modifier keycodes are currently held to infer it.
    private var heldModifiers: Set<Int64> = []
    private let onEvent: (KeyEvent) -> Void

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
                monitor.handle(type: type, event: event)
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
    }

    private func handle(type: CGEventType, event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let now = ProcessInfo.processInfo.systemUptime

        switch type {
        case .keyDown:
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            emit(keyCode, .down, now, isRepeat)
        case .keyUp:
            emit(keyCode, .up, now, false)
        case .flagsChanged:
            if heldModifiers.contains(keyCode) {
                heldModifiers.remove(keyCode)
                emit(keyCode, .up, now, false)
            } else {
                heldModifiers.insert(keyCode)
                emit(keyCode, .down, now, false)
            }
        default:
            break
        }
    }

    private func emit(_ keyCode: Int64, _ phase: KeyPhase, _ ts: TimeInterval, _ isRepeat: Bool) {
        onEvent(KeyEvent(keyCode: UInt16(truncatingIfNeeded: keyCode),
                         phase: phase, timestamp: ts, isRepeat: isRepeat))
    }
}
