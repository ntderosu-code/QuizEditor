import XCTest
@testable import QuizEditorCore

final class QuestionReviewServiceTests: XCTestCase {
    private let sampleQuestion = QuizQuestion(
        type: .multipleChoice,
        prompt: "Which is biggest?",
        answers: [
            QuizAnswer(text: "Elephant", isCorrect: true),
            QuizAnswer(text: "Mouse", isCorrect: false)
        ],
        feedback: "Elephants are large."
    )

    func testParsesPerFieldRevisions() {
        let raw = """
        {
          "summary": "The stem is vague and option lengths are uneven.",
          "suggestions": ["Clarify the comparison criterion.", "Balance option length."],
          "revised": {
            "prompt": "Which land animal has the greatest body mass?",
            "answers": [
              {"text": "African elephant", "correct": true},
              {"text": "House mouse", "correct": false}
            ],
            "feedback": "The African elephant is the largest living land animal."
          }
        }
        """

        let review = QuestionReviewService().parse(raw, original: sampleQuestion)

        XCTAssertTrue(review.summary.contains("vague"))
        XCTAssertEqual(review.suggestions.count, 2)
        XCTAssertEqual(review.revisedPrompt, "Which land animal has the greatest body mass?")
        XCTAssertEqual(review.revisedAnswers?.map(\.text), ["African elephant", "House mouse"])
        XCTAssertEqual(review.revisedAnswers?.map(\.isCorrect), [true, false])
        XCTAssertNotNil(review.revisedFeedback)
        XCTAssertNil(review.revisedMatches)
        XCTAssertTrue(review.hasRevisions)
    }

    func testOmittedFieldsStayNil() {
        let raw = """
        {
          "summary": "Only the feedback needs work.",
          "suggestions": ["Explain why the distractor is wrong."],
          "revised": { "feedback": "Elephants outweigh mice by orders of magnitude." }
        }
        """

        let review = QuestionReviewService().parse(raw, original: sampleQuestion)

        XCTAssertNil(review.revisedPrompt)
        XCTAssertNil(review.revisedAnswers)
        XCTAssertEqual(review.revisedFeedback, "Elephants outweigh mice by orders of magnitude.")
        XCTAssertTrue(review.hasRevisions)
    }

    func testNoRevisedObjectMeansReviewOnly() {
        let raw = """
        { "summary": "This question already follows the guidelines.", "suggestions": [] }
        """

        let review = QuestionReviewService().parse(raw, original: sampleQuestion)

        XCTAssertFalse(review.hasRevisions)
        XCTAssertTrue(review.suggestions.isEmpty)
    }

    func testToleratesCodeFencesAndSurroundingProse() {
        let raw = """
        Here is my review:
        ```json
        { "summary": "Tighten the stem.", "revised": { "prompt": "Which animal is heaviest?" } }
        ```
        Hope that helps!
        """

        let review = QuestionReviewService().parse(raw, original: sampleQuestion)

        XCTAssertEqual(review.summary, "Tighten the stem.")
        XCTAssertEqual(review.revisedPrompt, "Which animal is heaviest?")
    }

    func testUnparseableOutputFallsBackToRawSummary() {
        let raw = "The model is unavailable on this Mac."

        let review = QuestionReviewService().parse(raw, original: sampleQuestion)

        XCTAssertEqual(review.summary, "The model is unavailable on this Mac.")
        XCTAssertFalse(review.hasRevisions)
    }

    func testMalformedJSONNeverShowsRawBracesToTheUser() {
        // A response that looks like JSON but doesn't decode must not be dumped to
        // the user as raw braces; it should read as a friendly, plain-language summary.
        let raw = """
        { "summary": "Tighten the stem", "revised": { "prompt": "oops unterminated
        """

        let review = QuestionReviewService().parse(raw, original: sampleQuestion)

        XCTAssertFalse(review.summary.contains("{"))
        XCTAssertFalse(review.summary.contains("\"summary\""))
        XCTAssertFalse(review.hasRevisions)
    }

    func testRevisionEqualToOriginalIsNotOfferedAsAnEdit() {
        // Guided generation always returns every field, so a "revised" value that
        // matches the original must not surface as a no-op diff.
        let raw = """
        {
          "summary": "Looks good.",
          "revised": { "prompt": "Which is biggest?", "feedback": "Elephants are large." }
        }
        """

        let review = QuestionReviewService().parse(raw, original: sampleQuestion)

        XCTAssertNil(review.revisedPrompt)
        XCTAssertNil(review.revisedFeedback)
        XCTAssertFalse(review.hasRevisions)
    }

    func testRewritesAnswersInPlacePreservingCountIdsAndCorrectness() {
        let original = QuizQuestion(
            type: .multipleChoice,
            prompt: "Pick one.",
            answers: [
                QuizAnswer(text: "first", isCorrect: false),
                QuizAnswer(text: "second", isCorrect: true),
                QuizAnswer(text: "third", isCorrect: false)
            ]
        )
        let raw = """
        {
          "summary": "Tighten the option wording.",
          "revised": {
            "answers": ["First option", "Second option", "Third option"]
          }
        }
        """

        let review = QuestionReviewService().parse(raw, original: original)

        XCTAssertEqual(review.revisedAnswers?.map(\.text), ["First option", "Second option", "Third option"])
        // Correctness is preserved, not taken from the model.
        XCTAssertEqual(review.revisedAnswers?.map(\.isCorrect), [false, true, false])
        // Identity is preserved so per-answer state stays stable.
        XCTAssertEqual(review.revisedAnswers?.map(\.id), original.answers.map(\.id))
    }

    func testFewerReturnedAnswersNeverDropExistingOptions() {
        let original = QuizQuestion(
            type: .multipleChoice,
            prompt: "Pick one.",
            answers: [
                QuizAnswer(text: "alpha", isCorrect: true),
                QuizAnswer(text: "beta", isCorrect: false),
                QuizAnswer(text: "gamma", isCorrect: false)
            ]
        )
        // The model misbehaves and returns only one option.
        let raw = """
        { "summary": "x", "revised": { "answers": ["Alpha (clearer)"] } }
        """

        let review = QuestionReviewService().parse(raw, original: original)

        XCTAssertEqual(review.revisedAnswers?.count, 3)
        XCTAssertEqual(review.revisedAnswers?.map(\.text), ["Alpha (clearer)", "beta", "gamma"])
        XCTAssertEqual(review.revisedAnswers?.map(\.isCorrect), [true, false, false])
    }

    func testRewritesMatchingPairsInPlace() {
        let matchingQuestion = QuizQuestion(
            type: .matching,
            prompt: "Match the capital.",
            matches: [
                MatchingPair(prompt: "France", match: "paris"),
                MatchingPair(prompt: "Japan", match: "tokyo")
            ]
        )
        let raw = """
        {
          "summary": "Capitalize the capitals.",
          "revised": {
            "matches": [
              {"term": "France", "match": "Paris"},
              {"term": "Japan", "match": "Tokyo"}
            ]
          }
        }
        """

        let review = QuestionReviewService().parse(raw, original: matchingQuestion)

        XCTAssertEqual(review.revisedMatches?.count, 2)
        XCTAssertEqual(review.revisedMatches?.map(\.match), ["Paris", "Tokyo"])
        XCTAssertEqual(review.revisedMatches?.map(\.id), matchingQuestion.matches.map(\.id))
        XCTAssertNil(review.revisedAnswers)
    }
}
