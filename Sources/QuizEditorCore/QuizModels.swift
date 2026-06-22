import Foundation

public struct Quiz: Equatable, Codable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var questions: [QuizQuestion]
    /// Per-quiz persona override. `nil` means "use the app default persona."
    /// Optional, so the synthesized decoder treats a missing key as `nil` and
    /// quizzes saved before personas existed keep opening unchanged.
    public var personaID: String?

    public init(id: UUID = UUID(), title: String, questions: [QuizQuestion] = [], personaID: String? = nil) {
        self.id = id
        self.title = title
        self.questions = questions
        self.personaID = personaID
    }

    public static let sample = Quiz(
        title: "Cell Biology Quiz",
        questions: [
            QuizQuestion(
                type: .multipleChoice,
                prompt: "Which organelle is primarily responsible for producing ATP?",
                answers: [
                    QuizAnswer(text: "Mitochondrion", isCorrect: true),
                    QuizAnswer(text: "Ribosome", isCorrect: false),
                    QuizAnswer(text: "Golgi apparatus", isCorrect: false),
                    QuizAnswer(text: "Lysosome", isCorrect: false)
                ],
                feedback: "The mitochondrion generates ATP through cellular respiration.",
                tags: ["organelles", "energy"],
                difficulty: .easy
            ),
            QuizQuestion(
                type: .shortAnswer,
                prompt: "What molecule stores a cell's genetic information?",
                answers: [QuizAnswer(text: "DNA", isCorrect: true)],
                feedback: "DNA holds the hereditary instructions a cell uses to function.",
                tags: ["genetics"],
                difficulty: .medium
            )
        ]
    )
}

public struct QuizQuestion: Equatable, Codable, Identifiable, Sendable {
    public var id: UUID
    public var type: QuizQuestionType
    public var prompt: String
    public var answers: [QuizAnswer]
    public var matches: [MatchingPair]
    public var feedback: String
    public var points: Double
    /// Free-form topic tags used to organize and filter questions.
    public var tags: [String]
    /// Optional difficulty rating; `nil` means unspecified.
    public var difficulty: QuizDifficulty?

    public init(
        id: UUID = UUID(),
        type: QuizQuestionType,
        prompt: String,
        answers: [QuizAnswer] = [],
        matches: [MatchingPair] = [],
        feedback: String = "",
        points: Double = 1,
        tags: [String] = [],
        difficulty: QuizDifficulty? = nil
    ) {
        self.id = id
        self.type = type
        self.prompt = prompt
        self.answers = answers
        self.matches = matches
        self.feedback = feedback
        self.points = points
        self.tags = tags
        self.difficulty = difficulty
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, prompt, answers, matches, feedback, points, tags, difficulty
    }

    // Decodes tolerantly so quizzes saved before metadata existed still open:
    // any field absent from the JSON falls back to its empty/default value.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type = try container.decode(QuizQuestionType.self, forKey: .type)
        prompt = try container.decode(String.self, forKey: .prompt)
        answers = try container.decodeIfPresent([QuizAnswer].self, forKey: .answers) ?? []
        matches = try container.decodeIfPresent([MatchingPair].self, forKey: .matches) ?? []
        feedback = try container.decodeIfPresent(String.self, forKey: .feedback) ?? ""
        points = try container.decodeIfPresent(Double.self, forKey: .points) ?? 1
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        difficulty = try container.decodeIfPresent(QuizDifficulty.self, forKey: .difficulty)
    }
}

public enum QuizDifficulty: String, CaseIterable, Codable, Identifiable, Sendable {
    case easy
    case medium
    case hard

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Hard"
        }
    }
}

public enum QuizQuestionType: String, CaseIterable, Codable, Identifiable, Sendable {
    case multipleChoice
    case multipleAnswer
    case trueFalse
    case fillInBlank
    case shortAnswer
    case essay
    case matching

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .multipleChoice: "Multiple Choice"
        case .multipleAnswer: "Multiple Answer"
        case .trueFalse: "True/False"
        case .fillInBlank: "Fill in the Blank"
        case .shortAnswer: "Short Answer"
        case .essay: "Essay"
        case .matching: "Matching"
        }
    }

    public var canvasQuestionType: String {
        switch self {
        case .multipleChoice: "multiple_choice_question"
        case .multipleAnswer: "multiple_answers_question"
        case .trueFalse: "true_false_question"
        case .fillInBlank: "fill_in_the_blank_question"
        case .shortAnswer: "short_answer_question"
        case .essay: "essay_question"
        case .matching: "matching_question"
        }
    }
}

public extension Quiz {
    /// Every distinct tag used across the quiz, de-duplicated case-insensitively
    /// (preserving the first-seen spelling) and sorted for stable display.
    var allTags: [String] {
        var seenKeys: Set<String> = []
        var orderedTags: [String] = []
        for question in questions {
            for tag in question.tags {
                let key = tag.lowercased()
                if !seenKeys.contains(key) {
                    seenKeys.insert(key)
                    orderedTags.append(tag)
                }
            }
        }
        return orderedTags.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The sum of every question's point value.
    var totalPoints: Double {
        questions.reduce(0) { $0 + $1.points }
    }
}

public struct QuizAnswer: Equatable, Codable, Identifiable, Sendable {
    public var id: UUID
    public var text: String
    public var isCorrect: Bool

    public init(id: UUID = UUID(), text: String, isCorrect: Bool = false) {
        self.id = id
        self.text = text
        self.isCorrect = isCorrect
    }
}

public struct MatchingPair: Equatable, Codable, Identifiable, Sendable {
    public var id: UUID
    public var prompt: String
    public var match: String

    public init(id: UUID = UUID(), prompt: String, match: String) {
        self.id = id
        self.prompt = prompt
        self.match = match
    }
}
