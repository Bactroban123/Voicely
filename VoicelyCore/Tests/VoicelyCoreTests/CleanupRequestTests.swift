import XCTest
@testable import VoicelyCore

final class CleanupRequestTests: XCTestCase {
    private func json(_ req: CleanupRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: req.jsonData()) as? [String: Any])
    }

    func testBodyCarriesModelAndMessages() throws {
        let obj = try json(CleanupRequest(modelID: "google/gemini-2.5-flash-lite",
                                          systemPrompt: "SYS", transcript: "hello world"))
        XCTAssertEqual(obj["model"] as? String, "google/gemini-2.5-flash-lite")
        let msgs = try XCTUnwrap(obj["messages"] as? [[String: Any]])
        XCTAssertEqual(msgs.count, 2)
        XCTAssertEqual(msgs[0]["role"] as? String, "system")
        XCTAssertEqual(msgs[0]["content"] as? String, "SYS")
        XCTAssertEqual(msgs[1]["role"] as? String, "user")
        XCTAssertEqual(msgs[1]["content"] as? String, "hello world")
    }

    func testLatencyAndPrivacyDefaults() throws {
        let obj = try json(CleanupRequest(modelID: "m", systemPrompt: "s", transcript: "t"))
        XCTAssertEqual(obj["temperature"] as? Double, 0.1)
        XCTAssertEqual(obj["max_tokens"] as? Int, 400)
        XCTAssertEqual(obj["stream"] as? Bool, true)
        let reasoning = try XCTUnwrap(obj["reasoning"] as? [String: Any])
        XCTAssertEqual(reasoning["enabled"] as? Bool, false)
        let provider = try XCTUnwrap(obj["provider"] as? [String: Any])
        XCTAssertEqual(provider["sort"] as? String, "latency")
        XCTAssertEqual(provider["data_collection"] as? String, "deny")
        XCTAssertEqual(provider["zdr"] as? Bool, true)
    }

    func testZeroRetentionCanBeRelaxed() throws {
        let obj = try json(CleanupRequest(modelID: "m", systemPrompt: "s", transcript: "t", zeroRetention: false))
        let provider = try XCTUnwrap(obj["provider"] as? [String: Any])
        XCTAssertEqual(provider["data_collection"] as? String, "allow")
        XCTAssertEqual(provider["zdr"] as? Bool, false)
    }
}
