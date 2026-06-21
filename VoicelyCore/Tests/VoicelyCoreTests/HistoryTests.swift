import XCTest
@testable import VoicelyCore

final class HistoryTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 1000)

    func testTrimsAndAdds() {
        let h = History.add("  hello  ", to: [], now: t)
        XCTAssertEqual(h.map(\.text), ["hello"])
    }
    func testIgnoresEmpty() {
        XCTAssertEqual(History.add("   ", to: [], now: t).count, 0)
    }
    func testDeDupesImmediateRepeat() {
        var h = History.add("hello", to: [], now: t)
        h = History.add("hello", to: h, now: t)
        XCTAssertEqual(h.count, 1)
    }
    func testNewestFirst() {
        var h = History.add("one", to: [], now: t)
        h = History.add("two", to: h, now: t)
        XCTAssertEqual(h.map(\.text), ["two", "one"])
    }
    func testCaps() {
        var h: [HistoryEntry] = []
        for i in 0..<10 { h = History.add("item \(i)", to: h, now: t, cap: 3) }
        XCTAssertEqual(h.map(\.text), ["item 9", "item 8", "item 7"])
    }
    func testSearch() {
        let list = [HistoryEntry(text: "Send Gal the report", date: t),
                    HistoryEntry(text: "buy milk", date: t)]
        XCTAssertEqual(History.search("GAL", in: list).count, 1)
        XCTAssertEqual(History.search("", in: list).count, 2)
    }
    func testPreview() {
        XCTAssertEqual(History.preview("line one\nline two"), "line one line two")
        XCTAssertTrue(History.preview(String(repeating: "a", count: 60), max: 10).hasSuffix("…"))
    }
}
