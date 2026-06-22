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

print("Pipeline")

do { // happy path with cleanup on
    var p = Pipeline(cleanupEnabled: true)
    check(p.handle(.startedRecording) == .none, "pipeline: start recording")
    check(p.state == .recording, "pipeline: in recording")
    check(p.handle(.stoppedRecording) == .beginTranscription, "pipeline: stop → transcribe")
    check(p.handle(.transcript("hello")) == .beginCleanup("hello"), "pipeline: transcript → cleanup (on)")
    check(p.state == .refining, "pipeline: in refining")
    check(p.handle(.cleaned("Hello.")) == .insert("Hello."), "pipeline: cleaned → insert")
    check(p.handle(.inserted) == .none, "pipeline: inserted → idle")
    check(p.state == .idle, "pipeline: back to idle")
}
do { // cleanup off inserts raw
    var p = Pipeline(cleanupEnabled: false)
    _ = p.handle(.startedRecording); _ = p.handle(.stoppedRecording)
    check(p.handle(.transcript("raw text")) == .insert("raw text"), "pipeline: cleanup off → insert raw")
    check(p.state == .inserting, "pipeline: skips refining when cleanup off")
}
do { // cleanup failure falls back to raw (never lose the transcript)
    var p = Pipeline(cleanupEnabled: true)
    _ = p.handle(.startedRecording); _ = p.handle(.stoppedRecording)
    _ = p.handle(.transcript("kept raw"))
    check(p.handle(.cleanupFailed) == .insert("kept raw"), "pipeline: cleanup fail → insert raw fallback")
}
do { // cancel from anywhere
    var p = Pipeline(cleanupEnabled: true)
    _ = p.handle(.startedRecording)
    check(p.handle(.cancelled) == .none, "pipeline: cancel → none")
    check(p.state == .idle, "pipeline: cancel returns to idle")
}
do { // transcription failure goes idle with nothing pending
    var p = Pipeline(cleanupEnabled: true)
    _ = p.handle(.startedRecording); _ = p.handle(.stoppedRecording)
    check(p.handle(.transcriptionFailed) == .none, "pipeline: transcription fail → none")
    check(p.state == .idle, "pipeline: transcription fail → idle")
}

print("Insertion")

do { // plan ordering
    check(InsertPlan.methods(axFirst: true) == [.accessibility, .paste, .copyOnly], "insert: ax-first plan")
    check(InsertPlan.methods(axFirst: false) == [.paste, .copyOnly], "insert: paste-first plan")
}
do { // resolution
    let axWins = InsertPlan.resolve([.accessibility, .paste, .copyOnly]) { $0 == .accessibility }
    check(axWins == .inserted(.accessibility), "insert: AX succeeds first")
    let pasteWins = InsertPlan.resolve([.accessibility, .paste, .copyOnly]) { $0 == .paste }
    check(pasteWins == .inserted(.paste), "insert: falls through to paste")
    let copyOnly = InsertPlan.resolve([.paste, .copyOnly]) { _ in false }
    check(copyOnly == .copiedOnly, "insert: everything fails → copy-only")
}

print("ModelCatalog")

do {
    check(ModelCatalog.transcription.count == 4, "models: 4 transcription options")
    check(ModelCatalog.cleanup.count == 4, "models: 4 cleanup options")
    check(ModelCatalog.transcriptionModel(id: ModelCatalog.defaultTranscriptionID) != nil,
          "models: default transcription id exists in list")
    check(ModelCatalog.cleanupModel(id: ModelCatalog.defaultCleanupID) != nil,
          "models: default cleanup id exists in list")
    let tIDs = Set(ModelCatalog.transcription.map { $0.id })
    check(tIDs.count == ModelCatalog.transcription.count, "models: transcription ids unique")
    let cIDs = Set(ModelCatalog.cleanup.map { $0.id })
    check(cIDs.count == ModelCatalog.cleanup.count, "models: cleanup ids unique")
}

print("CleanupRequest")

