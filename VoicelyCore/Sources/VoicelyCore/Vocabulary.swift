import Foundation

/// A custom-vocabulary entry: the correct spelling of a term plus, optionally,
/// the ways the recognizer tends to mishear it. Variants are the single biggest
/// accuracy lever for the cleanup step (the model corrects toward `term`).
public struct VocabularyEntry: Codable, Equatable {
    public let term: String
    public let variants: [String]
    public init(term: String, variants: [String] = []) {
        self.term = term
        self.variants = variants
    }
}
