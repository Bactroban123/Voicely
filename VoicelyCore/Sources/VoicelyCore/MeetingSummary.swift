import Foundation

/// What a meeting produces besides its transcript.
///
/// Structured rather than prose so the UI can show tasks as tasks and the
/// Markdown export can render real checkboxes — and so a bad model response is
/// a *parse* failure we can detect, rather than plausible text we'd paste
/// unnoticed.
public struct MeetingSummary: Codable, Equatable {
    public struct ActionItem: Codable, Equatable {
        public let title: String
        /// Only set when the transcript names someone. Never inferred.
        public let owner: String?
        /// Only set when a date/deadline is actually spoken. Never inferred.
        public let due: String?

        public init(title: String, owner: String? = nil, due: String? = nil) {
            self.title = title
            self.owner = owner
            self.due = due
        }

        enum CodingKeys: String, CodingKey { case title, owner, due }
    }

    public let summary: String
    public let keyPoints: [String]
    public let decisions: [String]
    public let actionItems: [ActionItem]
    public let followups: [String]

    /// True when the model's response couldn't be parsed as the agreed schema
    /// and `summary` holds its raw text instead. The UI says so rather than
    /// presenting a half-empty result as complete.
    public var parseDegraded: Bool

    public init(summary: String,
                keyPoints: [String] = [],
                decisions: [String] = [],
                actionItems: [ActionItem] = [],
                followups: [String] = [],
                parseDegraded: Bool = false) {
        self.summary = summary
        self.keyPoints = keyPoints
        self.decisions = decisions
        self.actionItems = actionItems
        self.followups = followups
        self.parseDegraded = parseDegraded
    }

    enum CodingKeys: String, CodingKey {
        case summary
        case keyPoints = "key_points"
        case decisions
        case actionItems = "action_items"
        case followups
        case parseDegraded   // never sent by the model; local only
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        keyPoints = try container.decodeIfPresent([String].self, forKey: .keyPoints) ?? []
        decisions = try container.decodeIfPresent([String].self, forKey: .decisions) ?? []
        actionItems = try container.decodeIfPresent([ActionItem].self, forKey: .actionItems) ?? []
        followups = try container.decodeIfPresent([String].self, forKey: .followups) ?? []
        parseDegraded = false
    }

    /// True when the model returned nothing worth showing.
    public var isEmpty: Bool {
        summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && keyPoints.isEmpty && decisions.isEmpty && actionItems.isEmpty && followups.isEmpty
    }
}