do {
    let req = CleanupRequest(modelID: "google/gemini-2.5-flash-lite",
                             systemPrompt: "SYS", transcript: "hello world")
    let data = try! req.jsonData()
    let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    check(obj["model"] as? String == "google/gemini-2.5-flash-lite", "request: model set")
    let msgs = obj["messages"] as! [[String: Any]]
    check(msgs.count == 2, "request: two messages")
    check(msgs[0]["role"] as? String == "system" && msgs[0]["content"] as? String == "SYS", "request: system message")
    check(msgs[1]["role"] as? String == "user" && msgs[1]["content"] as? String == "hello world", "request: user transcript")
    check((obj["temperature"] as? Double) == 0.1, "request: temperature 0.1")
    check((obj["max_tokens"] as? Int) == 400, "request: max_tokens 400")
    check((obj["stream"] as? Bool) == true, "request: streaming on")
    let reasoning = obj["reasoning"] as! [String: Any]
    check((reasoning["enabled"] as? Bool) == false, "request: reasoning disabled")
    let provider = obj["provider"] as! [String: Any]
    check(provider["sort"] as? String == "latency", "request: provider sort latency")
    check(provider["data_collection"] as? String == "deny", "request: data_collection deny (zdr default)")
    check((provider["zdr"] as? Bool) == true, "request: zdr on by default")

    let open = CleanupRequest(modelID: "m", systemPrompt: "s", transcript: "t", zeroRetention: false)
    let oobj = try! JSONSerialization.jsonObject(with: open.jsonData()) as! [String: Any]
    let oprov = oobj["provider"] as! [String: Any]
    check(oprov["data_collection"] as? String == "allow" && (oprov["zdr"] as? Bool) == false,
          "request: zeroRetention=false relaxes routing")
}

print("SSE")

