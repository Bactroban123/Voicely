import Foundation

/// A speech engine's confidence signals for one segment.
public struct SegmentConfidence: Equatable {
    /// Probability the audio contained no speech at all (0…1).
    public let noSpeechProbability: Float
    /// Mean log-probability of the emitted tokens. Less negative is better.
    public let averageLogProbability: Float

    public init(noSpeechProbability: Float, averageLogProbability: Float) {
        self.noSpeechProbability = noSpeechProbability
        self.averageLogProbability = averageLogProbability
    }
}

/// Rejects text a speech engine invented rather than heard.
///
/// Whisper hallucinates on silence — fed a quiet stretch it will confidently
/// emit filler from its training data: "Thank you.", "Thanks for watching!",
/// "Please subscribe." It reports its own doubt (`noSpeechProb` high,
/// `avgLogprob` very negative) but still returns the text, so the caller has to
/// throw it away.
///
/// This matters far more for meetings than for dictation. A dictation is one
/// person talking on purpose; a meeting has two tracks, and the *other* track is
/// silent whenever the other person isn't speaking. Without this, every quiet
/// gap becomes invented dialogue — and the summarizer then treats it as
/// something a participant actually said. Seen on the very first real meeting:
/// a silent system track produced three "Thank you." lines.
public enum SpeechConfidence {
    /// Above this, the engine effectively says "there was no speech here".
    /// Whisper's own default for rejecting a decode is 0.6; this is deliberately
    /// stricter, because a meeting's silent track is the common case and the
    /// cost of a false accept (invented dialogue) is worse than a false reject
    /// (a mumble dropped from a transcript that still has the other track).
    public static let noSpeechCeiling: Float = 0.5
    /// Below this, the tokens were low-confidence guesses.
    public static let logProbFloor: Float = -1.0

    /// Phrases Whisper reliably invents from silence. Checked only for SHORT
    /// segments, so a real "thank you" mid-sentence survives — the giveaway is a
    /// standalone stock phrase, not the words themselves.
    private static let hallucinationPhrases: Set<String> = [
        "thank you", "thanks for watching", "thank you for watching",
        "please subscribe", "subscribe to my channel", "you", "bye", "bye.",
        "thanks for watching!", "thank you.", "thank you!",
    ]

    /// Whether a segment is real speech worth keeping.
    public static func isSpeech(text: String, confidence: SegmentConfidence?) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }

        if let confidence {
            if confidence.noSpeechProbability > noSpeechCeiling { return false }
            if confidence.averageLogProbability < logProbFloor { return false }
        }

        // Belt-and-braces for the classic stock phrases: Whisper sometimes
        // reports *high* confidence in them, so the numbers alone don't catch
        // every case. Length-gated so real speech containing "thank you" is
        // untouched.
        let normalized = clean.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?, "))
        if clean.count <= 25, hallucinationPhrases.contains(normalized) { return false }

        return true
    }
}
