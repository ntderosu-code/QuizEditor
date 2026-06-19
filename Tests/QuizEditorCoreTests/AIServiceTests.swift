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

    func testRequiresAPIKeyBeforeCreatingAIRequest() {
        let config = AIConfiguration(apiKey: "   ", endpoint: URL(string: "https://example.test/v1/chat/completions")!, model: "test-model")

        XCTAssertThrowsError(try AIRequestFactory().validate(config)) { error in
            XCTAssertEqual(error as? AIConfiguration.ValidationError, .missingAPIKey)
        }
    }
}