do {
    check(SSE.delta(fromDataLine: #"data: {"choices":[{"delta":{"content":"Hel"}}]}"#) == "Hel",
          "sse: extracts content delta")
    check(SSE.delta(fromDataLine: "data: [DONE]") == nil, "sse: [DONE] yields nil")
    check(SSE.delta(fromDataLine: ": keep-alive") == nil, "sse: comment line yields nil")
    check(SSE.delta(fromDataLine: #"data: {"choices":[{"delta":{}}]}"#) == nil, "sse: empty delta yields nil")
    let lines = [
        #"data: {"choices":[{"delta":{"content":"Send "}}]}"#,
        #"data: {"choices":[{"delta":{"content":"the thing."}}]}"#,
        "data: [DONE]",
    ]
    check(SSE.assemble(lines) == "Send the thing.", "sse: assembles streamed deltas")
}

print("SnippetExpander")

do {
    let s = [Snippet(trigger: "my email", expansion: "gal@example.com")]
    check(SnippetExpander.expand("my email", snippets: s) == "gal@example.com", "snippet: whole-utterance expands")
    check(SnippetExpander.expand("send it to my email please", snippets: s) == "send it to gal@example.com please",
          "snippet: inline expansion")
    check(SnippetExpander.expand("My Email", snippets: s) == "gal@example.com", "snippet: case-insensitive")
    check(SnippetExpander.expand("no trigger here", snippets: s) == "no trigger here", "snippet: no match unchanged")
    check(SnippetExpander.expand("anything", snippets: []) == "anything", "snippet: empty list unchanged")
}
do { // longer trigger wins
    let s = [Snippet(trigger: "email", expansion: "E"), Snippet(trigger: "my email", expansion: "FULL")]
    check(SnippetExpander.expand("my email", snippets: s) == "FULL", "snippet: longer trigger applied first")
}
do { // expansion with regex-special chars is literal
    let s = [Snippet(trigger: "price", expansion: "$5 (50% off)")]
    check(SnippetExpander.expand("the price", snippets: s) == "the $5 (50% off)", "snippet: special chars in expansion are literal")
}

print("CleanupModes")

do {
    check(CleanupModes.all.count == 7, "modes: seven presets (clean/polish/prompt/translate x4)")
    check(CleanupModes.mode(id: CleanupModes.defaultID) != nil, "modes: default id exists")
    let vocab = [VocabularyEntry(term: "Vercel")]
    let clean = CleanupModes.system(modeID: "clean", vocabulary: vocab)
    check(clean.contains("editor, not an assistant"), "modes: clean uses the conservative prompt")
    let polish = CleanupModes.system(modeID: "polish", vocabulary: vocab)
    check(polish.contains("concise") || polish.contains("Tighten"), "modes: polish tightens for clarity")
    check(polish.contains("- Vercel"), "modes: polish injects vocabulary")
    let prompt = CleanupModes.system(modeID: "prompt", vocabulary: vocab)
    check(prompt.contains("prompt-engineering"), "modes: prompt reshapes into an AI prompt")
    check(prompt.contains("- Vercel"), "modes: prompt injects vocabulary")
    let tEN = CleanupModes.system(modeID: "translate-en", vocabulary: vocab)
    check(tEN.contains("fluent English"), "modes: translate-en targets English")
    check(tEN.contains("- Vercel"), "modes: translate-en injects vocabulary")
    let tHE = CleanupModes.system(modeID: "translate-he", vocabulary: vocab)
    check(tHE.contains("Hebrew"), "modes: translate-he targets Hebrew")
    let tTH = CleanupModes.system(modeID: "translate-th", vocabulary: vocab)
    check(tTH.contains("Thai"), "modes: translate-th targets Thai")
    check(tTH.contains("- Vercel"), "modes: translate-th injects vocabulary")
    let tTHEN = CleanupModes.system(modeID: "translate-th-en", vocabulary: vocab)
    check(tTHEN.contains("spoken Thai"), "modes: translate-th-en declares Thai source")
    check(tTHEN.contains("fluent English"), "modes: translate-th-en targets English")
    check(tTHEN.contains("ครับ"), "modes: translate-th-en notes Thai politeness particles")
    check(CleanupModes.mode(id: "translate-th")?.name == "Translate → Thai", "modes: translate-th has a friendly label")
    let unknown = CleanupModes.system(modeID: "nope", vocabulary: vocab)
    check(unknown.contains("editor, not an assistant"), "modes: unknown id falls back to clean")
}

print("History")

do {
    let t = Date(timeIntervalSince1970: 1000)
    var h: [HistoryEntry] = []
    h = History.add("  hello  ", to: h, now: t)
    check(h.count == 1 && h[0].text == "hello", "history: trims and adds")
    h = History.add("   ", to: h, now: t)
    check(h.count == 1, "history: ignores empty/whitespace")
    h = History.add("hello", to: h, now: t)
    check(h.count == 1, "history: de-dupes immediate repeat")
    h = History.add("world", to: h, now: t)
    check(h.count == 2 && h[0].text == "world", "history: newest first")

    var capped: [HistoryEntry] = []
    for i in 0..<10 { capped = History.add("item \(i)", to: capped, now: t, cap: 3) }
    check(capped.count == 3 && capped[0].text == "item 9", "history: caps to newest N")

    let list = [HistoryEntry(text: "Send Gal the report", date: t),
                HistoryEntry(text: "buy milk", date: t)]
    check(History.search("GAL", in: list).count == 1, "history: search is case-insensitive")
    check(History.search("", in: list).count == 2, "history: empty query returns all")
    check(History.preview("line one\nline two") == "line one line two", "history: preview flattens newlines")
    check(History.preview(String(repeating: "a", count: 60), max: 10).hasSuffix("…"), "history: preview truncates")
}

print("AutoLearn — vocabulary")

do { // learns recurring proper nouns, ignores one-offs and pronouns
    let ts = [
        "I met Keswadee at the studio in Bangkok.",
        "Keswadee runs the Bangkok shop.",
        "We deployed to Vercel today.",
    ]
    let names = AutoLearn.vocabularyTerms(from: ts, minDistinct: 2).map { $0.term }
    check(names.contains("Keswadee"), "autolearn: learns proper noun even when later sentence-initial")
    check(names.contains("Bangkok"), "autolearn: learns recurring place name")
    check(!names.contains("Vercel"), "autolearn: ignores a one-off term (minDistinct 2)")
    check(!names.contains("I"), "autolearn: skips pronouns / short tokens")
}
do { // PascalCase + acronyms
    let ts = ["The API returned an error.", "Our API is fast.",
              "OpenRouter is great.", "I love OpenRouter."]
    let names = AutoLearn.vocabularyTerms(from: ts, minDistinct: 2).map { $0.term }
    check(names.contains("API"), "autolearn: learns acronym (internal caps)")
    check(names.contains("OpenRouter"), "autolearn: learns PascalCase product name")
}
do { // capitalized bigram name
    let ts = ["I work at Tattoo Genesis downtown.", "Tattoo Genesis is hiring.", "love Tattoo Genesis"]
    let names = AutoLearn.vocabularyTerms(from: ts, minDistinct: 2).map { $0.term }
    check(names.contains("Tattoo Genesis"), "autolearn: learns a two-word capitalized name")
}
do { // a bigram adjacent only across a sentence boundary is NOT counted
    let ts = ["I love Tattoo Genesis here.", "We went to Tattoo. Genesis was closed."]
    let names = AutoLearn.vocabularyTerms(from: ts, minDistinct: 2).map { $0.term }
    check(!names.contains("Tattoo Genesis"), "autolearn: bigram count respects sentence boundaries")
}
do { // a common capitalized interjection is not learned
    let ts = ["He said Hello there.", "She said Hello again."]
    let names = AutoLearn.vocabularyTerms(from: ts, minDistinct: 2).map { $0.term }
    check(!names.contains("Hello"), "autolearn: skips capitalized interjections (stopword)")
}
do { // exclusions: existing vocab + dismissed (case-insensitive)
    let ts = ["I met Keswadee in Bangkok.", "Keswadee called from Bangkok."]
    let withExisting = AutoLearn.vocabularyTerms(
        from: ts, existing: [VocabularyEntry(term: "bangkok")], minDistinct: 2).map { $0.term.lowercased() }
    check(!withExisting.contains("bangkok"), "autolearn: excludes terms already in vocabulary")
    let withDismissed = AutoLearn.vocabularyTerms(
        from: ts, dismissed: ["keswadee"], minDistinct: 2).map { $0.term.lowercased() }
    check(!withDismissed.contains("keswadee"), "autolearn: excludes dismissed terms")
}

print("AutoLearn — snippets")

do { // suggests a repeated phrase, prefers the longest
    let ts = [
        "Please book a consultation with the artist.",
        "Can you please book a consultation today?",
        "please book a consultation",
    ]
    let sug = AutoLearn.snippetSuggestions(from: ts, minDistinct: 2)
    check(!sug.isEmpty, "autolearn: surfaces a recurring phrase")
    check(sug.contains { $0.phrase.lowercased().contains("book a consultation") },
          "autolearn: suggestion contains the repeated phrase")
    check(sug[0].count >= 2, "autolearn: counts the repeats")
    check(!sug[0].suggestedTrigger.isEmpty, "autolearn: proposes an editable trigger")
}
do { // n-grams do not glue across a sentence boundary
    let ts = ["The shop was closed. Please call again.", "The shop was closed. Please call again."]
    let sug = AutoLearn.snippetSuggestions(from: ts, minDistinct: 2)
    check(!sug.contains { $0.phrase.lowercased().contains("closed please") },
          "autolearn: snippet n-grams respect sentence boundaries")
}
do { // ignores non-repeated text and existing snippets (even with trailing punctuation)
    let once = AutoLearn.snippetSuggestions(
        from: ["a totally unique sentence that only appears one single time"], minDistinct: 2)
    check(once.isEmpty, "autolearn: ignores phrases that do not repeat")
    let ts = ["call me at the studio", "call me at the studio", "call me at the studio"]
    let withExisting = AutoLearn.snippetSuggestions(
        from: ts, existing: [Snippet(trigger: "studio", expansion: "Call me at the studio.")], minDistinct: 2)
    check(!withExisting.contains { $0.phrase.lowercased().contains("call me at the studio") },
          "autolearn: excludes existing snippet expansion despite punctuation/casing")
}

if failures == 0 {
    print("\nALL PASS — \(passes) checks")
    exit(0)
} else {
    print("\n\(failures) FAILED, \(passes) passed")
    exit(1)
}
