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
}
