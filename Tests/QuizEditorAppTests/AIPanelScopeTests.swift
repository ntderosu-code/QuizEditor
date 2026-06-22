import XCTest
@testable import QuizEditorApp

final class AIPanelScopeTests: XCTestCase {
    func testScopesPutWholeQuizBeforeCurrentQuestion() {
        XCTAssertEqual(AIPanelScope.allCases, [.wholeQuiz, .currentQuestion])
    }

    func testScopeLabelsUsePlainUserFacingTerms() {
        XCTAssertEqual(AIPanelScope.wholeQuiz.title, "Whole quiz")
        XCTAssertEqual(AIPanelScope.currentQuestion.title, "Current question")
    }

    func testCurrentQuestionSectionTitleUsesSelectedQuestionNumberWhenAvailable() {
        XCTAssertEqual(AIPanelScope.currentQuestion.sectionTitle(selectedQuestionNumber: 4), "Question 4")
        XCTAssertEqual(AIPanelScope.currentQuestion.sectionTitle(selectedQuestionNumber: nil), "Current question")
    }
}
