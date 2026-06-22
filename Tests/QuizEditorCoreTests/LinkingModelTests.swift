import XCTest
@testable import QuizEditorCore

/// Issue #23: questions gain first-class links to learning objectives, sources,
/// and a shared stimulus, and the quiz carries those reusable entities. Every
/// addition is tolerant-decoded so quizzes saved before linking existed still open.
final class LinkingModelTests: XCTestCase {
    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func testLearningObjectiveRoundTrips() throws {
        let objective = LearningObjective(id: "obj1", text: "Analyze acid-base balance", cognitiveLevel: .analyze)
        XCTAssertEqual(try roundTrip(objective), objective)
    }

    func testStimulusRoundTripsWithFigureAndAltText() throws {
        let stimulus = Stimulus(
            id: "stim1",
            kind: .vignette,
            body: "A 64-year-old presents with shortness of breath...",
            figureImage: "data:image/png;base64,AAAA",
            altText: "Chest X-ray showing bilateral infiltrates",
            dataTable: "pH 7.30 | PaCO2 50"
        )
        XCTAssertEqual(try roundTrip(stimulus), stimulus)
    }

    func testSourceRoundTrips() throws {
        let source = Source(
            id: "src1",
            author: "WHO",
            date: "2023",
            place: "Geneva",
            type: .guideline,
            citation: "WHO. Hypertension guidelines. 2023."
        )
        XCTAssertEqual(try roundTrip(source), source)
    }

    func testQuestionLinkFieldsRoundTrip() throws {
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "Per the vignette, what is the priority action?",
            answers: [QuizAnswer(text: "Administer oxygen", isCorrect: true)],
            objectiveIDs: ["obj1"],
            competencyIDs: ["comp1"],
            sourceIDs: ["src1"],
            stimulusID: "stim1"
        )
        let decoded = try roundTrip(question)
        XCTAssertEqual(decoded.objectiveIDs, ["obj1"])
        XCTAssertEqual(decoded.competencyIDs, ["comp1"])
        XCTAssertEqual(decoded.sourceIDs, ["src1"])
        XCTAssertEqual(decoded.stimulusID, "stim1")
    }

    func testAnswerMisconceptionTagRoundTrips() throws {
        let answer = QuizAnswer(text: "Bradycardia", isCorrect: false, misconceptionTag: "confuses-with-hyperglycemia")
        XCTAssertEqual(try roundTrip(answer).misconceptionTag, "confuses-with-hyperglycemia")
    }

    func testQuizLinkingCollectionsRoundTrip() throws {
        let quiz = Quiz(
            title: "Linked",
            questions: [],
            objectives: [LearningObjective(id: "obj1", text: "Apply pharmacokinetics", cognitiveLevel: .apply)],
            stimuli: [Stimulus(id: "stim1", kind: .passage, body: "Excerpt...")],
            sources: [Source(id: "src1", citation: "Smith 2020")]
        )
        let decoded = try roundTrip(quiz)
        XCTAssertEqual(decoded.objectives, quiz.objectives)
        XCTAssertEqual(decoded.stimuli, quiz.stimuli)
        XCTAssertEqual(decoded.sources, quiz.sources)
    }

    func testQuizSavedBeforeLinkingStillDecodes() throws {
        // A quiz JSON that predates linking: no objectives/stimuli/sources keys,
        // and a question with no link fields. It must decode with empty defaults.
        let legacy = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "title": "Legacy Quiz",
            "questions": [
                { "type": "multipleChoice", "prompt": "Q?", "answers": [] }
            ]
        }
        """.data(using: .utf8)!

        let quiz = try JSONDecoder().decode(Quiz.self, from: legacy)
        XCTAssertEqual(quiz.objectives, [])
        XCTAssertEqual(quiz.stimuli, [])
        XCTAssertEqual(quiz.sources, [])
        XCTAssertEqual(quiz.questions.first?.objectiveIDs, [])
        XCTAssertNil(quiz.questions.first?.stimulusID)
        XCTAssertNil(quiz.questions.first?.answers.first?.misconceptionTag)
    }

    func testLinkingMetadataIsNotWrittenIntoQTIExport() throws {
        // Linking is author metadata. The acceptance criterion requires it never
        // appear in a QTI/Common Cartridge export.
        let quiz = Quiz(
            title: "Exported",
            questions: [
                QuizQuestion(
                    type: .multipleChoice,
                    prompt: "Per the vignette, what is the priority action?",
                    answers: [
                        QuizAnswer(text: "Administer oxygen", isCorrect: true, misconceptionTag: "MISCONCEPTION_TOKEN"),
                        QuizAnswer(text: "Document and reassess", isCorrect: false)
                    ],
                    feedback: "Oxygen first.",
                    objectiveIDs: ["OBJECTIVE_TOKEN"],
                    competencyIDs: ["COMPETENCY_TOKEN"],
                    sourceIDs: ["SOURCE_TOKEN"],
                    stimulusID: "STIMULUS_TOKEN"
                )
            ],
            objectives: [LearningObjective(id: "OBJECTIVE_TOKEN", text: "Apply oxygenation priorities", cognitiveLevel: .apply)],
            stimuli: [Stimulus(id: "STIMULUS_TOKEN", kind: .vignette, body: "STIMULUS_BODY_TOKEN")],
            sources: [Source(id: "SOURCE_TOKEN", citation: "SOURCE_CITATION_TOKEN")]
        )

        let package = try CanvasQTIExporter(engine: .classicQuizzes).makePackage(for: quiz)
        let everything = package.files.map(\.contents).joined(separator: "\n")

        for token in ["OBJECTIVE_TOKEN", "COMPETENCY_TOKEN", "SOURCE_TOKEN", "STIMULUS_TOKEN",
                      "MISCONCEPTION_TOKEN", "STIMULUS_BODY_TOKEN", "SOURCE_CITATION_TOKEN"] {
            XCTAssertFalse(everything.contains(token), "\(token) leaked into the QTI export")
        }
    }
}
