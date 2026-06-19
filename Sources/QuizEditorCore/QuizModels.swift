import Foundation

public struct Quiz: Equatable, Codable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var questions: [QuizQuestion]

    public init(id: UUID = UUID(), title: String, questions: [QuizQuestion] = []) {
        self.id = id
        self.title = title
        self.questions = questions
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
                feedback: "The mitochondrion generates ATP through cellular respiration."
            ),
            QuizQuestion(
                type: .shortAnswer,
                prompt: "What molecule stores a cell's genetic information?",
                answers: [QuizAnswer(text: "DNA", isCorrect: true)],
                feedback: "DNA holds the hereditary instructions a cell uses to function."
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

    public init(
        id: UUID = UUID(),
        type: QuizQuestionType,
        prompt: String,
        answers: [QuizAnswer] = [],
        matches: [MatchingPair] = [],
        feedback: String = "",
        points: Double = 1
    ) {
        self.id = id
        self.type = type
        self.prompt = prompt
        self.answers = answers
        self.matches = matches
        self.feedback = feedback
        self.points = points
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
