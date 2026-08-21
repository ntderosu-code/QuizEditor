import XCTest
@testable import QuizEditorCore

final class ExamAssemblerTests: XCTestCase {
    /// A 25-question bank; each prompt carries its authored index so order is easy to assert.
    private func bank(_ count: Int = 25) -> Quiz {
        Quiz(
            title: "Bank",
            questions: (0..<count).map { index in
                QuizQuestion(
                    type: .shortAnswer,
                    prompt: "Q\(index)",
                    answers: [QuizAnswer(text: "A\(index)", isCorrect: true)],
                    points: Double(index + 1)
                )
            }
        )
    }

    private func prompts(_ quiz: Quiz) -> [String] { quiz.questions.map(\.prompt) }

    // MARK: - Selection

    func testDefaultOptionsReturnTheWholeQuizUnchanged() {
        let quiz = bank()
        let assembled = ExamAssembler.assemble(quiz, selection: ExamSelection())
        XCTAssertEqual(assembled, quiz)
    }

    func testCountWithoutShuffleTakesTheFirstNInAuthoredOrder() {
        let assembled = ExamAssembler.assemble(bank(), selection: ExamSelection(questionCount: 20))
        XCTAssertEqual(prompts(assembled), (0..<20).map { "Q\($0)" })
    }

    func testCountClampsToTheAvailableQuestions() {
        let over = ExamAssembler.assemble(bank(5), selection: ExamSelection(questionCount: 99))
        XCTAssertEqual(over.questions.count, 5)

        let under = ExamAssembler.assemble(bank(5), selection: ExamSelection(questionCount: 0))
        XCTAssertTrue(under.questions.isEmpty)

        let negative = ExamAssembler.assemble(bank(5), selection: ExamSelection(questionCount: -3))
        XCTAssertTrue(negative.questions.isEmpty)
    }

    func testNilCountKeepsEveryQuestionEvenWhenShuffling() {
        let assembled = ExamAssembler.assemble(
            bank(),
            selection: ExamSelection(shuffleQuestions: true, questionCount: nil, seedLabel: "Version A")
        )
        XCTAssertEqual(assembled.questions.count, 25)
        XCTAssertEqual(Set(prompts(assembled)), Set(prompts(bank())))
    }

    // MARK: - Derived quiz

    func testDerivedQuizShrinksTotalPointsToTheSubset() {
        let assembled = ExamAssembler.assemble(bank(), selection: ExamSelection(questionCount: 3))
        // Points are 1, 2, 3 for the first three authored questions.
        XCTAssertEqual(assembled.totalPoints, 6, accuracy: 0.001)
    }

    func testDerivedQuizKeepsTitleAndLinkingEntities() {
        var quiz = bank(5)
        quiz.objectives = [LearningObjective(text: "Explain mitosis")]
        let assembled = ExamAssembler.assemble(quiz, selection: ExamSelection(questionCount: 2))
        XCTAssertEqual(assembled.title, quiz.title)
        XCTAssertEqual(assembled.id, quiz.id)
        XCTAssertEqual(assembled.objectives, quiz.objectives)
    }

    // MARK: - Seeded shuffling

    func testSameSeedProducesTheSameOrderAcrossCalls() {
        let selection = ExamSelection(shuffleQuestions: true, questionCount: 20, seedLabel: "Version A")
        let first = ExamAssembler.assemble(bank(), selection: selection)
        let second = ExamAssembler.assemble(bank(), selection: selection)
        XCTAssertEqual(prompts(first), prompts(second))
    }

    /// The answer key is a separate export; with the same seed and count it must
    /// present exactly the questions the student copy did, in the same order.
    func testAnswerKeyMatchesTheStudentCopyForTheSameSeed() {
        let student = ExamSelection(shuffleQuestions: true, questionCount: 20, seedLabel: "Version B")
        let key = ExamSelection(shuffleQuestions: true, questionCount: 20, seedLabel: "Version B")
        XCTAssertEqual(prompts(ExamAssembler.assemble(bank(), selection: student)),
                       prompts(ExamAssembler.assemble(bank(), selection: key)))
    }

    func testDifferentSeedsProduceDifferentOrders() {
        let a = ExamAssembler.assemble(bank(), selection: ExamSelection(shuffleQuestions: true, seedLabel: "Version A"))
        let b = ExamAssembler.assemble(bank(), selection: ExamSelection(shuffleQuestions: true, seedLabel: "Version B"))
        XCTAssertNotEqual(prompts(a), prompts(b))
    }

    func testShufflingIsAPermutationOfTheBank() {
        let assembled = ExamAssembler.assemble(bank(), selection: ExamSelection(shuffleQuestions: true, seedLabel: "Seed"))
        XCTAssertEqual(Set(prompts(assembled)), Set(prompts(bank())))
        XCTAssertNotEqual(prompts(assembled), prompts(bank()), "A 25-question shuffle should not land back in authored order")
    }

    /// The seed must survive relaunching the app: String.hashValue is randomized
    /// per process, so the stable hash is asserted against fixed expected values.
    func testStableSeedHashIsIndependentOfProcessLaunch() {
        XCTAssertEqual(ExamSelection.stableSeed(for: "Version A"), 3_858_971_208_477_204_956 as UInt64)
        XCTAssertEqual(ExamSelection.stableSeed(for: ""), 14_695_981_039_346_656_037 as UInt64)
    }

