import XCTest
@testable import VoicelyCore

/// Regression tests for "dictation doesn't work offline": with no
/// `modelFolder`, WhisperKit lists the Hugging Face repo over the network
/// before it will look at disk, so every offline model load failed with
/// "The Internet connection appears to be offline" while all 1.5 GB of
/// weights sat in Application Support. Finding the downloaded folder lets the
/// load skip the network entirely.
final class LocalWhisperKitFolderTests: XCTestCase {
    private var base: URL!
    private let variant = "large-v3-v20240930_turbo"

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalWhisperKitFolderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    /// Where WhisperKit's Hub snapshot puts variants under `downloadBase`.
    private var repo: URL { base.appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true) }

    /// Lays out bundles the way a finished download does. Pass `withoutWeights`
    /// to leave a bundle the way an interrupted one does: HubApi moves each
    /// file into place only once it's complete, so the small files land and
    /// the big `weight.bin` doesn't.
    @discardableResult
    private func makeVariantFolder(_ name: String, bundles: [String] = ModelStorage.requiredWhisperKitBundles,
                                   ext: String = "mlmodelc", withoutWeights: Set<String> = []) throws -> URL {
        let folder = repo.appendingPathComponent(name, isDirectory: true)
        let files = ext == "mlmodelc"
            ? ["coremldata.bin", "metadata.json", "weights/weight.bin"]
            : ["Manifest.json", "Data/com.apple.CoreML/model.mlmodel", "Data/com.apple.CoreML/weights/weight.bin"]
        for bundle in bundles {
            let root = folder.appendingPathComponent("\(bundle).\(ext)", isDirectory: true)
            for file in files where !(withoutWeights.contains(bundle) && file.hasSuffix("weight.bin")) {
                let url = root.appendingPathComponent(file)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: url.path, contents: Data([0]))
            }
        }
        return folder
    }

    func testNothingDownloadedMeansNoLocalFolder() {
        XCTAssertNil(ModelStorage.localWhisperKitFolder(variant: variant, downloadBase: base))
    }

    /// The real on-disk layout from the user's machine.
    func testFindsTheDownloadedVariant() throws {
        let folder = try makeVariantFolder("openai_whisper-\(variant)")
        XCTAssertEqual(ModelStorage.localWhisperKitFolder(variant: variant, downloadBase: base)?.standardizedFileURL,
                       folder.standardizedFileURL)
    }

    func testMLPackageBundlesCount() throws {
        let folder = try makeVariantFolder("openai_whisper-\(variant)", ext: "mlpackage")
        XCTAssertEqual(ModelStorage.localWhisperKitFolder(variant: variant, downloadBase: base)?.standardizedFileURL,
                       folder.standardizedFileURL)
    }

    /// A folder that can't load must not be offered: the caller should go
    /// straight to downloading rather than burn a prewarm pass failing.
    func testMissingBundleIsNotOffered() throws {
        try makeVariantFolder("openai_whisper-\(variant)", bundles: ["MelSpectrogram", "TextDecoder"])
        XCTAssertNil(ModelStorage.localWhisperKitFolder(variant: variant, downloadBase: base))
    }

    /// What an interrupted first download really leaves: every bundle folder
    /// exists with its small files, but the 1.2 GB encoder weights never
    /// landed.
    func testInterruptedDownloadIsNotOffered() throws {
        try makeVariantFolder("openai_whisper-\(variant)", withoutWeights: ["AudioEncoder"])
        XCTAssertNil(ModelStorage.localWhisperKitFolder(variant: variant, downloadBase: base))
    }

    /// Mirrors WhisperKit's `*<variant>/*` glob: a longer name that merely
    /// contains the variant is a different model.
    func testDoesNotMatchADifferentVariant() throws {
        try makeVariantFolder("openai_whisper-\(variant)_632MB")
        XCTAssertNil(ModelStorage.localWhisperKitFolder(variant: variant, downloadBase: base))
    }

    /// Same tie-break WhisperKit uses when the glob is ambiguous.
    func testAmbiguousMatchPrefersOpenAIFolder() throws {
        try makeVariantFolder("distil-whisper_\(variant)")
        let openai = try makeVariantFolder("openai_whisper-\(variant)")
        XCTAssertEqual(ModelStorage.localWhisperKitFolder(variant: variant, downloadBase: base)?.standardizedFileURL,
                       openai.standardizedFileURL)
    }

    func testStillAmbiguousMeansNoLocalFolder() throws {
        try makeVariantFolder("a_\(variant)")
        try makeVariantFolder("b_\(variant)")
        XCTAssertNil(ModelStorage.localWhisperKitFolder(variant: variant, downloadBase: base))
    }

    /// A plain file named like a bundle is not a model.
    func testFilesNamedLikeBundlesDoNotCount() throws {
        let folder = repo.appendingPathComponent("openai_whisper-\(variant)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for bundle in ModelStorage.requiredWhisperKitBundles {
            FileManager.default.createFile(atPath: folder.appendingPathComponent("\(bundle).mlmodelc").path,
                                           contents: Data())
        }
        XCTAssertNil(ModelStorage.localWhisperKitFolder(variant: variant, downloadBase: base))
    }
}
