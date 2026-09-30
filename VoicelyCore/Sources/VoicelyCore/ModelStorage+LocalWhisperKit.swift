import Foundation

extension ModelStorage {
    /// The CoreML bundles WhisperKit won't load without: `loadModels` checks
    /// for exactly these, as `.mlmodelc` or `.mlpackage`.
    public static let requiredWhisperKitBundles = ["MelSpectrogram", "AudioEncoder", "TextDecoder"]

    /// Files inside a bundle that only exist once it has finished downloading.
    /// HubApi moves each file into place only when it's complete, so an
    /// interrupted download leaves the small files and not the weights (the
    /// 1.2 GB encoder is the likeliest to be missing).
    private static let finishedBundleFiles = [
        "mlmodelc": ["coremldata.bin", "weights/weight.bin"],
        "mlpackage": ["Manifest.json", "Data/com.apple.CoreML/weights/weight.bin"],
    ]

    /// The already-downloaded folder for `variant` under `downloadBase`, or
    /// nil when it isn't fully there.
    ///
    /// WhisperKit only reads from disk when it's handed a `modelFolder`.
    /// Without one it lists the Hugging Face repo over the network first, even
    /// when every file is local, so without this dictation can't start
    /// offline. The match mirrors WhisperKit's own lookup (a `*<variant>/*`
    /// glob, ties broken toward the `openai` folder) so we load the folder it
    /// would have downloaded into.
    public static func localWhisperKitFolder(variant: String, downloadBase: URL,
                                             fileManager: FileManager = .default) -> URL? {
        let repo = downloadBase.appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
        guard let names = try? fileManager.contentsOfDirectory(atPath: repo.path) else { return nil }

        var candidates = names.filter { $0.hasSuffix(variant) }
        if candidates.count > 1 { candidates = candidates.filter { $0.contains("openai") } }
        guard candidates.count == 1, let name = candidates.first else { return nil }

        let folder = repo.appendingPathComponent(name, isDirectory: true)
        let complete = requiredWhisperKitBundles.allSatisfy { bundle in
            finishedBundleFiles.contains { ext, files in
                let root = folder.appendingPathComponent("\(bundle).\(ext)", isDirectory: true)
                return files.allSatisfy { file in
                    var isDirectory: ObjCBool = false
                    let path = root.appendingPathComponent(file).path
                    return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
                }
            }
        }
        return complete ? folder : nil
    }
}
