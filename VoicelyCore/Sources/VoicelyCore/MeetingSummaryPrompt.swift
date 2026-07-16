import Foundation

/// Prompts for turning a meeting transcript into notes.
///
/// Deliberately NOT built on `CleanupPrompt`. That one's rule 5 reads "DO NOT
/// add, invent, summarize, answer, explain, translate, or expand anything" —
/// the exact opposite contract. Reusing it would be a subtle way to get a
/// summarizer that refuses to summarize.
///
/// The overriding rule here is groundedness. A summary that invents a decision
/// nobody made, or assigns a task to someone who never agreed to it, is worse
/// than no summary: it's confidently wrong about what people committed to, and
/// the user has no easy way to catch it without re-reading the transcript they
/// were trying to avoid.
public enum MeetingSummaryPrompt {
    /// The JSON contract, stated once and reused by every prompt below.
    private static let schema = """
    {
      "summary": "<a short paragraph: what this meeting was about and what came of it>",
      "key_points": ["<point>", ...],
      "decisions": ["<decision actually made>", ...],
      "action_items": [{"title": "<what to do>", "owner": "<name or null>", "due": "<when or null>"}],
      "followups": ["<open question or thing to revisit>", ...]
    }
    """

    private static let groundingRules = """
    1. Ground everything in the transcript. Never invent a decision, task, name, \
    date, or number that isn't there. If the meeting didn't decide anything, \
    return an empty "decisions" list — an empty list is a correct answer.
    2. Speakers are labelled only "Me" (the user) and "Them" (everyone else on \
    the call, possibly several people). Do not invent participant names. Use a \
    name only if it is actually spoken in the transcript.
    3. "owner" is null unless the transcript clearly attributes the task to \
    someone. "due" is null unless a date or deadline is actually said. Never \
    guess either — null is better than plausible and wrong.
    4. Capture what was said, not what would have been sensible to say. Do not \
    add recommendations, next steps, or analysis of your own.
    5. Keep the speakers' own terminology, including product names and jargon.
    6. Write in the transcript's own language. If it is in Hebrew, write the \
    notes in Hebrew.
    7. Output ONLY the JSON object. No preamble, no markdown fences, no commentary.
    """

    /// Single-shot: the whole transcript in one call.
    public static func system() -> String {
        """
        You take a meeting transcript and return structured notes as JSON.

        RULES — follow exactly:
        \(groundingRules)

        Return exactly this shape:
        \(schema)
        """
    }

    /// Map step: condense one slice of a long meeting. Deliberately not a
    /// summary — a summary of a summary loses the specifics (names, numbers,
    /// commitments) that make notes useful, so the map step preserves them and
    /// only the reduce step generalises.
    public static func mapSystem() -> String {
        """
        You are condensing ONE SLICE of a longer meeting transcript. Other slices \
        are handled separately, so do not try to conclude or wrap up.

        RULES:
        1. Ground everything in this slice. Invent nothing.
        2. Preserve specifics verbatim: names, numbers, dates, product terms, and \
        anything anyone committed to. Later steps cannot recover what you drop here.
        3. Speakers are only "Me" and "Them". Don't invent names.
        4. Note anything that reads as a decision or a task, with the exact wording used.
        5. Write compact bullet points in the transcript's own language. No preamble.
        """
    }

    /// Reduce step: fold the slice notes into the final JSON.
    public static func reduceSystem() -> String {
        """
        You are assembling final notes for ONE meeting from ordered notes taken \
        across its slices. The slices are sequential parts of a single conversation.

        RULES — follow exactly:
        \(groundingRules)
        8. Merge duplicates across slices: a topic revisited later is one item, \
        not several. If a later slice supersedes an earlier decision, keep the \
        later one.

        Return exactly this shape:
        \(schema)
        """
    }

    /// The retry sent after an unparseable response. Kept blunt and short:
    /// restating the whole prompt tends to reproduce the same failure.
    public static let retryInstruction = """
    Your previous response was not valid JSON. Return ONLY the JSON object \
    described earlier — no fences, no commentary, nothing else.
    """
}
