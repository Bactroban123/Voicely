import Foundation
import VoicelyCore

enum MeetingSummaryError: Error, CustomStringConvertible {
    case noAPIKey
    case badResponse(Int)
    case malformed
    case emptyTranscript

    var description: String {
        switch self {
        case .noAPIKey: return "no OpenRouter key — add one in Settings to get meeting notes"
        case .badResponse(let code): return "the model returned HTTP \(code)"
        case .malformed: return "the model's response couldn't be read"
        case .emptyTranscript: return "there's no transcript to summarize"
        }
    }
}

/// Turns a meeting transcript into structured notes via OpenRouter.
///
/// Privacy: the TRANSCRIPT TEXT leaves the device here; the audio never does.
/// That's the same bargain dictation's cleanup already makes, with the same
/// zero-retention headers — but it's a bigger one for a meeting, because the
/// text includes other people. The UI has to say so plainly, and this stays
/// opt-in behind the same key.
@available(macOS 14.2, *)
actor MeetingSummaryService {
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let modelID: String
    private let zeroRetention: Bool

    init(modelID: String, zeroRetention: Bool) {
        self.modelID = modelID
        self.zeroRetention = zeroRetention
    }

    /// Summarize a rendered dialogue transcript.
    func summarize(_ transcript: String) async throws -> MeetingSummary {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeetingSummaryError.emptyTranscript
        }

        switch MeetingSummaryPlan.plan(for: transcript) {
        case .single(let text):
            return try await structuredNotes(system: MeetingSummaryPrompt.system(), content: text)

        case .mapReduce(let slices):
            // Long meeting: condense each slice, then fold. The map step keeps
            // specifics (names, numbers, commitments) rather than summarizing,
            // because a summary of a summary loses exactly what makes notes
            // useful.
            VoicelyLog.meeting.info("long transcript — condensing \(slices.count) slices before summarizing")
            var notes: [String] = []
            for (index, slice) in slices.enumerated() {
                let condensed = try await send(system: MeetingSummaryPrompt.mapSystem(),
                                               content: slice,
                                               maxTokens: MeetingSummaryRequest.mapMaxTokens,
                                               requireJSON: false)
                notes.append("--- part \(index + 1) of \(slices.count) ---\n\(condensed)")
            }
            return try await structuredNotes(system: MeetingSummaryPrompt.reduceSystem(),
                                             content: notes.joined(separator: "\n\n"))
        }
    }

    // MARK: - Internals

    /// One structured call, with a single retry on an unparseable response.
    ///
    /// JSON mode is requested but not trusted: providers honour it unevenly.
    /// A second failure degrades visibly rather than returning empty notes that
    /// would read as "this meeting had no content".
    private func structuredNotes(system: String, content: String) async throws -> MeetingSummary {
        let first = try await send(system: system, content: content,
                                   maxTokens: MeetingSummaryRequest.defaultMaxTokens, requireJSON: true)
        switch MeetingSummaryParsing.parse(first) {
        case .parsed(let summary):
            return summary
        case .degraded(let summary):
            return summary
        case .retryable:
            VoicelyLog.meeting.warning("summary response wasn't valid JSON — retrying once")
            let retried = try await send(system: system,
                                         content: content + "\n\n" + MeetingSummaryPrompt.retryInstruction,
                                         maxTokens: MeetingSummaryRequest.defaultMaxTokens,
                                         requireJSON: true)
            switch MeetingSummaryParsing.parse(retried, isFinalAttempt: true) {
            case .parsed(let summary), .degraded(let summary):
                if summary.parseDegraded {
                    VoicelyLog.meeting.warning("summary still unparseable — keeping the raw text")
                }
                return summary
            case .retryable:
                throw MeetingSummaryError.malformed   // unreachable: isFinalAttempt degrades
            }
        }
    }

    private func send(system: String, content: String, maxTokens: Int, requireJSON: Bool) async throws -> String {
        guard let apiKey = KeychainStore.openRouterKey(), !apiKey.isEmpty else {
            throw MeetingSummaryError.noAPIKey
        }
        let body = MeetingSummaryRequest(modelID: modelID,
                                         systemPrompt: system,
                                         content: content,
                                         maxTokens: maxTokens,
                                         requireJSON: requireJSON,
                                         zeroRetention: zeroRetention)

        var request = URLRequest(url: endpoint)
        // Far longer than dictation's 12s: this is a big prompt and a long
        // completion, and nobody is waiting on a cursor for it — the meeting is
        // already over. Failing early here would throw away the whole meeting's
        // notes to save a few seconds.
        request.timeoutInterval = 120
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://voicely.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Voicely", forHTTPHeaderField: "X-Title")
        request.httpBody = try body.jsonData()

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MeetingSummaryError.malformed }
        guard (200..<300).contains(http.statusCode) else {
            throw MeetingSummaryError.badResponse(http.statusCode)
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let choice = choices.first,
              let message = choice["message"] as? [String: Any],
              let text = message["content"] as? String
        else { throw MeetingSummaryError.malformed }

        // Truncation is a 200 with finish_reason "length" — the same silent
        // failure that pasted half-sentences in dictation. Notes cut off
        // mid-item would look complete; say so instead.
        if let finish = choice["finish_reason"] as? String, finish == "length" {
            VoicelyLog.meeting.warning("summary hit the token cap and was cut short")
        }
        return text
    }
}
