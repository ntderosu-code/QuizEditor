import Foundation

/// One problem the offline linter found in a question. Findings are advisory —
/// they surface common item-writing mistakes but never block editing or export.
public struct LintFinding: Equatable, Sendable, Identifiable {
    public enum Severity: Sendable, Equatable {
        /// A likely correctness problem (e.g. no correct answer marked).
        case warning
        /// A style or item-writing improvement (e.g. avoid "all of the above").
        case suggestion
    }

    public enum Rule: String, Sendable, Equatable, CaseIterable {
        case noCorrectAnswer
        case multipleCorrectAnswers
        case allOrNoneOfTheAbove
        case unemphasizedNegativeStem
        case longestOptionIsCorrect
        case duplicateOptions
        case emptyOption
        case missingFeedback
        case articleCue
    }

    public let rule: Rule
    public let severity: Severity
    /// Names the issue in plain language.
    public let message: String
    /// A concrete suggested fix.
    public let suggestion: String

    /// One finding per rule per question, so the rule is a stable identity.
    public var id: String { rule.rawValue }

    public init(rule: Rule, severity: Severity, message: String, suggestion: String) {
        self.rule = rule
        self.severity = severity
        self.message = message
        self.suggestion = suggestion
    }
}

/// A fast, offline, rule-based reviewer that catches common item-writing
/// problems instantly and without a network or API. It complements (does not
/// replace) the AI review, applying the same guidelines `QuestionReviewService`
/// uses as prompt instructions.
public struct QuestionLinter: Sendable {
    private let html = HTMLUtilities()

    /// The correct option must be at least this many times the length of the
    /// longest distractor (and longer by `lengthBiasMinCharGap`) to be flagged
    /// as a length-bias cue. Thresholds are deliberately conservative to avoid
    /// nagging on questions where the longer option is simply necessary.
    private let lengthBiasRatio = 1.3
    private let lengthBiasMinCharGap = 10

    public init() {}

    /// Findings for one question, ordered most-severe first.
    public func findings(for question: QuizQuestion) -> [LintFinding] {
        var findings: [LintFinding] = []

        findings.append(contentsOf: answerKeyFindings(question))
        findings.append(contentsOf: optionTextFindings(question))
        if let allNone = allOrNoneFinding(question) { findings.append(allNone) }
        if let negative = negativeStemFinding(question) { findings.append(negative) }
        if let lengthBias = lengthBiasFinding(question) { findings.append(lengthBias) }
        if let article = articleCueFinding(question) { findings.append(article) }
        if let feedback = missingFeedbackFinding(question) { findings.append(feedback) }

        return findings.sorted { lhs, rhs in
            severityRank(lhs.severity) < severityRank(rhs.severity)
        }
    }

    /// Findings for every question in a quiz, keyed by question id. Questions
    /// with no findings are omitted.
    public func findings(for quiz: Quiz) -> [QuizQuestion.ID: [LintFinding]] {
        var result: [QuizQuestion.ID: [LintFinding]] = [:]
        for question in quiz.questions {
            let questionFindings = findings(for: question)
            if !questionFindings.isEmpty {
                result[question.id] = questionFindings
            }
        }
        return result
    }

    // MARK: - Answer-key rules

    private func answerKeyFindings(_ question: QuizQuestion) -> [LintFinding] {
        var findings: [LintFinding] = []
        let correctCount = question.answers.filter(\.isCorrect).count

        switch question.type {
        case .multipleChoice, .trueFalse:
            if correctCount == 0 {
                findings.append(LintFinding(
                    rule: .noCorrectAnswer,
                    severity: .warning,
                    message: "No correct answer is marked.",
                    suggestion: "Mark exactly one option as correct."
                ))
            } else if correctCount > 1 {
                findings.append(LintFinding(
                    rule: .multipleCorrectAnswers,
                    severity: .warning,
                    message: "More than one option is marked correct on a single-answer question.",
                    suggestion: "Mark only one option correct, or change the type to Multiple Answer."
                ))
            }
        case .multipleAnswer:
            if correctCount == 0 {
                findings.append(LintFinding(
                    rule: .noCorrectAnswer,
                    severity: .warning,
                    message: "No correct answers are marked.",
                    suggestion: "Mark every option that should count as correct."
                ))
            }
        case .shortAnswer, .fillInBlank:
            if question.answers.isEmpty || correctCount == 0 {
                findings.append(LintFinding(
                    rule: .noCorrectAnswer,
                    severity: .warning,
                    message: "No accepted answer is provided to grade against.",
                    suggestion: "Add at least one accepted answer and mark it correct."
                ))
            }
        case .essay, .matching:
            break
        }

        return findings
    }

    // MARK: - Option-text rules (empty / duplicate)

