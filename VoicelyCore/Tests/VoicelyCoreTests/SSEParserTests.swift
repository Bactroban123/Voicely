import XCTest
@testable import VoicelyCore

final class SSEParserTests: XCTestCase {
    func testExtractsContentDelta() {
        XCTAssertEqual(SSE.delta(fromDataLine: #"data: {"choices":[{"delta":{"content":"Hel"}}]}"#), "Hel")
    }

    func testDoneYieldsNil() {
        XCTAssertNil(SSE.delta(fromDataLine: "data: [DONE]"))
    }

    func testCommentLineYieldsNil() {
        XCTAssertNil(SSE.delta(fromDataLine: ": keep-alive"))
    }

    func testEmptyDeltaYieldsNil() {
        XCTAssertNil(SSE.delta(fromDataLine: #"data: {"choices":[{"delta":{}}]}"#))
    }

    func testAssemblesStreamedDeltas() {
        let lines = [
            #"data: {"choices":[{"delta":{"content":"Send "}}]}"#,
            #"data: {"choices":[{"delta":{"content":"the thing."}}]}"#,
            "data: [DONE]",
        ]
        XCTAssertEqual(SSE.assemble(lines), "Send the thing.")
    }
}
