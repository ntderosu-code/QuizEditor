import XCTest
@testable import QuizEditorCore

final class FormattedDocumentTests: XCTestCase {
    private let quiz = Quiz(
        title: "Cell Biology & Cells",
        questions: [
            QuizQuestion(
                type: .multipleChoice,
                prompt: "<p>Which organelle makes <strong>ATP</strong>?</p>",
                answers: [
                    QuizAnswer(text: "Mitochondrion", isCorrect: true),
                    QuizAnswer(text: "Ribosome", isCorrect: false)
                ],
                feedback: "<p>The mitochondrion.</p>"
            ),
            QuizQuestion(
                type: .matching,
                prompt: "Match the capital.",
                matches: [MatchingPair(prompt: "France", match: "Paris")]
            )
        ]
    )

    func testFullDocumentIsWellFormedAndContainsContent() throws {
        let doc = FormattedDocumentBuilder().document(for: quiz)

        XCTAssertTrue(doc.hasPrefix("<!DOCTYPE html>"))
        // Title is escaped.
        XCTAssertTrue(doc.contains("Cell Biology &amp; Cells"))
        // Rich prompt HTML is embedded as-is.
        XCTAssertTrue(doc.contains("<strong>ATP</strong>"))
        // Correct answer is marked with a textual tag and bold styling (no decorative
        // checkmark glyph, which screen readers don't announce reliably).
        XCTAssertFalse(doc.contains("\u{2713}"))
        XCTAssertTrue(doc.contains("(correct)"))
        XCTAssertTrue(doc.contains("Mitochondrion"))
        // Matching renders as a table.
        XCTAssertTrue(doc.contains("France"))
        XCTAssertTrue(doc.contains("Paris"))
        // Feedback shown when answer key is included.
        XCTAssertTrue(doc.contains("Feedback:"))
    }

    func testAnswerKeyCanBeHidden() {
        let doc = FormattedDocumentBuilder().document(for: quiz, showAnswerKey: false)
        XCTAssertFalse(doc.contains("(correct)"))
        XCTAssertFalse(doc.contains("Feedback:"))
        // The blank matching target appears instead of the answer.
        XCTAssertFalse(doc.contains("Paris"))
    }

    func testSingleQuestionDocument() {
        let doc = FormattedDocumentBuilder().document(for: quiz.questions[0], number: 3)
        XCTAssertTrue(doc.contains(">3<"))
        XCTAssertTrue(doc.contains("<strong>ATP</strong>"))
    }
}
