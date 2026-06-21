import XCTest
@testable import QuizEditorCore

final class QuestionLinterTests: XCTestCase {
    private let linter = QuestionLinter()

    private func rules(_ findings: [LintFinding]) -> Set<LintFinding.Rule> {
        Set(findings.map(\.rule))
    }

    func testCleanQuestionHasNoFindings() {
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "Which planet is closest to the Sun?",
            answers: [
                QuizAnswer(text: "Mercury", isCorrect: true),
                QuizAnswer(text: "Venus", isCorrect: false),
                QuizAnswer(text: "Earth", isCorrect: false)
            ],
            feedback: "Mercury orbits nearest the Sun."
        )
        XCTAssertEqual(linter.findings(for: question), [])
    }

    func testFlagsNoCorrectAnswer() {
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "Pick one.",
            answers: [
                QuizAnswer(text: "A", isCorrect: false),
                QuizAnswer(text: "B", isCorrect: false)
            ],
            feedback: "x"
        )
        XCTAssertTrue(rules(linter.findings(for: question)).contains(.noCorrectAnswer))
    }

    func testFlagsMultipleCorrectOnSingleSelect() {
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "Pick one.",
            answers: [
                QuizAnswer(text: "A", isCorrect: true),
                QuizAnswer(text: "B", isCorrect: true)
            ],
            feedback: "x"
        )
        let found = linter.findings(for: question)
        XCTAssertTrue(rules(found).contains(.multipleCorrectAnswers))
        XCTAssertEqual(found.first?.severity, .warning)
    }

    func testMultipleAnswerAllowsMultipleCorrect() {
        let question = QuizQuestion(
            type: .multipleAnswer,
            prompt: "Select all primes.",
            answers: [
                QuizAnswer(text: "2", isCorrect: true),
                QuizAnswer(text: "3", isCorrect: true),
                QuizAnswer(text: "4", isCorrect: false)
            ],
            feedback: "2 and 3 are prime."
        )
        XCTAssertFalse(rules(linter.findings(for: question)).contains(.multipleCorrectAnswers))
        XCTAssertFalse(rules(linter.findings(for: question)).contains(.noCorrectAnswer))
    }

    func testFlagsAllOfTheAbove() {
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "Which are mammals?",
            answers: [
                QuizAnswer(text: "Dogs", isCorrect: false),
                QuizAnswer(text: "Cats", isCorrect: false),
                QuizAnswer(text: "All of the above", isCorrect: true)
            ],
            feedback: "All listed are mammals."
        )
        XCTAssertTrue(rules(linter.findings(for: question)).contains(.allOrNoneOfTheAbove))
    }

    func testFlagsUnemphasizedNegativeStem() {
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "Which of these is not a prime number?",
            answers: [
                QuizAnswer(text: "2", isCorrect: false),
                QuizAnswer(text: "4", isCorrect: true),
                QuizAnswer(text: "3", isCorrect: false)
            ],
            feedback: "4 is composite."
        )
        XCTAssertTrue(rules(linter.findings(for: question)).contains(.unemphasizedNegativeStem))
    }

    func testUppercaseNegativeStemIsNotFlagged() {
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "Which of these is NOT a prime number?",
            answers: [
                QuizAnswer(text: "2", isCorrect: false),
                QuizAnswer(text: "4", isCorrect: true),
                QuizAnswer(text: "3", isCorrect: false)
            ],
            feedback: "4 is composite."
        )
        XCTAssertFalse(rules(linter.findings(for: question)).contains(.unemphasizedNegativeStem))
    }

    func testBoldNegativeStemIsNotFlagged() {
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "<p>Which of these is <strong>not</strong> a prime number?</p>",
            answers: [
                QuizAnswer(text: "2", isCorrect: false),
                QuizAnswer(text: "4", isCorrect: true),
                QuizAnswer(text: "3", isCorrect: false)
            ],
            feedback: "4 is composite."
        )
        XCTAssertFalse(rules(linter.findings(for: question)).contains(.unemphasizedNegativeStem))
    }

    func testFlagsLengthBiasWhenCorrectIsLongest() {
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "What is osmosis?",
            answers: [
                QuizAnswer(text: "The diffusion of water across a selectively permeable membrane from low to high solute concentration", isCorrect: true),
                QuizAnswer(text: "Active pumping", isCorrect: false),
                QuizAnswer(text: "Cell division", isCorrect: false)
            ],
            feedback: "Osmosis is passive."
        )
        XCTAssertTrue(rules(linter.findings(for: question)).contains(.longestOptionIsCorrect))
    }

    func testDoesNotFlagLengthBiasWhenLengthsAreBalanced() {
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "Capital of France?",
            answers: [
                QuizAnswer(text: "Paris", isCorrect: true),
                QuizAnswer(text: "Lyon", isCorrect: false),
                QuizAnswer(text: "Nice", isCorrect: false)
            ],
            feedback: "Paris is the capital."
        )
        XCTAssertFalse(rules(linter.findings(for: question)).contains(.longestOptionIsCorrect))
    }

    func testFlagsDuplicateAndEmptyOptions() {
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "Pick one.",
            answers: [
                QuizAnswer(text: "Apple", isCorrect: true),
                QuizAnswer(text: "apple", isCorrect: false),
                QuizAnswer(text: "   ", isCorrect: false)
            ],
            feedback: "x"
        )
        let found = rules(linter.findings(for: question))
        XCTAssertTrue(found.contains(.duplicateOptions))
        XCTAssertTrue(found.contains(.emptyOption))
    }

    func testFlagsMissingFeedback() {
        let question = QuizQuestion(
            type: .essay,
            prompt: "Explain mitosis.",
            feedback: ""
        )
        XCTAssertTrue(rules(linter.findings(for: question)).contains(.missingFeedback))
    }

    func testFlagsArticleCueAtEndOfStem() {
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "The powerhouse of the cell is an ___",
            answers: [
                QuizAnswer(text: "mitochondrion", isCorrect: true),
                QuizAnswer(text: "ribosome", isCorrect: false),
                QuizAnswer(text: "nucleus", isCorrect: false)
            ],
            feedback: "It produces ATP."
        )
        XCTAssertTrue(rules(linter.findings(for: question)).contains(.articleCue))
    }

    func testEssayIsNotFlaggedForMissingAnswerKey() {
        let question = QuizQuestion(type: .essay, prompt: "Discuss.", feedback: "Look for a thesis.")
        XCTAssertFalse(rules(linter.findings(for: question)).contains(.noCorrectAnswer))
    }

    func testQuizLevelFindingsOmitCleanQuestions() {
        let clean = QuizQuestion(
            type: .trueFalse,
            prompt: "The sky is blue.",
            answers: [QuizAnswer(text: "True", isCorrect: true), QuizAnswer(text: "False", isCorrect: false)],
            feedback: "Rayleigh scattering."
        )
        let broken = QuizQuestion(
            type: .multipleChoice,
            prompt: "Pick one.",
            answers: [QuizAnswer(text: "A", isCorrect: false)],
            feedback: ""
        )
        let quiz = Quiz(title: "Mixed", questions: [clean, broken])

        let byQuestion = linter.findings(for: quiz)
        XCTAssertNil(byQuestion[clean.id])
        XCTAssertNotNil(byQuestion[broken.id])
    }
}
