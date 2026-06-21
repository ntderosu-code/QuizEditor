import XCTest
@testable import QuizEditorCore

final class QuestionAuthoringServiceTests: XCTestCase {
    private let service = QuestionAuthoringService()

    func testParsesGeneratedMultipleChoiceQuestions() {
        let raw = """
        {
          "questions": [
            {
              "type": "multipleChoice",
              "prompt": "Which gas do plants absorb?",
              "answers": [
                {"text": "Carbon dioxide", "correct": true},
                {"text": "Oxygen", "correct": false},
                {"text": "Nitrogen", "correct": false}
              ],
              "feedback": "Plants absorb CO2 for photosynthesis."
            }
          ]
        }
        """
        let questions = service.parseGeneratedQuestions(raw)

        XCTAssertEqual(questions.count, 1)
        XCTAssertEqual(questions.first?.type, .multipleChoice)
        XCTAssertEqual(questions.first?.prompt, "Which gas do plants absorb?")
        XCTAssertEqual(questions.first?.answers.count, 3)
        XCTAssertEqual(questions.first?.answers.first?.isCorrect, true)
        XCTAssertFalse(questions.first?.feedback.isEmpty ?? true)
    }

    func testParsesMatchingQuestionsAndToleratesProse() {
        let raw = """
        Sure! Here are your questions:
        ```json
        {
          "questions": [
            {
              "type": "matching_question",
              "prompt": "Match the capital.",
              "matches": [
                {"term": "France", "match": "Paris"},
                {"term": "Japan", "match": "Tokyo"}
              ],
              "feedback": "Capitals."
            }
          ]
        }
        ```
        """
        let questions = service.parseGeneratedQuestions(raw)

        XCTAssertEqual(questions.count, 1)
        XCTAssertEqual(questions.first?.type, .matching)
        XCTAssertEqual(questions.first?.matches.count, 2)
        XCTAssertEqual(questions.first?.matches.first?.prompt, "France")
        XCTAssertEqual(questions.first?.matches.first?.match, "Paris")
    }

    func testMapsHumanReadableTypeNames() {
        let raw = """
        { "questions": [ { "type": "True/False", "prompt": "The sky is blue.",
          "answers": [{"text":"True","correct":true},{"text":"False","correct":false}] } ] }
        """
        XCTAssertEqual(service.parseGeneratedQuestions(raw).first?.type, .trueFalse)
    }

    func testInvalidOutputYieldsNoQuestions() {
        XCTAssertEqual(service.parseGeneratedQuestions("I cannot help with that."), [])
    }

    func testParsesDistractorsFromObject() {
        let raw = """
        { "distractors": ["The cell wall", "The nucleus", "  "] }
        """
        XCTAssertEqual(service.parseDistractors(raw), ["The cell wall", "The nucleus"])
    }

    func testParsesDistractorsFromBareArray() {
        XCTAssertEqual(service.parseDistractors("[\"alpha\", \"beta\"]"), ["alpha", "beta"])
    }

    func testParsesFeedbackObjectAndFallsBackToPlainText() {
        XCTAssertEqual(service.parseFeedback("{ \"feedback\": \"Because CO2.\" }"), "Because CO2.")
        XCTAssertEqual(service.parseFeedback("Just plain text feedback."), "Just plain text feedback.")
    }

    func testGenerationPromptMentionsTopicAndCount() {
        let prompt = service.makeGenerationPrompt(topic: "Photosynthesis", count: 3, types: [.multipleChoice])
        XCTAssertTrue(prompt.contains("Photosynthesis"))
        XCTAssertTrue(prompt.contains("3"))
        XCTAssertTrue(prompt.contains("multipleChoice"))
    }
}
