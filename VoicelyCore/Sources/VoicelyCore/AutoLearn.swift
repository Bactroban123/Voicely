import Foundation

/// A term Voicely learned from your dictation history (a proper noun, product
/// name, or acronym you say often). Fed into the cleanup vocabulary so the model
/// spells it consistently.
public struct LearnedTerm: Equatable {
    public let term: String
    public let count: Int   // number of distinct dictations it appeared in
    public init(term: String, count: Int) {
        self.term = term
        self.count = count
    }
}

/// A phrase you dictate repeatedly that could become a snippet. Surfaced as a
/// suggestion (never auto-applied — the trigger is yours to set).
public struct SnippetSuggestion: Equatable {
    public let phrase: String            // the repeated phrase (the expansion)
    public let suggestedTrigger: String  // an editable starting point
    public let count: Int
    public init(phrase: String, suggestedTrigger: String, count: Int) {
        self.phrase = phrase
        self.suggestedTrigger = suggestedTrigger
        self.count = count
    }
}

/// Pure, deterministic learning over transcript history. No I/O, no persistence —
/// the app feeds it `HistoryStore.entries` and stores what it accepts.
///
/// Two signals:
/// - **Vocabulary**: "notable" tokens (mid-sentence capitals, PascalCase,
///   acronyms, alphanumerics) that recur across ≥ `minDistinct` dictations.
/// - **Snippets**: multi-word phrases that recur across ≥ `minDistinct` dictations.
///
/// Tokenization is space-delimited, so this learns from Latin-script dictation.
/// Space-less scripts (Thai, Chinese, Japanese) collapse to one token and yield
/// no suggestions — their translation/cleanup still works, they just aren't mined
/// for vocabulary yet.
public enum AutoLearn {

    // Common function words, days/months, and high-frequency capitalizable
    // interjections — never worth learning as vocabulary.
    static let stopwords: Set<String> = [
        "the","a","an","and","or","but","if","then","so","because","as","of","at","by",
        "for","with","about","against","between","into","through","during","to","from",
        "in","on","out","over","under","again","this","that","these","those","is","are",
        "was","were","be","been","being","have","has","had","do","does","did","will",
        "would","should","could","can","may","might","must","i","you","he","she","it",
        "we","they","me","him","her","us","them","my","your","his","its","our","their",
        "what","which","who","whom","when","where","why","how","all","any","both","each",
        "few","more","most","some","such","no","nor","not","only","own","same","than",
        "too","very","just","now","also","here","there","yeah","okay","ok","like","get",
        "got","really","actually","basically","monday","tuesday","wednesday","thursday",
        "friday","saturday","sunday","january","february","march","april","june","july",
        "august","september","october","november","december",
        // interjections / fillers that capitalize after a sentence break
        "hello","hi","hey","thanks","thank","please","sorry","yes","well","oh","hmm",
        "um","uh","right","sure","maybe",
    ]

    // MARK: - Vocabulary

    public static func vocabularyTerms(from transcripts: [String],
                                       existing: [VocabularyEntry] = [],
                                       dismissed: Set<String> = [],
                                       minDistinct: Int = 2,
                                       limit: Int = 12) -> [LearnedTerm] {
        // Words already covered by manual vocabulary (terms + variants), lowercased.
        var known = dismissed
        for e in existing {
            known.insert(e.term.lowercased())
            for v in e.variants { known.insert(v.lowercased()) }
        }

        let docs = transcripts.map(tokenizedSentences)

        // Pass 1 — discover which keys are "notable" anywhere, and remember casing.
        var notableUnigram: [String: String] = [:]   // key → representative casing
        var notableBigram:  [String: String] = [:]
        for doc in docs {
            for sent in doc {
                for (i, tok) in sent.enumerated() {
                    if isNotable(tok.orig, wordIndex: i), notableUnigram[tok.lower] == nil {
                        notableUnigram[tok.lower] = tok.orig
                    }
                    if i + 1 < sent.count {
                        let next = sent[i + 1]
                        if startsCapitalized(tok.orig), startsCapitalized(next.orig),
                           tok.orig.count >= 2, next.orig.count >= 2 {
                            let key = "\(tok.lower) \(next.lower)"
                            if notableBigram[key] == nil { notableBigram[key] = "\(tok.orig) \(next.orig)" }
                        }
                    }
                }
            }
        }

        // Pass 2 — count distinct transcripts that contain each notable key.
        // Unigrams: present anywhere. Bigrams: adjacent within a single sentence.
        var uniCount: [String: Int] = [:]
        var biCount:  [String: Int] = [:]
        for doc in docs {
            var words = Set<String>()
            var pairs = Set<String>()
            for sent in doc {
                for tok in sent { words.insert(tok.lower) }
                if sent.count >= 2 {
                    for i in 0..<(sent.count - 1) {
                        pairs.insert("\(sent[i].lower) \(sent[i + 1].lower)")
                    }
                }
            }
            for key in notableUnigram.keys where words.contains(key) { uniCount[key, default: 0] += 1 }
            for key in notableBigram.keys where pairs.contains(key) { biCount[key, default: 0] += 1 }
        }

        // Assemble candidates (bigrams first so a strong name suppresses its parts).
        struct Cand { let key: String; let term: String; let count: Int; let isBigram: Bool }
        var cands: [Cand] = []
        for (key, term) in notableBigram {
            let c = biCount[key] ?? 0
            if c >= minDistinct, !known.contains(key) {
                cands.append(Cand(key: key, term: term, count: c, isBigram: true))
            }
        }
        for (key, term) in notableUnigram {
            let c = uniCount[key] ?? 0
            if c >= minDistinct, !known.contains(key) {
                cands.append(Cand(key: key, term: term, count: c, isBigram: false))
            }
        }

        cands.sort {
            if $0.count != $1.count { return $0.count > $1.count }
            if $0.isBigram != $1.isBigram { return $0.isBigram && !$1.isBigram }
            return $0.key < $1.key
        }

        var covered = Set<String>()   // unigram keys already inside a chosen bigram
        var out: [LearnedTerm] = []
        for c in cands {
            if c.isBigram {
                for w in c.key.split(separator: " ") { covered.insert(String(w)) }
                out.append(LearnedTerm(term: c.term, count: c.count))
            } else if !covered.contains(c.key) {
                out.append(LearnedTerm(term: c.term, count: c.count))
            }
            if out.count >= limit { break }
        }
        return out
    }

