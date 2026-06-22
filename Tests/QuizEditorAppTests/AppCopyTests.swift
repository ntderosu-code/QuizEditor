import XCTest
@testable import QuizEditorApp

final class AppCopyTests: XCTestCase {
    func testReviewVocabularySeparatesOfflineChecksFromAI() {
        XCTAssertEqual(AppCopy.checkQuiz, "Check Quiz")
        XCTAssertEqual(AppCopy.aiSuggestions, "AI Suggestions")
        XCTAssertEqual(AppCopy.offlineChecks, "Offline checks")
    }
}
