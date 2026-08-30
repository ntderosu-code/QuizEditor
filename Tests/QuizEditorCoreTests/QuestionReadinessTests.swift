import XCTest
@testable import QuizEditorCore

final class QuestionReadinessTests: XCTestCase {
    private func mc(
        prompt: String = "What is 2 + 2?",
        answers: [QuizAnswer] = [
            QuizAnswer(text: "4", isCorrect: true),
            QuizAnswer(text: "3", isCorrect: false),
            QuizAnswer(text: "5", isCorrect: false)
        ],
        feedback: String = "Four is the sum.",
        type: QuizQuestionType = .multipleChoice
    ) -> QuizQuestion {
        QuizQuestion(type: type, prompt: prompt, answers: answers, feedback: feedback)
    }

    private func check(_ r: QuestionReadiness, _ id: String) -> ReadinessCheck? {
        r.checks.first { $0.id == id }
    }

    func testWellFormedMultipleChoiceIsReady() {
        let r = QuestionReadiness(question: mc())
        XCTAssertEqual(r.status, .ready)
        XCTAssertTrue(r.checks.allSatisfy { $0.isSatisfied })
    }

    func testMissingStemIsDraft() {
        let r = QuestionReadiness(question: mc(prompt: "   "))
        XCTAssertEqual(r.status, .draft)
        XCTAssertEqual(check(r, "stem")?.severity, .required)
    }

    func testNoCorrectAnswerIsRequiredProblem() {
        let r = QuestionReadiness(question: mc(answers: [
            QuizAnswer(text: "4", isCorrect: false),
            QuizAnswer(text: "3", isCorrect: false)
        ]))
        XCTAssertEqual(check(r, "key")?.severity, .required)
        XCTAssertEqual(r.status, .needsWork)
    }

    func testMoreThanOneCorrectInSingleSelectIsRequiredProblem() {
        let r = QuestionReadiness(question: mc(answers: [
            QuizAnswer(text: "4", isCorrect: true),
            QuizAnswer(text: "5", isCorrect: true)
        ]))
        XCTAssertEqual(check(r, "key")?.severity, .required)
    }

    func testMultipleAnswerAllowsSeveralCorrect() {
        let r = QuestionReadiness(question: mc(answers: [
            QuizAnswer(text: "4", isCorrect: true),
            QuizAnswer(text: "Four", isCorrect: true),
            QuizAnswer(text: "3", isCorrect: false)
        ], type: .multipleAnswer))
        XCTAssertEqual(check(r, "key")?.severity, .ok)
    }

    func testDuplicateAnswerTextIsRequiredProblem() {
        let r = QuestionReadiness(question: mc(answers: [
            QuizAnswer(text: "4", isCorrect: true),
            QuizAnswer(text: "4", isCorrect: false),
            QuizAnswer(text: "5", isCorrect: false)
        ]))
        XCTAssertEqual(check(r, "duplicates")?.severity, .required)
    }

    func testBlankAnswerChoiceIsRequiredProblem() {
        let r = QuestionReadiness(question: mc(answers: [
            QuizAnswer(text: "4", isCorrect: true),
            QuizAnswer(text: "  ", isCorrect: false)
        ]))
        XCTAssertEqual(check(r, "blanks")?.severity, .required)
    }

    func testFewerThanTwoChoicesIsRequiredProblem() {
        let r = QuestionReadiness(question: mc(answers: [
            QuizAnswer(text: "4", isCorrect: true)
        ]))
        XCTAssertEqual(check(r, "choices")?.severity, .required)
    }

    func testMissingFeedbackIsRecommendedNotRequired() {
        let r = QuestionReadiness(question: mc(feedback: ""))
        XCTAssertEqual(check(r, "feedback")?.severity, .recommended)
        XCTAssertEqual(r.status, .needsWork)
    }

    func testEssayNeedsNoAnswerKey() {
        let q = QuizQuestion(type: .essay, prompt: "Discuss osmosis.", answers: [], feedback: "Look for the gradient explanation.")
        let r = QuestionReadiness(question: q)
        XCTAssertEqual(r.status, .ready)
        XCTAssertNil(check(r, "key"))
        XCTAssertNil(check(r, "choices"))
    }

    func testNumericNeedsAConfiguredSpec() {
        let unconfigured = QuizQuestion(type: .numeric, prompt: "Compute the pH.", feedback: "Use -log[H+].")
        let r = QuestionReadiness(question: unconfigured)
        XCTAssertEqual(check(r, "numeric")?.severity, .required)
    }

    // MARK: - Surveys

    func testSurveyQuestionWithNoKeyOrFeedbackIsReady() {
        // A survey has nothing to grade, so the answer-key and feedback checks
        // do not apply. The item is still expected to have a stem and choices.
        let opinion = mc(
            answers: [
                QuizAnswer(text: "Strongly agree", isCorrect: false),
                QuizAnswer(text: "Neutral", isCorrect: false),
                QuizAnswer(text: "Strongly disagree", isCorrect: false)
            ],
            feedback: ""
        )
        XCTAssertEqual(QuestionReadiness(question: opinion).status, .needsWork)

        let survey = QuestionReadiness(question: opinion, kind: .survey)
        XCTAssertEqual(survey.status, .ready)
        XCTAssertNil(check(survey, "key"))
        XCTAssertNil(check(survey, "feedback"))
    }

    func testSurveyStillRequiresAStemAndChoices() {
        let noStem = QuestionReadiness(question: mc(prompt: "  ", feedback: ""), kind: .survey)
        XCTAssertEqual(noStem.status, .draft)

        let oneChoice = QuestionReadiness(
            question: mc(answers: [QuizAnswer(text: "Yes", isCorrect: false)], feedback: ""),
            kind: .survey
        )
        XCTAssertEqual(check(oneChoice, "choices")?.severity, .required)
    }

    func testSurveyNumericAndFormulaItemsNeedNoAnswerKey() {
        let numeric = QuizQuestion(type: .numeric, prompt: "How many hours do you study?", feedback: "")
        XCTAssertEqual(QuestionReadiness(question: numeric, kind: .survey).status, .ready)

        let formula = QuizQuestion(type: .formula, prompt: "Estimate your commute.", feedback: "")
        XCTAssertEqual(QuestionReadiness(question: formula, kind: .survey).status, .ready)
    }

    func testMatchingNeedsAtLeastTwoPairs() {
        let q = QuizQuestion(type: .matching, prompt: "Match capitals.", matches: [
            MatchingPair(prompt: "France", match: "Paris")
        ], feedback: "Capitals.")
        let r = QuestionReadiness(question: q)
        XCTAssertEqual(check(r, "pairs")?.severity, .required)
    }
}
