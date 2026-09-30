import XCTest
@testable import VoicelyCore

/// Regression tests for the bug that made dictation hang forever: WhisperKit's
/// default download base is `~/Documents/huggingface`, and `~/Documents` is
/// synced by iCloud Drive. Once the disk filled up, macOS evicted the 1.5 GB of
/// model weights to the cloud (`dataless` flag). Reading an evicted file blocks
/// in `read(2)` until iCloud materialises it — which never happened — so
/// `prepare()` never returned and the HUD sat in "transcribing" indefinitely.
///
/// Model weights are large, re-downloadable, and must never live anywhere the
/// system is allowed to sync, evict, or purge them.
final class ModelStorageTests: XCTestCase {
    private let appSupport = URL(fileURLWithPath: "/Users/test/Library/Application Support", isDirectory: true)

    func testModelsLiveUnderApplicationSupport() {
        let dir = ModelStorage.modelsDirectory(applicationSupport: appSupport)
        XCTAssertEqual(dir.path, "/Users/test/Library/Application Support/Voicely/Models")
    }

    func testModelsDirectoryIsSafe() {
        XCTAssertTrue(ModelStorage.isSafeForModelWeights(ModelStorage.modelsDirectory(applicationSupport: appSupport)))
    }

    /// The actual regression: the old location.
    func testDocumentsIsRejected() {
        let old = URL(fileURLWithPath: "/Users/test/Documents/huggingface", isDirectory: true)
        XCTAssertFalse(ModelStorage.isSafeForModelWeights(old),
                       "~/Documents is iCloud-synced — weights get evicted and reads block forever")
    }

    func testOtherSyncedOrPurgeableLocationsAreRejected() {
        let rejected = [
            "/Users/test/Desktop/models",
            "/Users/test/Library/Mobile Documents/com~apple~CloudDocs/models",
            "/Users/test/Library/CloudStorage/iCloudDrive/models",
            "/Users/test/Library/Caches/models",          // purgeable: silent 1.5 GB re-download
            "/Users/test/Documents",
        ]
        for path in rejected {
            XCTAssertFalse(ModelStorage.isSafeForModelWeights(URL(fileURLWithPath: path, isDirectory: true)),
                           "\(path) must be rejected")
        }
    }
}
