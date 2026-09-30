import XCTest
@testable import QuizEditorCore

final class QTIValidatorTests: XCTestCase {
    private let validator = QTIValidator()

    private let quiz = Quiz(
        title: "Validation Quiz",
        questions: [
            QuizQuestion(
                type: .multipleChoice,
                prompt: "What is 2 + 2?",
                answers: [QuizAnswer(text: "4", isCorrect: true), QuizAnswer(text: "5", isCorrect: false)],
                feedback: "Basic arithmetic."
            ),
            QuizQuestion(type: .essay, prompt: "Explain entropy."),
            QuizQuestion(
                type: .matching,
                prompt: "Match capital to country.",
                matches: [MatchingPair(prompt: "France", match: "Paris")]
            )
        ]
    )

    func testValidClassicExportHasNoIssues() {
        XCTAssertEqual(validator.validateExport(of: quiz, target: .qti12), [])
    }

    func testValidNewQuizzesExportHasNoErrors() {
        let issues = validator.validateExport(of: quiz, target: .qti21)
        XCTAssertFalse(issues.contains { $0.severity == .error })
    }

    // MARK: - Format fidelity

    private var formulaQuiz: Quiz {
        Quiz(title: "Formulas", questions: [
            QuizQuestion(
                type: .formula,
                prompt: "Compute F = m * a.",
                formula: FormulaAnswer(
                    variables: [FormulaVariable(name: "m", value: 2), FormulaVariable(name: "a", value: 9.8)],
                    expression: "m * a"
                )
            )
        ])
    }

    /// QTI 2.1 has nowhere to put a formula expression, so exporting one there
    /// silently drops it. That warrants a warning naming the fix, since the
    /// author has a lossless option one menu item away.
    func testQTI21FormulaExportWarnsThatTheExpressionIsLost() {
        let issues = validator.validateExport(of: formulaQuiz, target: .qti21)
        let warning = issues.first { $0.message.contains("formula") }
        XCTAssertNotNil(warning, "expected a formula fidelity warning, got: \(issues)")
        XCTAssertEqual(warning?.severity, .warning, "advisory only — it must never block the export")
        XCTAssertTrue(try XCTUnwrap(warning?.message).contains("QTI 1.2"), "the warning should name the lossless target")
    }

    /// QTI 1.2 stores the expression in qtimetadata, so there is nothing to warn about.
    func testQTI12FormulaExportDoesNotWarn() {
        let issues = validator.validateExport(of: formulaQuiz, target: .qti12)
        XCTAssertFalse(issues.contains { $0.message.contains("formula") })
    }

    /// The warning is about formulas specifically, not about QTI 2.1 in general.
    func testQTI21WithoutFormulasDoesNotWarn() {
        let issues = validator.validateExport(of: quiz, target: .qti21)
        XCTAssertFalse(issues.contains { $0.message.contains("formula") })
    }

    func testRoundTripPreservesQuestionCount() {
        // A larger quiz still re-imports with the same count.
        let big = Quiz(title: "Big", questions: (1...8).map {
            QuizQuestion(type: .multipleChoice, prompt: "Q\($0)?",
                         answers: [QuizAnswer(text: "a", isCorrect: true), QuizAnswer(text: "b", isCorrect: false)])
        })
        XCTAssertFalse(validator.validateExport(of: big, target: .qti12).contains { $0.severity == .error })
    }

    func testWellFormednessCatchesMalformedXML() {
        let package = QTIPackage(files: [
            QTIPackageFile(path: "imsmanifest.xml", contents: "<manifest></manifest>"),
            QTIPackageFile(path: "items/question-1.xml", contents: "<item><unclosed></item>")
        ])
        let issues = validator.wellFormednessIssues(in: package)
        XCTAssertTrue(issues.contains { $0.severity == .error && $0.message.contains("question-1.xml") })
    }

    func testManifestConsistencyCatchesCountMismatch() {
        let package = QTIPackage(files: [
            QTIPackageFile(path: "imsmanifest.xml", contents: "<manifest>items/question-1.xml</manifest>"),
            QTIPackageFile(path: "assessment.xml", contents: "<assessment/>"),
            QTIPackageFile(path: "items/question-1.xml", contents: "<item/>")
        ])
        // Only one item file, but two questions were expected.
        let issues = validator.manifestConsistencyIssues(in: package, expectedItemCount: 2)
        XCTAssertTrue(issues.contains { $0.severity == .error && $0.message.contains("Expected 2") })
    }

    func testManifestConsistencyFlagsUnreferencedItem() {
        let package = QTIPackage(files: [
            QTIPackageFile(path: "imsmanifest.xml", contents: "<manifest>nothing here</manifest>"),
            QTIPackageFile(path: "assessment.xml", contents: "<assessment/>"),
            QTIPackageFile(path: "items/question-1.xml", contents: "<item/>")
        ])
        let issues = validator.manifestConsistencyIssues(in: package, expectedItemCount: 1)
        XCTAssertTrue(issues.contains { $0.severity == .warning && $0.message.contains("not referenced") })
    }

    func testMissingManifestIsAnError() {
        let package = QTIPackage(files: [QTIPackageFile(path: "assessment.xml", contents: "<a/>")])
        let issues = validator.manifestConsistencyIssues(in: package, expectedItemCount: 0)
        XCTAssertTrue(issues.contains { $0.severity == .error && $0.message.contains("imsmanifest.xml") })
    }

    // MARK: - Target-compatibility advisories

    func testSurveyQuizExportedAsNewQuizzesWarns() {
        // Canvas Surveys are a QTI 1.2-only Canvas feature. Exporting to New
        // Quizzes (qti21) is a no-op for the survey flag. The author should
        // know the receiving engine doesn't have a survey type.
        let survey = Quiz(
            title: "Course eval",
            questions: [QuizQuestion(type: .multipleChoice, prompt: "Pace?", answers: [QuizAnswer(text: "OK")])],
            kind: .survey
        )
        let issues = validator.validateExport(of: survey, target: .qti21)
        XCTAssertTrue(issues.contains { $0.severity == QTIValidationIssue.Severity.warning && $0.message.lowercased().contains("survey") })
    }

    func testNewQuizzesExportWithMatchingWarns() {
        // Canvas's New Quizzes engine renders matching items differently from
        // Classic Quizzes; the author should be aware before sending.
        let withMatching = Quiz(
            title: "T",
            questions: [
                QuizQuestion(
                    type: .matching,
                    prompt: "Match.",
                    matches: [MatchingPair(prompt: "A", match: "B")]
                )
            ]
        )
        let issues = validator.validateExport(of: withMatching, target: .qti21)
        XCTAssertTrue(issues.contains { $0.severity == QTIValidationIssue.Severity.warning && $0.message.lowercased().contains("matching") })
    }
}
