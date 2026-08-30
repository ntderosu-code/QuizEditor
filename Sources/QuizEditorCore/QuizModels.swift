import Foundation

/// Whether the quiz is graded (questions are scored) or a survey (responses are
/// collected, never scored). Affects export shape (surveys strip `resprocessing`)
/// and which linter rules apply (answer-key rules are skipped for surveys).
public enum QuizKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case graded
    case survey

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .graded: "Graded Quiz"
        case .survey: "Survey"
        }
    }
}

public struct Quiz: Equatable, Codable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var questions: [QuizQuestion]
    /// Per-quiz persona override. `nil` means "use the app default persona."
    /// Optional, so a missing key decodes as `nil` and quizzes saved before
    /// personas existed keep opening unchanged.
    public var personaID: String?
    /// Reusable linking entities (issue #23): authored once on the quiz and
    /// referenced by many questions via id. Author metadata — never exported.
    public var objectives: [LearningObjective]
    public var stimuli: [Stimulus]
    public var sources: [Source]
    /// Whether the quiz is graded or a survey. Decoded tolerantly: quizzes saved
    /// before this field existed open as `.graded`.
    public var kind: QuizKind

    public init(
        id: UUID = UUID(),
        title: String,
        questions: [QuizQuestion] = [],
        personaID: String? = nil,
        objectives: [LearningObjective] = [],
        stimuli: [Stimulus] = [],
        sources: [Source] = [],
        kind: QuizKind = .graded
    ) {
        self.id = id
        self.title = title
        self.questions = questions
        self.personaID = personaID
        self.objectives = objectives
        self.stimuli = stimuli
        self.sources = sources
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, questions, personaID, objectives, stimuli, sources, kind
    }

    // Decodes tolerantly so quizzes saved before linking existed still open: a
    // missing collection falls back to empty rather than failing the whole decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled Quiz"
        questions = try container.decodeIfPresent([QuizQuestion].self, forKey: .questions) ?? []
        personaID = try container.decodeIfPresent(String.self, forKey: .personaID)
        objectives = try container.decodeIfPresent([LearningObjective].self, forKey: .objectives) ?? []
        stimuli = try container.decodeIfPresent([Stimulus].self, forKey: .stimuli) ?? []
        sources = try container.decodeIfPresent([Source].self, forKey: .sources) ?? []
        kind = try container.decodeIfPresent(QuizKind.self, forKey: .kind) ?? .graded
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
    /// Links into the quiz's reusable entities (issue #23), by id. Empty/nil when
    /// nothing is linked. Author metadata — never written into an export.
    public var objectiveIDs: [String]
    public var competencyIDs: [String]
    public var sourceIDs: [String]
    public var stimulusID: String?
    /// Grading spec for a `.numeric` question; nil for every other type.
    public var numeric: NumericAnswer?
    /// Grading spec for a `.formula` question; nil for every other type.
    public var formula: FormulaAnswer?
    /// Optional MIME-type allowlist for `.fileUpload` questions; empty means any
    /// type. This one *is* exported: Canvas reads it to constrain the upload
    /// widget, and defaults to "any file" when it is absent.
    public var allowedFileTypes: [String]

    public init(
        id: UUID = UUID(),
        type: QuizQuestionType,
        prompt: String,
        answers: [QuizAnswer] = [],
        matches: [MatchingPair] = [],
        feedback: String = "",
        points: Double = 1,
        tags: [String] = [],
        difficulty: QuizDifficulty? = nil,
        objectiveIDs: [String] = [],
        competencyIDs: [String] = [],
        sourceIDs: [String] = [],
        stimulusID: String? = nil,
        numeric: NumericAnswer? = nil,
        formula: FormulaAnswer? = nil,
        allowedFileTypes: [String] = []
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
        self.objectiveIDs = objectiveIDs
        self.competencyIDs = competencyIDs
        self.sourceIDs = sourceIDs
        self.stimulusID = stimulusID
        self.numeric = numeric
        self.formula = formula
        self.allowedFileTypes = allowedFileTypes
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, prompt, answers, matches, feedback, points, tags, difficulty
        case objectiveIDs, competencyIDs, sourceIDs, stimulusID, numeric, formula, allowedFileTypes
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
        objectiveIDs = try container.decodeIfPresent([String].self, forKey: .objectiveIDs) ?? []
        competencyIDs = try container.decodeIfPresent([String].self, forKey: .competencyIDs) ?? []
        sourceIDs = try container.decodeIfPresent([String].self, forKey: .sourceIDs) ?? []
        stimulusID = try container.decodeIfPresent(String.self, forKey: .stimulusID)
        numeric = try container.decodeIfPresent(NumericAnswer.self, forKey: .numeric)
        formula = try container.decodeIfPresent(FormulaAnswer.self, forKey: .formula)
        allowedFileTypes = try container.decodeIfPresent([String].self, forKey: .allowedFileTypes) ?? []
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
    case numeric
    /// Student uploads a file. Scored manually (or by rubric) in Canvas; the
    /// package carries the question stem and the accepted MIME types.
    case fileUpload
    /// Computed answer: the author supplies variables, an arithmetic expression,
    /// and a tolerance. Canvas calls this `calculated_question` (Classic) and
    /// the QTI 2.1 community calls it `formula_question`; the canonical name in
    /// our model is `.formula` for clarity.
    case formula

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
        case .numeric: "Numeric"
        case .fileUpload: "File Upload"
        case .formula: "Formula"
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
        case .numeric: "numerical_question"
        case .fileUpload: "file_upload_question"
        case .formula: "calculated_question"
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
    /// Optional tag naming the misconception a distractor targets (issue #23,
    /// consumed later by the misconception feature). Optional, so the synthesized
    /// decoder treats a missing key as `nil` and older answers decode unchanged.
    public var misconceptionTag: String?

    public init(id: UUID = UUID(), text: String, isCorrect: Bool = false, misconceptionTag: String? = nil) {
        self.id = id
        self.text = text
        self.isCorrect = isCorrect
        self.misconceptionTag = misconceptionTag
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
