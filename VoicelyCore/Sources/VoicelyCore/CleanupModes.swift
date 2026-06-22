import Foundation

/// A cleanup preset: how aggressively the LLM reworks the transcript.
public struct CleanupMode: Equatable, Identifiable {
    public let id: String
    public let name: String
    public let detail: String
    public init(id: String, name: String, detail: String) {
        self.id = id
        self.name = name
        self.detail = detail
    }
}

/// The selectable cleanup presets and their system prompts. "clean" reuses
/// CleanupPrompt (conservative). "polish" tightens for clarity. "prompt" reshapes
/// dictation into an AI prompt. All apply the custom vocabulary and output text only.
public enum CleanupModes {
    public static let clean = CleanupMode(
        id: "clean", name: "Clean",
        detail: "Punctuation, fillers, your vocabulary — keeps your wording.")
    public static let polish = CleanupMode(
        id: "polish", name: "Polish",
        detail: "Also tightens for clarity and conciseness.")
    public static let prompt = CleanupMode(
        id: "prompt", name: "Prompt",
        detail: "Reshapes your dictation into a clean AI prompt.")
    public static let translateEN = CleanupMode(
        id: "translate-en", name: "Translate → English",
        detail: "Speak any language; insert fluent English.")
    public static let translateHE = CleanupMode(
        id: "translate-he", name: "Translate → Hebrew",
        detail: "Speak any language; insert fluent Hebrew (עברית).")
    public static let translateTH = CleanupMode(
        id: "translate-th", name: "Translate → Thai",
        detail: "Speak any language; insert fluent Thai (ภาษาไทย).")
    public static let translateTHEN = CleanupMode(
        id: "translate-th-en", name: "Thai → English",
        detail: "Speak Thai; insert fluent English.")

    public static let all: [CleanupMode] = [
        clean, polish, prompt, translateEN, translateHE, translateTH, translateTHEN,
    ]
    public static let defaultID = "clean"

    public static func mode(id: String) -> CleanupMode? {
        all.first { $0.id == id }
    }

    public static func system(modeID: String, vocabulary: [VocabularyEntry]) -> String {
        switch modeID {
        case "polish": return polishPrompt(vocabulary)
        case "prompt": return promptPrompt(vocabulary)
        case "translate-en": return translatePrompt(target: "English", vocabulary: vocabulary)
        case "translate-he": return translatePrompt(target: "Hebrew (עברית)", vocabulary: vocabulary)
        case "translate-th": return translatePrompt(target: "Thai (ภาษาไทย)", vocabulary: vocabulary)
        case "translate-th-en":
            return translatePrompt(source: "Thai", target: "English", vocabulary: vocabulary)
        default: return CleanupPrompt.system(vocabulary: vocabulary) // clean
        }
    }

    private static func vocabularyBlock(_ vocabulary: [VocabularyEntry]) -> String {
        """
        CUSTOM VOCABULARY (correct misheard variants TO these exact spellings):
        \(CleanupPrompt.renderVocabulary(vocabulary))
        """
    }

    private static func polishPrompt(_ vocabulary: [VocabularyEntry]) -> String {
        """
        You are a dictation polishing engine. You receive a raw speech-to-text transcript \
        and return a clearer, more concise version of the SAME message. You are an editor.

        RULES — follow exactly:
        1. Fix capitalization, punctuation, and spacing. Add sentence/paragraph breaks where natural.
        2. Remove filler words, false starts, and repetition ("um", "uh", filler "like", "you know").
        3. Tighten the writing: cut redundancy, merge rambling sentences, and improve flow and clarity.
        4. Preserve the speaker's meaning, intent, facts, tone, and language. Do NOT add new ideas, \
        opinions, or information the speaker did not express. Keep it natural, not stiff or formal.
        5. Apply the custom vocabulary corrections below.
        6. Output ONLY the polished text. No preamble, quotes, markdown fences, or commentary.

        \(vocabularyBlock(vocabulary))
        """
    }

    private static func translatePrompt(source: String? = nil,
                                        target: String,
                                        vocabulary: [VocabularyEntry]) -> String {
        let intro = source.map {
            "You are a translation engine. The transcript is spoken \($0). "
            + "Translate it into natural, fluent \(target)."
        } ?? "You are a translation engine. Translate the transcript into natural, fluent \(target)."

        // Thai source has no inter-word spaces and uses politeness particles; nudge the model.
        let sourceNote = source == "Thai"
            ? "\n6. The source is Thai: drop politeness particles (ครับ/ค่ะ/นะ) unless they carry meaning, "
              + "and render Thai names and places with their common English spelling."
            : ""

        return """
        \(intro)

        RULES — follow exactly:
        1. Produce idiomatic \(target), not a word-for-word translation. Convey the speaker's meaning and tone.
        2. Remove speech fillers and false starts. Use correct punctuation and casing for \(target).
        3. Keep proper nouns, people's names, code, URLs, and email addresses unchanged — do not translate \
        them. Apply the custom-vocabulary spellings below to any that appear.
        4. If the transcript is already in \(target), simply clean it up — do not re-translate or paraphrase.
        5. Output ONLY the \(target) text. No preamble, quotes, transliteration, notes, or the original.\(sourceNote)

        \(vocabularyBlock(vocabulary))
        """
    }

    private static func promptPrompt(_ vocabulary: [VocabularyEntry]) -> String {
        """
        You are a prompt-engineering assistant. The transcript is a person thinking out loud about \
        what they want an AI assistant to do. Rewrite it into a clear, well-structured prompt.

        RULES — follow exactly:
        1. Capture ALL of the speaker's intent, constraints, and context. Do NOT add requirements, \
        scope, or assumptions they did not state.
        2. Lead with a direct instruction. Add context or constraints after it, using short bullet \
        points only if it genuinely helps.
        3. Be concise and unambiguous. Remove fillers and rambling.
        4. Apply the custom vocabulary corrections below. Preserve the speaker's language.
        5. Output ONLY the finished prompt text. No preamble, quotes, markdown fences, or commentary.

        \(vocabularyBlock(vocabulary))
        """
    }
}
