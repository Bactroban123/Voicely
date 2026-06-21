import Foundation

/// Abstraction over the on-device speech-to-text engines so they can be swapped
/// (Parakeet default; Whisper / Apple Speech later) behind one interface.
protocol TranscriptionEngine: AnyObject {
    /// Download + load the model and keep it resident (warm). Safe to call repeatedly.
    func prepare() async throws
    /// Transcribe 16 kHz mono Float32 samples to text.
    func transcribe(_ samples: [Float]) async throws -> String
}

enum TranscriptionError: Error {
    case notReady
    case emptyAudio
}
