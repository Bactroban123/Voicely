import Foundation

/// Cleans Whisper's raw segment text.
///
/// Whisper's per-segment text carries its control tokens inline:
///
///     <|startoftranscript|><|he|><|transcribe|><|0.00|> שלום, אני שמח…<|2.42|><|endoftext|>
///
/// The library strips these when building its own top-level `text`, but that
/// property gives no timings — and meetings need timings to interleave two
/// speakers. So reading `segments` is right, and stripping is then ours to do.
///
/// Pure and fixture-tested because getting it wrong is invisible in code review
/// and in any test built from hand-made segments: it compiles, it merges, it
/// renders — and every line of the transcript is prefixed with
/// `<|startoftranscript|>`. Only real audio shows it, which is how it was found.
public enum WhisperText {
    /// Removes `<|…|>` control tokens and tidies the whitespace they leave.
    public static func strippingSpecialTokens(_ text: String) -> String {
        let stripped = text.replacingOccurrences(
            of: "<\\|[^|]*\\|>",
            with: "",
            options: .regularExpression)
        return stripped
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
