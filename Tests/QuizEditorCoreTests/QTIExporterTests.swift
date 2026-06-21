import XCTest
@testable import QuizEditorCore

final class QTIExporterTests: XCTestCase {
    func testClassicItemCarriesPointsTagsAndDifficultyMetadata() throws {
        let quiz = Quiz(title: "Meta", questions: [
            QuizQuestion(
                type: .multipleChoice,
                prompt: "Q?",
                answers: [QuizAnswer(text: "A", isCorrect: true)],
                points: 3,
                tags: ["cells", "energy"],
                difficulty: .hard
            )
        ])

        let package = try CanvasQTIExporter(engine: .classicQuizzes).makePackage(for: quiz)
        let item = try XCTUnwrap(package.file(named: "items/question-1.xml")).contents

        XCTAssertTrue(item.contains("<fieldlabel>points_possible</fieldlabel>"))
        XCTAssertTrue(item.contains("<fieldentry>3</fieldentry>"))
        XCTAssertTrue(item.contains("<fieldlabel>difficulty</fieldlabel>"))
        XCTAssertTrue(item.contains("<fieldentry>hard</fieldentry>"))
        XCTAssertTrue(item.contains("<fieldlabel>tags</fieldlabel>"))
        XCTAssertTrue(item.contains("cells, energy"))
    }

    func testBuildsCanvasQTIPackageWithManifestAssessmentItemsAnswersAndFeedback() throws {
        let quiz = Quiz(
            title: "Safety <Basics>",
            questions: [
                QuizQuestion(
                    type: .multipleChoice,
                    prompt: "Which item is required?",
                    answers: [
                        QuizAnswer(text: "Goggles", isCorrect: true),
                        QuizAnswer(text: "Sandals", isCorrect: false)
                    ],
                    feedback: "Wear goggles when chemicals are present."
                ),
                QuizQuestion(
                    type: .essay,
                    prompt: "Describe one lab safety habit.",
                    answers: [],
                    feedback: "Mention a specific observable habit."
                )
            ]
        )

        let package = try CanvasQTIExporter().makePackage(for: quiz)

        XCTAssertEqual(Set(package.files.map(\.path)), [
            "imsmanifest.xml",
            "assessment.xml",
            "items/question-1.xml",
            "items/question-2.xml"
        ])

        let manifest = try XCTUnwrap(package.file(named: "imsmanifest.xml"))
        XCTAssertTrue(manifest.contents.contains("imsqti_xmlv1p2"))
        XCTAssertTrue(manifest.contents.contains("assessment.xml"))

        let assessment = try XCTUnwrap(package.file(named: "assessment.xml"))
        XCTAssertTrue(assessment.contents.contains("Safety &lt;Basics&gt;"))
        XCTAssertTrue(assessment.contents.contains("question-1.xml"))
        XCTAssertTrue(assessment.contents.contains("question-2.xml"))

        let firstItem = try XCTUnwrap(package.file(named: "items/question-1.xml"))
        XCTAssertTrue(firstItem.contents.contains("multiple_choice_question"))
        XCTAssertTrue(firstItem.contents.contains("Which item is required?"))
        XCTAssertTrue(firstItem.contents.contains("Goggles"))
        XCTAssertTrue(firstItem.contents.contains("respcondition title=\"correct\""))
        XCTAssertTrue(firstItem.contents.contains("Wear goggles when chemicals are present."))

        let essayItem = try XCTUnwrap(package.file(named: "items/question-2.xml"))
        XCTAssertTrue(essayItem.contents.contains("essay_question"))
        XCTAssertTrue(essayItem.contents.contains("Describe one lab safety habit."))
    }

    func testBuildsNewQuizzesQTIPackageWithQTI21AssessmentItems() throws {
        let quiz = Quiz(
            title: "New Quiz",
            questions: [
                QuizQuestion(
                    type: .multipleChoice,
                    prompt: "Which export target supports New Quizzes?",
                    answers: [
                        QuizAnswer(text: "QTI 2.x", isCorrect: true),
                        QuizAnswer(text: "Plain text only", isCorrect: false)
                    ],
                    feedback: "New Quizzes supports QTI 2.x imports."
                )
            ]
        )

        let package = try CanvasQTIExporter(engine: .newQuizzes).makePackage(for: quiz)

        let manifest = try XCTUnwrap(package.file(named: "imsmanifest.xml"))
        XCTAssertTrue(manifest.contents.contains("imsqti_item_xmlv2p1"))
        XCTAssertTrue(manifest.contents.contains("items/question-1.xml"))

        let item = try XCTUnwrap(package.file(named: "items/question-1.xml"))
        XCTAssertTrue(item.contents.contains("assessmentItem"))
        XCTAssertTrue(item.contents.contains("choiceInteraction"))
        XCTAssertTrue(item.contents.contains("Which export target supports New Quizzes?"))
        XCTAssertTrue(item.contents.contains("QTI 2.x"))
        XCTAssertTrue(item.contents.contains("New Quizzes supports QTI 2.x imports."))
    }

    func testWritesAZipFileContainingTheQTIPackage() throws {
        let quiz = Quiz.sample
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try QTIPackageWriter().writeZip(for: quiz, to: outputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        let zipData = try Data(contentsOf: outputURL)
        XCTAssertEqual(Array(zipData.prefix(2)), [0x50, 0x4B])
        XCTAssertGreaterThan(zipData.count, 100)
    }
}
