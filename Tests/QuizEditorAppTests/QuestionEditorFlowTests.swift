import XCTest
@testable import QuizEditorApp

final class QuestionEditorFlowTests: XCTestCase {
    func testDefaultEditorOrderStartsWithAuthoringWork() {
        XCTAssertEqual(QuestionEditorSection.defaultOrder, [.type, .stem, .answer, .feedback, .checks, .details])
    }

    func testDefaultEditorOrderIncludesEveryVisibleSectionOnce() {
        XCTAssertEqual(Set(QuestionEditorSection.defaultOrder), Set(QuestionEditorSection.allCases))
    }
}
