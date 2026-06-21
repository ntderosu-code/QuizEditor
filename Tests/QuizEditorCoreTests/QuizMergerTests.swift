import XCTest
@testable import QuizEditorCore

final class QuizMergerTests: XCTestCase {
    private let merger = QuizMerger()

    private func base() -> Quiz {
        Quiz(title: "Base", questions: [
            QuizQuestion(type: .multipleChoice, prompt: "What is 2+2?",
                         answers: [QuizAnswer(text: "4", isCorrect: true)])
        ])
    }

    func testAppendsQuestionsWithoutOverwriting() {
        let incoming = [QuizQuestion(type: .essay, prompt: "Discuss entropy.")]
        let result = merger.merge(base: base(), incoming: incoming, duplicatePolicy: .keepBoth)

        XCTAssertEqual(result.merged.questions.count, 2)
        XCTAssertEqual(result.merged.questions.first?.prompt, "What is 2+2?")
        XCTAssertEqual(result.merged.title, "Base")
        XCTAssertEqual(result.addedCount, 1)
    }

    func testAppendedQuestionsGetFreshIDs() {
        let shared = QuizQuestion(type: .essay, prompt: "Same identity?",
                                  answers: [QuizAnswer(text: "x", isCorrect: true)])
        let result = merger.merge(base: base(), incoming: [shared], duplicatePolicy: .keepBoth)
        let appended = try? XCTUnwrap(result.merged.questions.last)

        XCTAssertNotEqual(appended?.id, shared.id)
        XCTAssertNotEqual(appended?.answers.first?.id, shared.answers.first?.id)
        XCTAssertEqual(appended?.answers.first?.text, "x")
        XCTAssertEqual(appended?.answers.first?.isCorrect, true)
    }

    func testSkipPolicyDropsDuplicatesByPromptAndType() {
        // Same prompt text (different formatting/case) and same type → duplicate.
        let duplicate = QuizQuestion(type: .multipleChoice, prompt: "<p>what is 2+2?</p>",
                                     answers: [QuizAnswer(text: "4", isCorrect: true)])
        let fresh = QuizQuestion(type: .essay, prompt: "New question")

        let result = merger.merge(base: base(), incoming: [duplicate, fresh], duplicatePolicy: .skip)

        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(result.merged.questions.count, 2)
    }

    func testKeepBothPolicyKeepsDuplicates() {
        let duplicate = QuizQuestion(type: .multipleChoice, prompt: "What is 2+2?",
                                     answers: [QuizAnswer(text: "4", isCorrect: true)])
        let result = merger.merge(base: base(), incoming: [duplicate], duplicatePolicy: .keepBoth)

        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(result.merged.questions.count, 2)
    }

    func testDuplicateCountPreview() {
        let incoming = [
            QuizQuestion(type: .multipleChoice, prompt: "What is 2+2?"), // dup of base
            QuizQuestion(type: .essay, prompt: "Unique"),
            QuizQuestion(type: .essay, prompt: "Unique") // dup within incoming
        ]
        XCTAssertEqual(merger.duplicateCount(base: base(), incoming: incoming), 2)
    }

    func testDifferentTypeSamePromptIsNotDuplicate() {
        let sameTextDifferentType = QuizQuestion(type: .essay, prompt: "What is 2+2?")
        let result = merger.merge(base: base(), incoming: [sameTextDifferentType], duplicatePolicy: .skip)
        XCTAssertEqual(result.addedCount, 1)
    }
}