    func testDifferentSubsetsAreSelectedForDifferentSeeds() {
        let a = ExamAssembler.assemble(bank(), selection: ExamSelection(shuffleQuestions: true, questionCount: 20, seedLabel: "Version A"))
        let b = ExamAssembler.assemble(bank(), selection: ExamSelection(shuffleQuestions: true, questionCount: 20, seedLabel: "Version B"))
        XCTAssertNotEqual(Set(prompts(a)), Set(prompts(b)), "A 20-of-25 draw should exclude different questions per seed")
    }
}

/// The two export paths must apply the same selection, and the paper exam's
/// header totals must describe the exam it actually prints.
final class ExamSelectionExportTests: XCTestCase {
    private let bank = Quiz(
        title: "Bank",
        questions: (0..<10).map { index in
            QuizQuestion(
                type: .shortAnswer,
                prompt: "Prompt\(index)",
                answers: [QuizAnswer(text: "A\(index)", isCorrect: true)],
                points: 2
            )
        }
    )

    func testPaperExamPrintsOnlyTheSelectedQuestions() {
        let options = PaperExamOptions(questionCount: 4)
        let html = PaperExamBuilder().document(for: bank, options: options)
        XCTAssertTrue(html.contains("Prompt3"))
        XCTAssertFalse(html.contains("Prompt4"))
    }

    func testPaperExamScoreTotalReflectsTheSelectedSubset() {
        let html = PaperExamBuilder().document(for: bank, options: PaperExamOptions(questionCount: 4))
        // Four questions at 2 points each, not the bank's 20.
        XCTAssertTrue(html.contains("/ 8"), "Expected the score field to read out of 8")
        XCTAssertFalse(html.contains("/ 20"))
    }

    func testSelectedQuestionsAreNumberedFromOne() {
        let html = PaperExamBuilder().document(
            for: bank,
            options: PaperExamOptions(versionLabel: "Version A", shuffleQuestions: true, questionCount: 3)
        )
        XCTAssertTrue(html.contains("<span class=\"qnum\">1.</span>"))
        XCTAssertTrue(html.contains("<span class=\"qnum\">3.</span>"))
        XCTAssertFalse(html.contains("<span class=\"qnum\">4.</span>"))
    }

    func testFormattedDocumentHonorsTheSameSelection() {
        let selection = ExamSelection(shuffleQuestions: false, questionCount: 4)
        let html = FormattedDocumentBuilder().document(for: bank, selection: selection)
        XCTAssertTrue(html.contains("Prompt3"))
        XCTAssertFalse(html.contains("Prompt4"))
    }

    func testAnswerKeyAndStudentCopyShareTheSameQuestionsAndOrder() {
        let student = PaperExamOptions(versionLabel: "Version A", shuffleQuestions: true, questionCount: 6)
        var key = student
        key.includeAnswerKey = true

        let order: (String) -> [String] = { html in
            (0..<10).compactMap { index in
                html.range(of: "Prompt\(index)").map { _ in "Prompt\(index)" }
            }
        }
        // Same membership...
        XCTAssertEqual(
            Set(order(PaperExamBuilder().document(for: bank, options: student))),
            Set(order(PaperExamBuilder().document(for: bank, options: key)))
        )
        // ...and the same sequence, which is what makes the key usable for grading.
        let studentQuiz = ExamAssembler.assemble(bank, selection: student.selection)
        let keyQuiz = ExamAssembler.assemble(bank, selection: key.selection)
        XCTAssertEqual(studentQuiz.questions.map(\.prompt), keyQuiz.questions.map(\.prompt))
        XCTAssertEqual(studentQuiz.questions.count, 6)
    }
}

/// The formatted document printed the answers unconditionally, which made the
/// only HTML export unusable as a student handout.
final class FormattedDocumentOptionsTests: XCTestCase {
    private let quiz = Quiz(
        title: "Bank",
        questions: (0..<4).map { index in
            QuizQuestion(
                type: .multipleChoice,
                prompt: "Prompt\(index)",
                answers: [
                    QuizAnswer(text: "Right\(index)", isCorrect: true),
                    QuizAnswer(text: "Wrong\(index)", isCorrect: false)
                ],
                feedback: "<p>Because\(index).</p>"
            )
        }
    )

    func testDefaultsToIncludingTheAnswers() {
        XCTAssertTrue(FormattedDocumentOptions().includeAnswers)
    }

    func testExcludingAnswersDropsCorrectMarkersAndFeedback() {
        let html = FormattedDocumentBuilder().document(
            for: quiz,
            options: FormattedDocumentOptions(includeAnswers: false)
        )
        XCTAssertTrue(html.contains("Right0"), "the choices themselves still print")
        XCTAssertFalse(html.contains("Because0"), "feedback belongs to the answer key")
        // The stylesheet always carries an li.correct rule; what matters is that
        // no element is given the class or the tag.
        XCTAssertFalse(html.contains("class=\"correct\""), "no choice is marked correct")
        XCTAssertFalse(html.contains("(correct)"))
    }

    func testIncludingAnswersKeepsThem() {
        let html = FormattedDocumentBuilder().document(
            for: quiz,
            options: FormattedDocumentOptions(includeAnswers: true)
        )
        XCTAssertTrue(html.contains("Because0"))
    }

    /// The two settings are independent: a short student handout is a subset
    /// with the answers withheld.
    func testSelectionAndAnswerVisibilityCompose() {
        let html = FormattedDocumentBuilder().document(
            for: quiz,
            options: FormattedDocumentOptions(
                includeAnswers: false,
                selection: ExamSelection(questionCount: 2)
            )
        )
        XCTAssertTrue(html.contains("Prompt1"))
        XCTAssertFalse(html.contains("Prompt2"))
        XCTAssertFalse(html.contains("Because0"))
    }
}
