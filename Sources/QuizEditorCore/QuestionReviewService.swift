import Foundation

/// The result of an AI review of a single quiz question.
///
/// Each `revised*` field is non-nil only when the model proposes a change to
/// that field, so the UI can offer per-field "apply" actions.
public struct QuestionReview: Equatable, Sendable {
    public var summary: String
    public var suggestions: [String]
    public var revisedPrompt: String?
    public var revisedAnswers: [QuizAnswer]?
    public var revisedMatches: [MatchingPair]?
    public var revisedFeedback: String?

    public init(
        summary: String,
        suggestions: [String] = [],
        revisedPrompt: String? = nil,
        revisedAnswers: [QuizAnswer]? = nil,
        revisedMatches: [MatchingPair]? = nil,
        revisedFeedback: String? = nil
    ) {
        self.summary = summary
        self.suggestions = suggestions
        self.revisedPrompt = revisedPrompt
        self.revisedAnswers = revisedAnswers
        self.revisedMatches = revisedMatches
        self.revisedFeedback = revisedFeedback
    }

    public var hasRevisions: Bool {
        revisedPrompt != nil || revisedAnswers != nil || revisedMatches != nil || revisedFeedback != nil
    }
}

/// Builds the review prompt and parses the model's JSON response.
public struct QuestionReviewService: Sendable {
    public init() {}

    public var systemInstruction: String {
        "You are an expert instructional designer and assessment writer reviewing one quiz question. Apply established item-writing guidelines and return only the requested JSON."
    }

    public func makePrompt(question: QuizQuestion, quizTitle: String) -> String {
        """
        Review this single quiz question from the quiz titled "\(quizTitle)".

        Evaluate it against these item-writing guidelines (look beyond grammar and spelling):
        - The stem poses one clear, complete problem. Avoid double-barreled stems.
        - Prefer positive phrasing. If the stem must be negative (NOT/EXCEPT), it should emphasize that word.
        - Distractors are plausible, based on common misconceptions, and mutually exclusive.
        - Options are parallel in grammar, length, and complexity. The correct answer must not stand out by being longest or most detailed.
        - Avoid "all of the above" and "none of the above".
        - Avoid absolute terms (always, never) and vague qualifiers that cue the answer.
        - Avoid grammatical clues (a/an, singular/plural agreement) that signal the key.
        - Use plain, accessible language. Do not rely on color, position, or images without alt text.
        - Feedback explains why the key is correct and why distractors are plausible but wrong.
        - The cognitive demand matches the apparent intent.

        Question (type: \(question.type.displayName)):
        \(questionMarkedText(question))

        Respond with ONLY a JSON object, no prose and no code fences, using this shape:
        {
          "summary": "one short paragraph assessing the question overall",
          "suggestions": ["specific issue and the concrete fix", "..."],
          "revised": {
            "prompt": "improved stem text",
            "answers": ["rewritten option 1", "rewritten option 2"],
            "matches": [{"term": "rewritten left item", "match": "rewritten right item"}],
            "feedback": "improved feedback text"
          }
        }

        Critical rules for "revised":
        - Suggest ONLY rewordings of existing text. Improve clarity and quality, but keep the same meaning.
        - Do NOT add, remove, or reorder answer options or matching pairs. Return exactly \(question.answers.count) answer option(s) and \(question.matches.count) matching pair(s), in their original order.
        - Do NOT change which options are correct. Correctness is preserved automatically; you only rewrite text.
        - Include ONLY the fields you would actually change; omit unchanged fields and omit "revised" entirely if nothing needs rewording.
        - Use "answers" for choice-based questions and "matches" only for matching questions.
        """
    }

    public func parse(_ raw: String, original: QuizQuestion) -> QuestionReview {
        guard let jsonString = extractJSONObject(from: raw),
              let data = jsonString.data(using: .utf8),
              let dto = try? JSONDecoder().decode(ReviewDTO.self, from: data) else {
            // Fall back to showing the raw model output so nothing is lost.
            return QuestionReview(summary: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return QuestionReview(
            summary: dto.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No summary returned.",
            suggestions: dto.suggestions ?? [],
            revisedPrompt: nonEmpty(dto.revised?.prompt),
            revisedAnswers: alignedAnswers(dto.revised?.answers, original: original.answers),
            revisedMatches: alignedMatches(dto.revised?.matches, original: original.matches),
            revisedFeedback: nonEmpty(dto.revised?.feedback)
        )
    }

    /// Maps the model's rewritten answer text onto the original options by index,
    /// preserving each option's identity, correctness, and the overall count.
    /// Returns nil when nothing actually changed.
    private func alignedAnswers(_ rewrites: [FlexibleText]?, original: [QuizAnswer]) -> [QuizAnswer]? {
        guard let rewrites, !rewrites.isEmpty, !original.isEmpty else { return nil }
        let aligned = original.enumerated().map { index, answer -> QuizAnswer in
            var revised = answer
            if index < rewrites.count, let text = nonEmpty(rewrites[index].value) {
                revised.text = text
            }
            return revised
        }
        return aligned == original ? nil : aligned
    }

    private func alignedMatches(_ rewrites: [ReviewDTO.Match]?, original: [MatchingPair]) -> [MatchingPair]? {
        guard let rewrites, !rewrites.isEmpty, !original.isEmpty else { return nil }
        let aligned = original.enumerated().map { index, pair -> MatchingPair in
            var revised = pair
            if index < rewrites.count {
                if let term = nonEmpty(rewrites[index].term) { revised.prompt = term }
                if let match = nonEmpty(rewrites[index].match) { revised.match = match }
            }
            return revised
        }
        return aligned == original ? nil : aligned
    }

    private func questionMarkedText(_ question: QuizQuestion) -> String {
        var lines = ["Prompt: \(question.prompt)"]
        if question.type == .matching {
            lines.append(contentsOf: question.matches.map { "- \($0.prompt) => \($0.match)" })
        } else {
            lines.append(contentsOf: question.answers.map { "\($0.isCorrect ? "*" : "-") \($0.text)" })
        }
        if !question.feedback.isEmpty {
            lines.append("Feedback: \(question.feedback)")
        }
        return lines.joined(separator: "\n")
    }

    /// Extracts the outermost JSON object, tolerating code fences or surrounding prose.
    private func extractJSONObject(from raw: String) -> String? {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end else {
            return nil
        }
        return String(raw[start...end])
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

/// Decodes a value that may arrive as a bare string ("text") or an object
/// like {"text": "..."} — models vary in how they format the answer list.
private struct FlexibleText: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer().decode(String.self) {
            value = single
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode(String.self, forKey: .text)
    }

    private enum CodingKeys: String, CodingKey { case text }
}

private struct ReviewDTO: Decodable {
    struct Match: Decodable {
        let term: String
        let match: String
    }

    struct Revised: Decodable {
        let prompt: String?
        let answers: [FlexibleText]?
        let matches: [Match]?
        let feedback: String?
    }

    let summary: String?
    let suggestions: [String]?
    let revised: Revised?
}
