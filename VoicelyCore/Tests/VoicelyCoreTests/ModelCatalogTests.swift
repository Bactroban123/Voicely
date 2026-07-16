import XCTest
@testable import VoicelyCore

final class ModelCatalogTests: XCTestCase {
    func testOptionCounts() {
        XCTAssertEqual(ModelCatalog.transcription.count, 3)
        XCTAssertEqual(ModelCatalog.cleanup.count, 4)
    }

    /// Every offered engine must have an implementation behind it: the old
    /// "apple-speech" entry silently fell back to Parakeet when selected.
    func testEveryTranscriptionOptionIsImplemented() {
        let implemented: Set<String> = ["parakeet-en", "parakeet-multi", "whisper-large-v3-turbo"]
        for option in ModelCatalog.transcription {
            XCTAssertTrue(implemented.contains(option.id), "\(option.id) has no engine")
        }
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
