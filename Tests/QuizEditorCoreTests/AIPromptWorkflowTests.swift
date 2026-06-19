import XCTest
@testable import QuizEditorCore

final class AIPromptWorkflowTests: XCTestCase {
    func testBuildsCopyPastePromptForWebChatServices() {
        let prompt = AIPromptBuilder().makePrompt(
            feature: .review,
            quiz: .sample,
            userInstruction: "Focus on weak distractors."
        )

        XCTAssertTrue(prompt.contains("Paste the full response back into Quiz Editor"))
        XCTAssertTrue(prompt.contains("Focus on weak distractors."))
        XCTAssertTrue(prompt.contains("WCAG"))
        XCTAssertTrue(prompt.contains(Quiz.sample.title))
    }

    func testFoundationModelsProviderIsAdvertisedAsLocalWhenAvailable() {
        XCTAssertEqual(AIProvider.foundationModels.displayName, "Apple Foundation Models")
        XCTAssertFalse(AIProvider.foundationModels.requiresAPIKey)
    }
}
