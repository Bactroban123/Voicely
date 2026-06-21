import Foundation

/// Builds the system prompt for the OpenRouter cleanup step. The model is told to
/// behave as an editor, not an assistant: fix punctuation/fillers, apply the
/// custom vocabulary, never add or invent content, and return only the text.
/// The raw transcript is sent separately as the user message.
public enum CleanupPrompt {

    /// Renders the custom vocabulary as a bullet list for injection into the prompt.
    public static func renderVocabulary(_ entries: [VocabularyEntry]) -> String {
        guard !entries.isEmpty else { return "(none)" }
        return entries.map { entry in
            if entry.variants.isEmpty {
                return "- \(entry.term)"
            }
            return "- \(entry.term) (heard as: \(entry.variants.joined(separator: ", ")))"
        }.joined(separator: "\n")
    }

    /// The full system prompt, with the vocabulary block injected.
    public static func system(vocabulary: [VocabularyEntry]) -> String {
        """
        You are a dictation cleanup engine. You receive a raw speech-to-text transcript and \
        return a corrected version of the SAME text. You are an editor, not an assistant.

        RULES — follow exactly:
        1. Fix capitalization, punctuation, and obvious spacing. Add sentence/paragraph \
        breaks only where the speaker clearly paused or changed thought.
        2. Remove filler words and false starts: "um", "uh", "er", filler "like", \
        "you know", "I mean", repeated words, and abandoned half-sentences. Keep these \
        words when they carry real meaning.
        3. Apply light formatting only: turn an obvious spoken list into a list; convert \
        spoken commands "new line"/"new paragraph"/"period"/"comma"/"question mark" \
        into the actual formatting/punctuation, and do not print them as words.
        4. Apply the custom vocabulary corrections below. When the transcript contains a \
        clear misrecognition of a listed term (by sound or spelling), replace it with \
        the correct term. Match case sensibly.
        5. DO NOT add, invent, summarize, answer, explain, translate, or expand anything. \
        Never introduce facts, names, or sentences the speaker did not say. Preserve the \
        speaker's wording, meaning, tone, and language. If unsure, leave it unchanged.
        6. If the transcript is already clean, return it unchanged.
        7. Output ONLY the cleaned text. No preamble, quotes, markdown fences, or commentary.

        CUSTOM VOCABULARY (correct misheard variants TO these exact spellings):
        \(renderVocabulary(vocabulary))
        """
    }
}
