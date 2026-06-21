import Foundation
import VoicelyCore

// A tiny dependency-free test runner so VoicelyCore's pure logic can be verified
// with `swift run voicely-spec` on Command Line Tools (no full Xcode required).
// The XCTest suite under Tests/ mirrors these for when Xcode is present.

var failures = 0
var passes = 0
func check(_ cond: Bool, _ msg: String, line: UInt = #line) {
    if cond { passes += 1 }
    else { failures += 1; print("  ✗ \(msg)  (line \(line))") }
}

let hk: UInt16 = 61   // Right Option
let esc: UInt16 = 53
func config() -> HotKeyConfig { HotKeyConfig(hotKeyCode: hk, cancelKeyCode: esc, tapThreshold: 0.25) }
func down(_ t: TimeInterval, _ code: UInt16? = nil, repeat r: Bool = false) -> KeyEvent {
    KeyEvent(keyCode: code ?? hk, phase: .down, timestamp: t, isRepeat: r)
}
func up(_ t: TimeInterval, _ code: UInt16? = nil) -> KeyEvent {
    KeyEvent(keyCode: code ?? hk, phase: .up, timestamp: t)
}

print("HotKeyProcessor")

do { // hold = push-to-talk
    var p = HotKeyProcessor(config: config())
    check(p.process(down(0)) == .startRecording, "hold: starts on key-down")
    check(p.process(up(0.5)) == .stopRecording, "hold: stops on release after threshold")
    check(p.mode == .idle, "hold: returns to idle")
}
do { // quick tap = toggle on
    var p = HotKeyProcessor(config: config())
    check(p.process(down(0)) == .startRecording, "tap: starts on key-down")
    check(p.process(up(0.1)) == nil, "tap: release under threshold keeps recording")
    check(p.mode == .lockedRecording, "tap: enters locked recording")
}
do { // second tap stops
    var p = HotKeyProcessor(config: config())
    _ = p.process(down(0)); _ = p.process(up(0.1))
    check(p.process(down(1.0)) == .stopRecording, "locked: next press stops")
    check(p.mode == .idle, "locked: returns to idle")
    check(p.process(up(1.05)) == nil, "locked: trailing release ignored")
}
do { // esc cancels while holding
    var p = HotKeyProcessor(config: config())
    _ = p.process(down(0))
    check(p.process(down(0.1, esc)) == .cancel, "esc: cancels while holding")
    check(p.mode == .idle, "esc(holding): returns to idle")
}
do { // esc cancels while locked
    var p = HotKeyProcessor(config: config())
    _ = p.process(down(0)); _ = p.process(up(0.1))
    check(p.process(down(0.5, esc)) == .cancel, "esc: cancels while locked")
    check(p.mode == .idle, "esc(locked): returns to idle")
}
do { // esc idle is a no-op
    var p = HotKeyProcessor(config: config())
    check(p.process(down(0, esc)) == nil, "esc: no-op while idle")
}
do { // autorepeat ignored
    var p = HotKeyProcessor(config: config())
    check(p.process(down(0)) == .startRecording, "repeat: starts on first down")
    check(p.process(down(0.05, repeat: true)) == nil, "repeat: autorepeat ignored")
    check(p.mode == .holding, "repeat: still holding")
    check(p.process(up(0.5)) == .stopRecording, "repeat: stops on release")
}
do { // unrelated keys ignored
    var p = HotKeyProcessor(config: config())
    check(p.process(down(0, 40)) == nil, "other-key: down ignored")
    check(p.process(up(0.1, 40)) == nil, "other-key: up ignored")
    check(p.mode == .idle, "other-key: stays idle")
}
do { // threshold boundary is a hold
    var p = HotKeyProcessor(config: config())
    _ = p.process(down(0))
    check(p.process(up(0.25)) == .stopRecording, "boundary: dt == threshold is a hold")
}

print("CleanupPrompt")

do { // vocabulary rendering
    check(CleanupPrompt.renderVocabulary([]) == "(none)", "vocab: empty renders (none)")
    check(CleanupPrompt.renderVocabulary([VocabularyEntry(term: "Collabo")]) == "- Collabo",
          "vocab: bare term renders one bullet")
    let withVariants = CleanupPrompt.renderVocabulary([
        VocabularyEntry(term: "Keswadee", variants: ["kes wadi", "case wadi"]),
    ])
    check(withVariants == "- Keswadee (heard as: kes wadi, case wadi)",
          "vocab: variants render as 'heard as' list")
    let two = CleanupPrompt.renderVocabulary([
        VocabularyEntry(term: "Collabo"),
        VocabularyEntry(term: "kubectl", variants: ["cube cuddle"]),
    ])
    check(two == "- Collabo\n- kubectl (heard as: cube cuddle)", "vocab: multiple entries newline-joined")
}
do { // system prompt assembly
    let sys = CleanupPrompt.system(vocabulary: [VocabularyEntry(term: "Collabo")])
    check(sys.contains("editor, not an assistant"), "system: states editor-not-assistant guardrail")
    check(sys.contains("Output ONLY the cleaned text"), "system: forbids preamble/commentary")
    check(sys.contains("DO NOT add, invent"), "system: forbids inventing content")
    check(sys.contains("- Collabo"), "system: injects the vocabulary block")
    let empty = CleanupPrompt.system(vocabulary: [])
    check(empty.contains("(none)"), "system: empty vocab still well-formed")
}

if failures == 0 {
    print("\nALL PASS — \(passes) checks")
    exit(0)
} else {
    print("\n\(failures) FAILED, \(passes) passed")
    exit(1)
}
