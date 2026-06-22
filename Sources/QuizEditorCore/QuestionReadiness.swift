import Foundation

/// A rolled-up readiness state for a question, derived purely from its data
/// (no AI). Drives the editor's status badge, the readiness checklist, and the
/// navigator badges. AI review can add further issues on top of these.
public enum ReadinessStatus: String, Sendable, Equatable {
    /// The question is barely started (no stem yet).
    case draft
    /// The question has content but at least one check is unmet.
    case needsWork
    /// Every deterministic check passes.
    case ready

    public var label: String {
        switch self {
        case .draft: "Draft"
        case .needsWork: "Needs work"
        case .ready: "Ready"
        }
    }
}

/// One deterministic readiness check and its outcome.
public struct ReadinessCheck: Equatable, Sendable, Identifiable {
    public enum Severity: Int, Sendable, Comparable {
        /// The check passes.
        case ok
        /// Recommended but not blocking (e.g. student feedback).
        case recommended
        /// A real problem that should be fixed (e.g. no correct answer).
        case required

        public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Stable key (e.g. "stem", "choices", "key") for matching across renders.
    public let id: String
    /// Short label for the checklist (e.g. "Correct answer").
    public let title: String
    public let severity: Severity
    /// One-line, human-friendly explanation.
    public let message: String

    public var isSatisfied: Bool { severity == .ok }

    public init(id: String, title: String, severity: Severity, message: String) {
        self.id = id
        self.title = title
        self.severity = severity
        self.message = message
    }
}

/// Computes the deterministic readiness of a single question.
public struct QuestionReadiness: Equatable, Sendable {
    public let checks: [ReadinessCheck]

    public init(question: QuizQuestion) {
        self.checks = Self.computeChecks(for: question)
    }

    /// The rolled-up status: a missing stem is a draft; any unmet check otherwise
    /// means it needs work; all passing means ready.
    public var status: ReadinessStatus {
        if checks.first(where: { $0.id == "stem" })?.severity == .required {
            return .draft
        }
        return checks.contains { !$0.isSatisfied } ? .needsWork : .ready
    }

    /// Checks that are not yet satisfied, in declaration order.
    public var unmet: [ReadinessCheck] { checks.filter { !$0.isSatisfied } }

    // MARK: - Computation

    private static func computeChecks(for question: QuizQuestion) -> [ReadinessCheck] {
        var checks: [ReadinessCheck] = [stemCheck(question)]

        switch question.type {
        case .multipleChoice, .trueFalse:
            checks += optionChecks(question, singleSelect: true)
        case .multipleAnswer:
            checks += optionChecks(question, singleSelect: false)
        case .fillInBlank, .shortAnswer:
            checks += acceptedAnswerChecks(question)
        case .numeric:
            checks.append(numericCheck(question))
        case .matching:
            checks += matchingChecks(question)
        case .essay:
            break // open response: no answer key
        }

        checks.append(feedbackCheck(question))
        return checks
    }

    private static func plain(_ html: String) -> String {
        HTMLUtilities().plainText(fromHTML: html).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stemCheck(_ question: QuizQuestion) -> ReadinessCheck {
        let empty = plain(question.prompt).isEmpty
        return ReadinessCheck(
            id: "stem",
            title: "Question stem",
            severity: empty ? .required : .ok,
            message: empty ? "Write the question stem." : "Stem present."
        )
    }

    private static func feedbackCheck(_ question: QuizQuestion) -> ReadinessCheck {
        let empty = plain(question.feedback).isEmpty
        return ReadinessCheck(
            id: "feedback",
            title: "Student feedback",
            severity: empty ? .recommended : .ok,
            message: empty ? "Add feedback so students learn from the result." : "Feedback written."
        )
    }

    private static func optionChecks(_ question: QuizQuestion, singleSelect: Bool) -> [ReadinessCheck] {
        let answers = question.answers
        let texts = answers.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let nonBlank = texts.filter { !$0.isEmpty }
        var checks: [ReadinessCheck] = []

        checks.append(ReadinessCheck(
            id: "choices",
            title: "Answer choices",
            severity: answers.count >= 2 ? .ok : .required,
            message: answers.count >= 2 ? "\(answers.count) choices." : "Add at least two answer choices."
        ))

        let hasBlank = texts.contains(where: \.isEmpty)
        checks.append(ReadinessCheck(
            id: "blanks",
            title: "No blank choices",
            severity: hasBlank ? .required : .ok,
            message: hasBlank ? "Fill in or remove the blank answer choice." : "No blank choices."
        ))

        let hasDuplicate = Set(nonBlank.map { $0.lowercased() }).count != nonBlank.count
        checks.append(ReadinessCheck(
            id: "duplicates",
            title: "Distinct answers",
            severity: hasDuplicate ? .required : .ok,
            message: hasDuplicate ? "Two answer choices are identical." : "All choices are distinct."
        ))

        let correct = answers.filter(\.isCorrect).count
        let satisfied = singleSelect ? correct == 1 : correct >= 1
        let message: String
        if correct == 0 {
            message = "Mark the correct answer."
        } else if singleSelect && correct > 1 {
            message = "Only one answer can be correct for this question type."
        } else {
            message = "Correct answer marked."
        }
        checks.append(ReadinessCheck(
            id: "key",
            title: "Correct answer",
            severity: satisfied ? .ok : .required,
            message: message
        ))

        return checks
    }

    private static func acceptedAnswerChecks(_ question: QuizQuestion) -> [ReadinessCheck] {
        let nonBlank = question.answers
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var checks: [ReadinessCheck] = []

        checks.append(ReadinessCheck(
            id: "key",
            title: "Accepted answer",
            severity: nonBlank.isEmpty ? .required : .ok,
            message: nonBlank.isEmpty ? "Add at least one accepted answer." : "\(nonBlank.count) accepted answer(s)."
        ))

        let hasDuplicate = Set(nonBlank.map { $0.lowercased() }).count != nonBlank.count
        checks.append(ReadinessCheck(
            id: "duplicates",
            title: "Distinct answers",
            severity: hasDuplicate ? .required : .ok,
            message: hasDuplicate ? "Two accepted answers are identical." : "All accepted answers are distinct."
        ))

        return checks
    }

    private static func numericCheck(_ question: QuizQuestion) -> ReadinessCheck {
        let configured = question.numeric?.isConfigured ?? false
        return ReadinessCheck(
            id: "numeric",
            title: "Numeric answer",
            severity: configured ? .ok : .required,
            message: configured ? "Answer configured." : "Set the expected value, range, or precision."
        )
    }

    private static func matchingChecks(_ question: QuizQuestion) -> [ReadinessCheck] {
        var checks: [ReadinessCheck] = []

        checks.append(ReadinessCheck(
            id: "pairs",
            title: "Matching pairs",
            severity: question.matches.count >= 2 ? .ok : .required,
            message: question.matches.count >= 2 ? "\(question.matches.count) pairs." : "Add at least two matching pairs."
        ))

        let hasBlank = question.matches.contains {
            $0.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || $0.match.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        checks.append(ReadinessCheck(
            id: "blanks",
            title: "No blank sides",
            severity: hasBlank ? .required : .ok,
            message: hasBlank ? "Fill in both sides of every pair." : "All pairs complete."
        ))

        return checks
    }
}
