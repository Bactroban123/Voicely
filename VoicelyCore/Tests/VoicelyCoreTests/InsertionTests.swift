import XCTest
@testable import VoicelyCore

final class InsertionTests: XCTestCase {
    func testPlanOrdering() {
        XCTAssertEqual(InsertPlan.methods(axFirst: true), [.accessibility, .paste, .copyOnly])
        XCTAssertEqual(InsertPlan.methods(axFirst: false), [.paste, .copyOnly])
    }

    func testAccessibilitySucceedsFirst() {
        let outcome = InsertPlan.resolve([.accessibility, .paste, .copyOnly]) { $0 == .accessibility }
        XCTAssertEqual(outcome, .inserted(.accessibility))
    }

    func testFallsThroughToPaste() {
        let outcome = InsertPlan.resolve([.accessibility, .paste, .copyOnly]) { $0 == .paste }
        XCTAssertEqual(outcome, .inserted(.paste))
    }

    func testEverythingFailsGivesCopyOnly() {
        let outcome = InsertPlan.resolve([.paste, .copyOnly]) { _ in false }
        XCTAssertEqual(outcome, .copiedOnly)
    }
}