    // MARK: - Snippets

    public static func snippetSuggestions(from transcripts: [String],
                                          existing: [Snippet] = [],
                                          dismissed: Set<String> = [],
                                          minDistinct: Int = 2,
                                          limit: Int = 8) -> [SnippetSuggestion] {
        // Normalize stored expansions/triggers through the same tokenizer so a
        // trailing period or double space can't defeat the exclusion.
        let existingExpansions = Set(existing.map { normalizedKey($0.expansion) })
        let existingTriggers = Set(existing.map { normalizedKey($0.trigger) })

        // key (lowercased n-gram) → (display phrase first seen, distinct transcript count)
        var display: [String: String] = [:]
        var count: [String: Int] = [:]

        for text in transcripts {
            var seenThisDoc = Set<String>()   // distinct-transcript scope
            for sent in tokenizedSentences(text) {
                guard sent.count >= 3 else { continue }
                let maxN = min(8, sent.count)
                for n in 3...maxN {
                    for i in 0...(sent.count - n) {
                        let slice = sent[i..<(i + n)]
                        let key = slice.map(\.lower).joined(separator: " ")
                        if seenThisDoc.contains(key) { continue }
                        seenThisDoc.insert(key)
                        count[key, default: 0] += 1
                        if display[key] == nil {
                            display[key] = slice.map(\.orig).joined(separator: " ")
                        }
                    }
                }
            }
        }

        struct Cand { let key: String; let phrase: String; let count: Int; let words: Int }
        var cands: [Cand] = []
        for (key, c) in count where c >= minDistinct {
            guard let phrase = display[key] else { continue }
            if phrase.count < 12 { continue }
            if dismissed.contains(key) { continue }
            if existingExpansions.contains(key) || existingTriggers.contains(key) { continue }
            let words = key.split(separator: " ")
            let nonStop = words.filter { !stopwords.contains(String($0)) }
            if nonStop.count < 2 { continue }   // skip pure-filler phrases
            cands.append(Cand(key: key, phrase: phrase, count: c, words: words.count))
        }

        // Prefer longer phrases; drop a shorter phrase contained in a chosen longer one.
        cands.sort {
            if $0.count != $1.count { return $0.count > $1.count }
            if $0.words != $1.words { return $0.words > $1.words }
            return $0.key < $1.key
        }

        var chosenKeys: [String] = []
        var out: [SnippetSuggestion] = []
        for c in cands {
            let padded = " \(c.key) "
            if chosenKeys.contains(where: { " \($0) ".contains(padded) }) { continue }
            chosenKeys.append(c.key)
            out.append(SnippetSuggestion(phrase: c.phrase,
                                         suggestedTrigger: defaultTrigger(c.phrase),
                                         count: c.count))
            if out.count >= limit { break }
        }
        return out
    }

    // MARK: - Token helpers

    /// A transcript split into sentences, each a list of (original, lowercased)
    /// tokens. Sentences break on `.!?` and newlines; tokens on whitespace.
    private static func tokenizedSentences(_ text: String) -> [[(orig: String, lower: String)]] {
        sentences(text).map { sentence in
            sentence.split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map { raw -> (orig: String, lower: String) in
                    let t = trimToken(String(raw))
                    return (t, t.lowercased())
                }
                .filter { !$0.orig.isEmpty }
        }
    }

    private static func sentences(_ text: String) -> [String] {
        text.split(whereSeparator: { ".!?\n\r".contains($0) }).map(String.init)
    }

    /// Trim leading/trailing non-alphanumerics; keep internal characters.
    static func trimToken(_ raw: String) -> String {
        var chars = Array(raw)
        while let f = chars.first, !(f.isLetter || f.isNumber) { chars.removeFirst() }
        while let l = chars.last,  !(l.isLetter || l.isNumber) { chars.removeLast() }
        return String(chars)
    }

    /// Lowercased, whitespace-collapsed token form of a string (for snippet dedup).
    private static func normalizedKey(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
            .map { trimToken(String($0)).lowercased() }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func startsCapitalized(_ tok: String) -> Bool {
        guard let f = tok.first else { return false }
        return f.isUppercase
    }

    private static func isNotable(_ tok: String, wordIndex: Int) -> Bool {
        guard tok.count >= 3 else { return false }
        let lower = tok.lowercased()
        if stopwords.contains(lower) { return false }
        if tok.allSatisfy({ $0.isNumber }) { return false }

        let chars = Array(tok)
        let hasInternalUppercase = chars.enumerated().contains { $0.offset > 0 && $0.element.isUppercase }
        let hasLetter = chars.contains { $0.isLetter }
        let hasDigit  = chars.contains { $0.isNumber }
        let capitalizedMidSentence = (chars.first?.isUppercase ?? false) && wordIndex > 0

        return hasInternalUppercase || capitalizedMidSentence || (hasLetter && hasDigit)
    }

    private static func defaultTrigger(_ phrase: String) -> String {
        let words = phrase.split(separator: " ").prefix(2)
        return words.joined(separator: " ").lowercased()
    }
}
