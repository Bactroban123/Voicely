import Foundation
import VoicelyCore
import WhisperKit

/// The one way Voicely builds a loaded WhisperKit: from disk when the weights
/// are already there, downloading only when they aren't.
enum WhisperKitLoader {
    /// Without a `modelFolder`, WhisperKit lists the Hugging Face repo over the
    /// network before it looks at disk, so every offline load failed ("The
    /// Internet connection appears to be offline") while all 1.5 GB of weights
    /// sat in `directory`. A local copy that won't load falls through to the
    /// download, which fills in any missing files. It won't replace a present
    /// but corrupt file (HubApi skips files whose metadata matches), so that
    /// case keeps failing, as it always did.
    ///
    /// - Parameter directory: the download base. Must be somewhere macOS won't
    ///   sync, evict or purge — see `ModelStorage`.
    static func load(model: String, directory: URL) async throws -> WhisperKit {
        if let local = ModelStorage.localWhisperKitFolder(variant: model, downloadBase: directory) {
            do {
                return try await WhisperKit(
                    model: model,
                    downloadBase: directory, // where the tokenizer is found
                    modelFolder: local.path,
                    verbose: false,
                    prewarm: true,
                    load: true,
                    download: false)
            } catch {
                VoicelyLog.model.warning("local \(model) didn't load, fetching it again — \(error)")
            }
        } else {
            VoicelyLog.model.info("no complete local copy of \(model) — downloading")
        }
        return try await WhisperKit(
            model: model,
            downloadBase: directory, // also where the tokenizer lands
            verbose: false,
            prewarm: true,
            load: true,
            download: true)
    }
}
