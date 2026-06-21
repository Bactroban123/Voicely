import XCTest
@testable import VoicelyCore

final class ModelCatalogTests: XCTestCase {
    func testOptionCounts() {
        XCTAssertEqual(ModelCatalog.transcription.count, 4)
        XCTAssertEqual(ModelCatalog.cleanup.count, 4)
    }

    func testDefaultsExistInLists() {
        XCTAssertNotNil(ModelCatalog.transcriptionModel(id: ModelCatalog.defaultTranscriptionID))
        XCTAssertNotNil(ModelCatalog.cleanupModel(id: ModelCatalog.defaultCleanupID))
    }

    func testIDsAreUnique() {
        XCTAssertEqual(Set(ModelCatalog.transcription.map(\.id)).count, ModelCatalog.transcription.count)
        XCTAssertEqual(Set(ModelCatalog.cleanup.map(\.id)).count, ModelCatalog.cleanup.count)
    }
}
