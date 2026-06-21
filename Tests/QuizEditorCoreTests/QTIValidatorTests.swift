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
        XCTAssertEqual(validator.validateExport(of: quiz, engine: .classicQuizzes), [])
    }

    func testValidNewQuizzesExportHasNoErrors() {
        let issues = validator.validateExport(of: quiz, engine: .newQuizzes)
        XCTAssertFalse(issues.contains { $0.severity == .error })
    }

    func testRoundTripPreservesQuestionCount() {
        // A larger quiz still re-imports with the same count.
        let big = Quiz(title: "Big", questions: (1...8).map {
            QuizQuestion(type: .multipleChoice, prompt: "Q\($0)?",
                         answers: [QuizAnswer(text: "a", isCorrect: true), QuizAnswer(text: "b", isCorrect: false)])
        })
        XCTAssertFalse(validator.validateExport(of: big, engine: .classicQuizzes).contains { $0.severity == .error })
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
}
