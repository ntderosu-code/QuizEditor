import XCTest
@testable import QuizEditorCore

final class QuizModelsTests: XCTestCase {
    func testDecodesLegacyQuizWithoutMetadataFields() throws {
        // A quiz saved before tags/difficulty/points existed: the question only
        // carries id/type/prompt/answers. Decoding must not throw.
        let legacyJSON = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "title": "Legacy Quiz",
          "questions": [
            {
              "id": "22222222-2222-2222-2222-222222222222",
              "type": "multipleChoice",
              "prompt": "Older question?",
              "answers": [{ "id": "33333333-3333-3333-3333-333333333333", "text": "Yes", "isCorrect": true }]
            }
          ]
        }
        """

        let quiz = try JSONDecoder().decode(Quiz.self, from: Data(legacyJSON.utf8))
        let question = try XCTUnwrap(quiz.questions.first)

        XCTAssertEqual(question.prompt, "Older question?")
        XCTAssertEqual(question.tags, [])
        XCTAssertNil(question.difficulty)
        XCTAssertEqual(question.points, 1)
        XCTAssertEqual(question.matches, [])
        XCTAssertEqual(question.feedback, "")
    }

    func testMetadataRoundTripsThroughCoding() throws {
        let original = Quiz(
            title: "Tagged",
            questions: [
                QuizQuestion(
                    type: .multipleChoice,
                    prompt: "Q",
                    answers: [QuizAnswer(text: "A", isCorrect: true)],
                    points: 2.5,
                    tags: ["Bio", "cells"],
                    difficulty: .hard
                )
            ]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Quiz.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.questions.first?.difficulty, .hard)
        XCTAssertEqual(decoded.questions.first?.tags, ["Bio", "cells"])
        XCTAssertEqual(decoded.questions.first?.points, 2.5)
    }

    func testAllTagsDeDuplicatesCaseInsensitivelyAndSorts() {
        let quiz = Quiz(
            title: "T",
            questions: [
                QuizQuestion(type: .essay, prompt: "1", tags: ["Cells", "energy"]),
                QuizQuestion(type: .essay, prompt: "2", tags: ["cells", "ATP"])
            ]
        )

        // "Cells"/"cells" collapse to one entry (first spelling wins), sorted A–Z.
        XCTAssertEqual(quiz.allTags, ["ATP", "Cells", "energy"])
    }

    func testTotalPointsSumsQuestions() {
        let quiz = Quiz(
            title: "T",
            questions: [
                QuizQuestion(type: .essay, prompt: "1", points: 3),
                QuizQuestion(type: .essay, prompt: "2", points: 1.5)
            ]
        )
        XCTAssertEqual(quiz.totalPoints, 4.5)
    }

    // MARK: - QuizKind (graded vs survey)

    func testNewQuizKindDefaultsToGraded() {
        let quiz = Quiz(title: "T")
        XCTAssertEqual(quiz.kind, .graded)
    }

    func testQuizKindRoundTripsThroughCoding() throws {
        let survey = Quiz(title: "Mid-semester feedback", kind: .survey)
        let data = try JSONEncoder().encode(survey)
        let decoded = try JSONDecoder().decode(Quiz.self, from: data)
        XCTAssertEqual(decoded.kind, .survey)
    }

    func testLegacyQuizDecodesAsGraded() throws {
        // Pre-QuizKind JSON: no `kind` field. Must still open, defaulting to graded.
        let legacyJSON = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "title": "Legacy",
          "questions": []
        }
        """
        let quiz = try JSONDecoder().decode(Quiz.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(quiz.kind, .graded)
    }

    // MARK: - New question types

    func testFileUploadAndFormulaRoundTrip() throws {
        let formula = FormulaAnswer(
            variables: [FormulaVariable(name: "m", value: 2), FormulaVariable(name: "a", value: 9.8)],
            expression: "m * a",
            tolerance: 0.1,
            expectedUnit: "N"
        )
        let question = QuizQuestion(
            type: .formula,
            prompt: "Compute F.",
            answers: [],
            formula: formula
        )
        let data = try JSONEncoder().encode(question)
        let decoded = try JSONDecoder().decode(QuizQuestion.self, from: data)
        XCTAssertEqual(decoded.type, .formula)
        XCTAssertEqual(decoded.formula?.variables.count, 2)
        XCTAssertEqual(decoded.formula?.expression, "m * a")
        XCTAssertEqual(decoded.formula?.tolerance, 0.1)
        XCTAssertEqual(decoded.formula?.expectedUnit, "N")
    }

    func testFileUploadTypeHasNoFormula() throws {
        let question = QuizQuestion(type: .fileUpload, prompt: "Upload your essay", answers: [], formula: nil)
        let data = try JSONEncoder().encode(question)
        let decoded = try JSONDecoder().decode(QuizQuestion.self, from: data)
        XCTAssertEqual(decoded.type, .fileUpload)
        XCTAssertNil(decoded.formula)
    }

    func testFormulaFieldDecodesAsNilForNonFormulaQuestions() throws {
        // Legacy JSON for an MC question shouldn't crash if it ever gains a `formula` key — the tolerant
        // decoder just ignores it for the wrong type. We assert the field is nil.
        let json = """
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "type": "multipleChoice",
          "prompt": "Pick one",
          "answers": []
        }
        """
        let decoded = try JSONDecoder().decode(QuizQuestion.self, from: Data(json.utf8))
        XCTAssertNil(decoded.formula)
    }

    func testCanvasQuestionTypeMappingsForNewTypes() {
        XCTAssertEqual(QuizQuestionType.fileUpload.canvasQuestionType, "file_upload_question")
        XCTAssertEqual(QuizQuestionType.formula.canvasQuestionType, "calculated_question")
    }

    func testDisplayNamesCoverEveryCase() {
        // Guard against a future case being added to the enum without a display name.
        for type in QuizQuestionType.allCases {
            XCTAssertFalse(type.displayName.isEmpty, "Missing display name for \(type)")
        }
    }
}
