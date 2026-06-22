import XCTest
@testable import QuizEditorCore

final class AIServiceTests: XCTestCase {
    func testBuildsReviewMessagesWithQuizContextAndAccessibilityInstruction() throws {
        let quiz = Quiz.sample

        let request = AIRequestFactory().makeRequest(
            feature: .review,
            quiz: quiz,
            userInstruction: "Check for ambiguous wording.",
            configuration: AIConfiguration(apiKey: "test-key", endpoint: URL(string: "https://example.test/v1/chat/completions")!, model: "test-model")
        )

        XCTAssertEqual(request.url?.absoluteString, "https://example.test/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertTrue(body.contains("test-model"))
        XCTAssertTrue(body.contains("AI review"))
        XCTAssertTrue(body.contains("WCAG"))
        XCTAssertTrue(body.contains("Check for ambiguous wording."))
        XCTAssertTrue(body.contains(quiz.title))
    }

    // MARK: - Token-budget batching (for on-device models)

    private func makeQuiz(questionCount: Int) -> Quiz {
        let questions = (1...questionCount).map { index in
            QuizQuestion(
                type: .multipleChoice,
                prompt: "Question number \(index): which option is correct?",
                answers: [
                    QuizAnswer(text: "Correct option \(index)", isCorrect: true),
                    QuizAnswer(text: "Wrong option \(index)", isCorrect: false)
                ],
                feedback: "Feedback for question \(index)."
            )
        }
        return Quiz(title: "Batching Quiz", questions: questions)
    }

    func testBatchedReturnsSingleBatchWhenQuizFitsBudget() {
        let quiz = makeQuiz(questionCount: 3)
        let batches = quiz.batched(maxCharacters: 10_000)

        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches.first?.questions.count, 3)
        XCTAssertEqual(batches.first?.title, quiz.title)
    }

    func testBatchedSplitsLargeQuizAndKeepsEveryQuestionInOrder() {
        let quiz = makeQuiz(questionCount: 12)
        let batches = quiz.batched(maxCharacters: 300)

        // Every batch (except possibly a lone oversized question) stays within budget.
        for batch in batches where batch.questions.count > 1 {
            XCTAssertLessThanOrEqual(batch.markedTextRepresentation.count, 300)
        }

        // No question is lost, duplicated, or reordered.
        let rebuilt = batches.flatMap(\.questions).map(\.id)
        XCTAssertEqual(rebuilt, quiz.questions.map(\.id))
        XCTAssertGreaterThan(batches.count, 1)
    }

    func testBatchedKeepsAnOversizedQuestionWholeInItsOwnBatch() {
        let quiz = makeQuiz(questionCount: 2)
        // A budget smaller than any single question forces one question per batch
        // rather than splitting a question apart.
        let batches = quiz.batched(maxCharacters: 1)

        XCTAssertEqual(batches.count, 2)
        XCTAssertTrue(batches.allSatisfy { $0.questions.count == 1 })
    }

    func testBatchedReturnsNothingForAnEmptyQuiz() {
        let quiz = Quiz(title: "Empty", questions: [])
        XCTAssertTrue(quiz.batched(maxCharacters: 4000).isEmpty)
    }

    func testRequiresAPIKeyBeforeCreatingAIRequest() {
        let config = AIConfiguration(apiKey: "   ", endpoint: URL(string: "https://example.test/v1/chat/completions")!, model: "test-model")

        XCTAssertThrowsError(try AIRequestFactory().validate(config)) { error in
            XCTAssertEqual(error as? AIConfiguration.ValidationError, .missingAPIKey)
        }
    }
}
