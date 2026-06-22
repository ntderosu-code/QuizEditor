import XCTest
@testable import QuizEditorCore

/// The whole-quiz review analyzes a page of questions in one request that returns
/// a JSON array of per-question reviews. `parseBatch` maps each array element to
/// its question by index and aligns revised fields, preserving answer count and
/// correctness — exactly like the single-question parser.
final class BatchReviewTests: XCTestCase {
    private let service = QuestionReviewService()

    private func mc(_ prompt: String, _ options: [(String, Bool)]) -> QuizQuestion {
        QuizQuestion(
            type: .multipleChoice,
            prompt: prompt,
            answers: options.map { QuizAnswer(text: $0.0, isCorrect: $0.1) },
            feedback: ""
        )
    }

    func testParseBatchReturnsOneReviewPerQuestionInOrder() {
        let originals = [
            mc("Q1", [("A", true), ("B", false)]),
            mc("Q2", [("C", true), ("D", false)])
        ]
        let raw = """
        [
          {"index": 0, "summary": "First looks fine.", "suggestions": []},
          {"index": 1, "summary": "Second is clear.", "suggestions": ["tighten wording"]}
        ]
        """
        let reviews = service.parseBatch(raw, originals: originals)
        XCTAssertEqual(reviews.count, 2)
        XCTAssertEqual(reviews[0].summary, "First looks fine.")
        XCTAssertEqual(reviews[1].summary, "Second is clear.")
        XCTAssertEqual(reviews[1].suggestions, ["tighten wording"])
    }

    func testParseBatchAlignsRevisedAnswersToTheRightQuestion() {
        let originals = [
            mc("What is 2+2?", [("Four", true), ("Five", false)]),
            mc("Capital of France?", [("Paris", true), ("Lyon", false)])
        ]
        // Only the second question gets a revised prompt and rewritten options.
        let raw = """
        [
          {"index": 0, "summary": "ok"},
          {"index": 1, "summary": "reworded",
           "revised": {"prompt": "Which city is the capital of France?",
                       "answers": ["Paris, France", "Lyon, France"]}}
        ]
        """
        let reviews = service.parseBatch(raw, originals: originals)
        XCTAssertNil(reviews[0].revisedPrompt)
        XCTAssertEqual(reviews[1].revisedPrompt, "Which city is the capital of France?")
        // Count preserved and correctness untouched (Paris stays correct).
        XCTAssertEqual(reviews[1].revisedAnswers?.count, 2)
        XCTAssertEqual(reviews[1].revisedAnswers?[0].text, "Paris, France")
        XCTAssertEqual(reviews[1].revisedAnswers?[0].isCorrect, true)
        XCTAssertEqual(reviews[1].revisedAnswers?[1].isCorrect, false)
    }

    func testParseBatchFillsOmittedQuestionsWithCleanReview() {
        let originals = [
            mc("Q1", [("A", true), ("B", false)]),
            mc("Q2", [("C", true), ("D", false)]),
            mc("Q3", [("E", true), ("F", false)])
        ]
        // Model only returned a review for index 1.
        let raw = """
        [ {"index": 1, "summary": "middle one needs work", "suggestions": ["fix stem"]} ]
        """
        let reviews = service.parseBatch(raw, originals: originals)
        XCTAssertEqual(reviews.count, 3)
        XCTAssertFalse(reviews[0].hasRevisions)
        XCTAssertEqual(reviews[1].summary, "middle one needs work")
        XCTAssertFalse(reviews[2].hasRevisions)
    }

    func testParseBatchMalformedJSONYieldsCleanReviewPerQuestion() {
        let originals = [
            mc("Q1", [("A", true), ("B", false)]),
            mc("Q2", [("C", true), ("D", false)])
        ]
        let reviews = service.parseBatch("the model said something that isn't JSON", originals: originals)
        XCTAssertEqual(reviews.count, 2)
        XCTAssertFalse(reviews[0].hasRevisions)
        XCTAssertFalse(reviews[1].hasRevisions)
    }

    func testBatchPromptListsEveryQuestionAndAsksForArray() {
        let originals = [mc("Alpha question", [("A", true)]), mc("Beta question", [("B", true)])]
        let prompt = service.makeBatchPrompt(questions: originals, quizTitle: "Sample")
        XCTAssertTrue(prompt.contains("Alpha question"))
        XCTAssertTrue(prompt.contains("Beta question"))
        // Asks for a JSON array keyed by index.
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("array"))
        XCTAssertTrue(prompt.contains("index"))
    }
}
