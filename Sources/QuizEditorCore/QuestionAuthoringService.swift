import Foundation

/// Builds prompts and parses model output for the AI *authoring* features:
/// generating whole questions from a topic, generating distractors for a stem,
/// and drafting feedback. Parsing is deliberately tolerant of code fences and
/// surrounding prose, mirroring `QuestionReviewService`.
public struct QuestionAuthoringService: Sendable {
    public init() {}

    public var systemInstruction: String {
        """
        You are an expert instructional designer authoring assessment items. Follow established \
        item-writing guidelines: one clear problem per stem, plausible distractors based on common \
        misconceptions, options parallel in grammar and length, no "all/none of the above", no \
        absolute terms, and accessible language that never relies on color or images without alt text. \
        Return only the requested JSON.
        """
    }

    // MARK: - Generate whole questions

    public func makeGenerationPrompt(
        topic: String,
        count: Int,
        types: [QuizQuestionType],
        additionalInstructions: String = ""
    ) -> String {
        let typeList = (types.isEmpty ? QuizQuestionType.allCases : types)
            .map { "\($0.rawValue) (\($0.displayName))" }
            .joined(separator: ", ")
        let extra = additionalInstructions.trimmingCharacters(in: .whitespacesAndNewlines)

        return """
        Write \(count) quiz question(s) about the following topic or learning objective:
        \(topic)

        Allowed question types (use the rawValue in the "type" field): \(typeList)
        \(extra.isEmpty ? "" : "Additional instructions: \(extra)")

        Respond with ONLY a JSON object, no prose and no code fences:
        {
          "questions": [
            {
              "type": "multipleChoice",
              "prompt": "the question stem",
              "answers": [
                {"text": "option text", "correct": true},
                {"text": "option text", "correct": false}
              ],
              "matches": [{"term": "left item", "match": "right item"}],
              "feedback": "why the key is correct and the distractors are not"
            }
          ]
        }

        Rules:
        - Use "answers" for choice-based types; use "matches" only for matching.
        - Mark exactly one option correct for multipleChoice and trueFalse; one or more for multipleAnswer.
        - For shortAnswer/fillInBlank, put accepted answers in "answers" with "correct": true.
        - For essay, omit "answers" and "matches".
        - Always include "feedback".
        """
    }

    public func parseGeneratedQuestions(_ raw: String) -> [QuizQuestion] {
        guard let json = extractJSONObject(from: raw),
              let data = json.data(using: .utf8),
              let dto = try? JSONDecoder().decode(GenerationDTO.self, from: data) else {
            return []
        }
        return dto.questions.compactMap { makeQuestion(from: $0) }
    }

    // MARK: - Generate distractors

    public func makeDistractorsPrompt(prompt: String, correctAnswer: String, count: Int) -> String {
        """
        For this question stem and its correct answer, write \(count) plausible but incorrect answer \
        options (distractors). Base them on common misconceptions. Keep them parallel in grammar and \
        length with the correct answer, and make each one clearly wrong on close reading.

        Stem: \(prompt)
        Correct answer: \(correctAnswer)

        Respond with ONLY a JSON object, no prose and no code fences:
        { "distractors": ["first distractor", "second distractor"] }
        """
    }

    public func parseDistractors(_ raw: String) -> [String] {
        // Accept either {"distractors": [...]} or a bare JSON array.
        if let json = extractJSONObject(from: raw),
           let data = json.data(using: .utf8),
           let dto = try? JSONDecoder().decode(DistractorsDTO.self, from: data) {
            return dto.distractors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let array = extractJSONArray(from: raw),
           let data = array.data(using: .utf8),
           let values = try? JSONDecoder().decode([String].self, from: data) {
            return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        return []
    }

    // MARK: - Generate feedback

    public func makeFeedbackPrompt(question: QuizQuestion, quizTitle: String) -> String {
        let answerLines: String
        if question.type == .matching {
            answerLines = question.matches.map { "- \($0.prompt) => \($0.match)" }.joined(separator: "\n")
        } else {
            answerLines = question.answers.map { "\($0.isCorrect ? "*" : "-") \($0.text)" }.joined(separator: "\n")
        }

        return """
        Draft concise feedback for this quiz question from "\(quizTitle)". Explain why the correct \
        answer is correct and why the distractors are plausible but wrong. Use accessible language.

        Prompt: \(question.prompt)
        \(answerLines)

        Respond with ONLY a JSON object, no prose and no code fences:
        { "feedback": "the feedback text" }
        """
    }

    public func parseFeedback(_ raw: String) -> String? {
        if let json = extractJSONObject(from: raw),
           let data = json.data(using: .utf8),
           let dto = try? JSONDecoder().decode(FeedbackDTO.self, from: data) {
            let trimmed = dto.feedback.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        // Fall back to using the whole response as plain feedback text.
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - DTO → model

    private func makeQuestion(from dto: GeneratedQuestionDTO) -> QuizQuestion? {
        let prompt = dto.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return nil }
        let type = questionType(from: dto.type)

        if type == .matching {
            let matches = (dto.matches ?? []).compactMap { pair -> MatchingPair? in
                let term = pair.term.trimmingCharacters(in: .whitespacesAndNewlines)
                let match = pair.match.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !term.isEmpty, !match.isEmpty else { return nil }
                return MatchingPair(prompt: term, match: match)
            }
            return QuizQuestion(type: .matching, prompt: prompt, matches: matches, feedback: cleanFeedback(dto.feedback))
        }

        let answers = (dto.answers ?? []).compactMap { answer -> QuizAnswer? in
            let text = answer.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return QuizAnswer(text: text, isCorrect: answer.correct ?? false)
        }
        return QuizQuestion(type: type, prompt: prompt, answers: answers, feedback: cleanFeedback(dto.feedback))
    }

    private func cleanFeedback(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Maps a model-supplied type string onto our enum, accepting the rawValue,
    /// the Canvas type, or a human-readable display name.
    private func questionType(from value: String?) -> QuizQuestionType {
        guard let value else { return .multipleChoice }
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "question", with: "")
        for type in QuizQuestionType.allCases {
            let raw = type.rawValue.lowercased()
            let display = type.displayName.lowercased().replacingOccurrences(of: " ", with: "")
            let canvas = type.canvasQuestionType.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "question", with: "")
            if normalized == raw || normalized == display || normalized == canvas {
                return type
            }
        }
        return .multipleChoice
    }

    // MARK: - Lenient JSON extraction

    private func extractJSONObject(from raw: String) -> String? {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end else {
            return nil
        }
        return String(raw[start...end])
    }

    private func extractJSONArray(from raw: String) -> String? {
        guard let start = raw.firstIndex(of: "["), let end = raw.lastIndex(of: "]"), start < end else {
            return nil
        }
        return String(raw[start...end])
    }

    // MARK: - DTOs

    private struct GenerationDTO: Decodable {
        let questions: [GeneratedQuestionDTO]
    }

    private struct GeneratedQuestionDTO: Decodable {
        struct Answer: Decodable {
            let text: String
            let correct: Bool?
        }
        struct Match: Decodable {
            let term: String
            let match: String
        }
        let type: String?
        let prompt: String
        let answers: [Answer]?
        let matches: [Match]?
        let feedback: String?
    }

    private struct DistractorsDTO: Decodable {
        let distractors: [String]
    }

    private struct FeedbackDTO: Decodable {
        let feedback: String
    }
}