    private func optionTextFindings(_ question: QuizQuestion) -> [LintFinding] {
        let optionTexts: [String]
        switch question.type {
        case .matching:
            optionTexts = question.matches.flatMap { [plain($0.prompt), plain($0.match)] }
        case .essay:
            optionTexts = []
        default:
            optionTexts = question.answers.map { plain($0.text) }
        }

        guard !optionTexts.isEmpty else { return [] }

        var findings: [LintFinding] = []

        if optionTexts.contains(where: { $0.isEmpty }) {
            let noun = question.type == .matching ? "matching pair" : "answer option"
            findings.append(LintFinding(
                rule: .emptyOption,
                severity: .warning,
                message: "At least one \(noun) is empty.",
                suggestion: "Fill in or remove the blank \(noun)."
            ))
        }

        let normalized = optionTexts.map { $0.lowercased() }.filter { !$0.isEmpty }
        if Set(normalized).count < normalized.count {
            findings.append(LintFinding(
                rule: .duplicateOptions,
                severity: .warning,
                message: "Two or more options have identical text.",
                suggestion: "Make every option distinct so only one reading is correct."
            ))
        }

        return findings
    }

    // MARK: - Style rules

    private func allOrNoneFinding(_ question: QuizQuestion) -> LintFinding? {
        guard usesChoiceOptions(question) else { return nil }
        let pattern = "^(all|none|both)\\s+of\\s+the\\s+(above|following|others)\\.?$"
        let hasAllNone = question.answers.contains { answer in
            let text = plain(answer.text)
            return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        guard hasAllNone else { return nil }
        return LintFinding(
            rule: .allOrNoneOfTheAbove,
            severity: .suggestion,
            message: "An option uses \u{201C}all/none of the above.\u{201D}",
            suggestion: "Replace it with a concrete option; these cue test-wise guessing."
        )
    }

    private func negativeStemFinding(_ question: QuizQuestion) -> LintFinding? {
        let stem = plain(question.prompt)
        guard stem.range(of: "\\b(not|except)\\b", options: [.regularExpression, .caseInsensitive]) != nil else {
            return nil
        }
        // Emphasized if already shown in ALL CAPS, or wrapped in a bold/italic/
        // underline tag in the source HTML.
        if stem.range(of: "\\b(NOT|EXCEPT)\\b", options: .regularExpression) != nil {
            return nil
        }
        if question.prompt.range(
            of: "<(b|strong|em|i|u)\\b[^>]*>[^<]*\\b(not|except)\\b",
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return nil
        }
        return LintFinding(
            rule: .unemphasizedNegativeStem,
            severity: .suggestion,
            message: "The stem is negative (\u{201C}not\u{201D}/\u{201C}except\u{201D}) but the negative word is not emphasized.",
            suggestion: "Emphasize the negative word, e.g. capitalize NOT or make it bold."
        )
    }

    private func lengthBiasFinding(_ question: QuizQuestion) -> LintFinding? {
        guard question.type == .multipleChoice || question.type == .multipleAnswer else { return nil }
        guard question.answers.count >= 3 else { return nil }

        let lengths = question.answers.map { plain($0.text).count }
        guard let maxLength = lengths.max(), maxLength > 0 else { return nil }

        let longestIndices = lengths.indices.filter { lengths[$0] == maxLength }
        guard longestIndices.count == 1, let longestIndex = longestIndices.first else { return nil }
        guard question.answers[longestIndex].isCorrect else { return nil }

        let distractorMax = question.answers.indices
            .filter { !question.answers[$0].isCorrect }
            .map { lengths[$0] }
            .max() ?? 0

        let clearlyLonger = Double(maxLength) >= lengthBiasRatio * Double(max(distractorMax, 1))
            && (maxLength - distractorMax) >= lengthBiasMinCharGap
        guard clearlyLonger else { return nil }

        return LintFinding(
            rule: .longestOptionIsCorrect,
            severity: .suggestion,
            message: "The correct option is noticeably longer than the distractors.",
            suggestion: "Balance option length so the key does not stand out."
        )
    }

    private func articleCueFinding(_ question: QuizQuestion) -> LintFinding? {
        guard usesChoiceOptions(question) else { return nil }
        var stem = plain(question.prompt)
        // Drop trailing blank markers and punctuation before checking the last word.
        stem = stem.trimmingCharacters(in: CharacterSet(charactersIn: " _:?.\u{2026}-\t\n"))
        let lastWord = stem.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).last.map(String.init)?.lowercased()
        guard lastWord == "a" || lastWord == "an" else { return nil }
        return LintFinding(
            rule: .articleCue,
            severity: .suggestion,
            message: "The stem ends with \u{201C}\(lastWord ?? "a")\u{201D}, which can cue the answer grammatically.",
            suggestion: "Reword to \u{201C}a(n)\u{201D} or move the article into each option."
        )
    }

    private func missingFeedbackFinding(_ question: QuizQuestion) -> LintFinding? {
        guard plain(question.feedback).isEmpty else { return nil }
        return LintFinding(
            rule: .missingFeedback,
            severity: .suggestion,
            message: "This question has no feedback for students.",
            suggestion: "Fill in the Feedback for students field to explain why the key is correct and the distractors are not."
        )
    }

    // MARK: - Helpers

    private func usesChoiceOptions(_ question: QuizQuestion) -> Bool {
        switch question.type {
        case .multipleChoice, .multipleAnswer, .trueFalse: true
        case .fillInBlank, .shortAnswer, .essay, .matching: false
        }
    }

    private func plain(_ value: String) -> String {
        html.plainText(fromHTML: value).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func severityRank(_ severity: LintFinding.Severity) -> Int {
        switch severity {
        case .warning: 0
        case .suggestion: 1
        }
    }
}
