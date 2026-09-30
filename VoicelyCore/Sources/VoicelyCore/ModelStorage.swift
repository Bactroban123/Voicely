import Foundation

/// Where downloaded model weights are allowed to live.
///
/// On-device weights are big (Whisper large-v3-turbo is ~1.5 GB on disk) and
/// re-downloadable, which makes them exactly the kind of file macOS likes to
/// take away from you: iCloud Drive evicts them to the cloud when the disk
/// fills, and `~/Library/Caches` is purgeable. Both are silent, and both break
/// the app in the same way — an evicted file still exists, still reports its
/// full size in `ls`, and blocks in `read(2)` until the file provider hands the
/// bytes back. If it never does, the read never returns.
///
/// That is not hypothetical: WhisperKit downloads to `~/Documents/huggingface`
/// by default, `~/Documents` is synced by iCloud Drive, and once the weights
/// were evicted every dictation hung in "transcribing" forever with no error,
/// no timeout and no log line.
public enum ModelStorage {
    /// The one safe home for weights: Application Support is neither synced
    /// nor purgeable, so what we downloaded stays downloaded.
    public static func modelsDirectory(applicationSupport: URL) -> URL {
        applicationSupport
            .appendingPathComponent("Voicely", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    /// Directories the system may sync, evict, or purge behind our back.
    /// Matched on path components so it holds for any user's home directory.
    private static let unsafeComponents: [[String]] = [
        ["Documents"],                              // iCloud Drive: Desktop & Documents
        ["Desktop"],                                // same
        ["Library", "Mobile Documents"],            // iCloud Drive proper
        ["Library", "CloudStorage"],                // iCloud + third-party file providers
        ["Library", "Caches"],                      // purgeable: a silent multi-GB re-download
    ]

    /// False for anywhere weights could be taken away from us. Callers should
    /// treat a false here as a configuration bug, not a runtime condition.
    public static func isSafeForModelWeights(_ directory: URL) -> Bool {
        let components = directory.standardizedFileURL.pathComponents
        return !unsafeComponents.contains { unsafe in
            guard let start = components.firstIndex(of: unsafe[0]) else { return false }
            let slice = components[start...].prefix(unsafe.count)
            return Array(slice) == unsafe
        }
    }
}
