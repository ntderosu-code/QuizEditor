import XCTest
@testable import QuizEditorCore

final class PaperExamBuilderTests: XCTestCase {
    private let quiz = Quiz(
        title: "Biology Midterm",
        questions: [
            QuizQuestion(
                type: .multipleChoice,
                prompt: "<p>Which organelle makes <strong>ATP</strong>?</p>",
                answers: [
                    QuizAnswer(text: "Mitochondrion", isCorrect: true),
                    QuizAnswer(text: "Ribosome", isCorrect: false)
                ],
                feedback: "<p>The mitochondrion.</p>",
                points: 2
            ),
            QuizQuestion(
                type: .shortAnswer,
                prompt: "Name the genetic molecule.",
                answers: [QuizAnswer(text: "DNA", isCorrect: true)],
                points: 1
            ),
            QuizQuestion(type: .essay, prompt: "Explain osmosis.", points: 5),
            QuizQuestion(
                type: .matching,
                prompt: "Match capital to country.",
                matches: [
                    MatchingPair(prompt: "France", match: "Paris"),
                    MatchingPair(prompt: "Japan", match: "Tokyo")
                ],
                points: 4
            )
        ]
    )

    private let builder = PaperExamBuilder()

    func testStudentCopyRendersHeaderFields() {
        let doc = builder.document(for: quiz, options: PaperExamOptions(includeAnswerKey: false))
        XCTAssertTrue(doc.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(doc.contains(">Name<"))
        XCTAssertTrue(doc.contains(">Date<"))
        XCTAssertTrue(doc.contains("Course / Section"))
        XCTAssertTrue(doc.contains(">Score<"))
        // Score is out of the total points (2 + 1 + 5 + 4 = 12).
        XCTAssertTrue(doc.contains("/ 12"))
    }

    func testStudentCopyHasNoAnswerLeakage() {
        let doc = builder.document(for: quiz, options: PaperExamOptions(includeAnswerKey: false))
        XCTAssertFalse(doc.contains("(correct)"))
        XCTAssertFalse(doc.contains("bubble filled"))
        XCTAssertFalse(doc.contains("Answer:"))
        XCTAssertFalse(doc.contains("Feedback:"))
        // The short-answer key text must not appear in the blank copy.
        XCTAssertFalse(doc.contains(">DNA<") || doc.contains("Answer:</span> DNA"))
        // The prompt itself is still shown.
        XCTAssertTrue(doc.contains("<strong>ATP</strong>"))
    }

    func testAnswerKeyCopyMarksCorrectAnswers() {
        let doc = builder.document(for: quiz, options: PaperExamOptions(includeAnswerKey: true))
        XCTAssertTrue(doc.contains("ANSWER KEY"))
        XCTAssertTrue(doc.contains("(correct)"))
        XCTAssertTrue(doc.contains("bubble filled"))
        // Short-answer accepted answer appears.
        XCTAssertTrue(doc.contains("DNA"))
        // Feedback appears in the key copy.
        XCTAssertTrue(doc.contains("Feedback:"))
    }

    func testPerQuestionPointsShownAndHideable() {
        let withPoints = builder.document(for: quiz, options: PaperExamOptions(showPoints: true))
        XCTAssertTrue(withPoints.contains("2 pts"))
        XCTAssertTrue(withPoints.contains("1 pt"))

        let withoutPoints = builder.document(for: quiz, options: PaperExamOptions(showPoints: false))
        XCTAssertFalse(withoutPoints.contains("pts)"))
        // Score field falls back to the question count when points are hidden.
        XCTAssertTrue(withoutPoints.contains("/ 4"))
    }

    func testPageBreakCSSPreventsMidQuestionSplits() {
        let doc = builder.document(for: quiz)
        XCTAssertTrue(doc.contains("break-inside: avoid"))
        XCTAssertTrue(doc.contains("page-break-inside: avoid"))
    }

    func testInstructionsAndVersionLabelRender() {
        let doc = builder.document(for: quiz, options: PaperExamOptions(
            instructions: "No calculators.",
            versionLabel: "Version A"
        ))
        XCTAssertTrue(doc.contains("Instructions:"))
        XCTAssertTrue(doc.contains("No calculators."))
        XCTAssertTrue(doc.contains("Version A"))
    }

    func testMatchingBankDoesNotLeakRowAlignment() {
        // The choices bank is sorted alphabetically (Paris, Tokyo), independent of
        // the term order, so a student can't pair by row position.
        let doc = builder.document(for: quiz, options: PaperExamOptions(includeAnswerKey: false))
        XCTAssertTrue(doc.contains("Choices:"))
        let parisIndex = doc.range(of: "Paris")?.lowerBound
        let tokyoIndex = doc.range(of: "Tokyo")?.lowerBound
        XCTAssertNotNil(parisIndex)
        XCTAssertNotNil(tokyoIndex)
    }
}
