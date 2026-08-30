import XCTest
@testable import QuizEditorCore

final class QTIExporterTests: XCTestCase {

    // MARK: - Export target naming

    /// The raw values are the persisted spelling of the export choice and predate
    /// the rename away from Canvas engine names. Changing one silently
    /// invalidates any stored selection, so they are pinned here.
    func testExportTargetRawValuesArePinnedToTheOriginalEngineNames() {
        XCTAssertEqual(QTIExportTarget.qti12.rawValue, "classicQuizzes")
        XCTAssertEqual(QTIExportTarget.qti21.rawValue, "newQuizzes")
        XCTAssertEqual(QTIExportTarget.qti12Survey.rawValue, "surveys")
    }

    /// Labels lead with the QTI standard, because that is what the file is —
    /// Moodle, Blackboard, and D2L read these packages too. The Canvas engine
    /// stays in the name so Canvas users still recognise their option.
    func testExportTargetLabelsLeadWithTheQTIVersion() {
        for target in QTIExportTarget.allCases {
            XCTAssertTrue(
                target.displayName.hasPrefix("QTI "),
                "\(target) label should lead with the QTI version, got \(target.displayName)"
            )
        }
        XCTAssertEqual(QTIExportTarget.qti12.displayName, "QTI 1.2 (Classic Quizzes)")
        XCTAssertEqual(QTIExportTarget.qti21.displayName, "QTI 2.1 (New Quizzes)")
    }

    func testClassicItemCarriesPointsButNotAuthorMetadata() throws {
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

        let package = try QTIExporter(target: .qti12).makePackage(for: quiz)
        let item = try XCTUnwrap(package.file(named: "items/question-1.xml")).contents

        // Points are gradeable, so they belong in the package.
        XCTAssertTrue(item.contains("<fieldlabel>points_possible</fieldlabel>"))
        XCTAssertTrue(item.contains("<fieldentry>3</fieldentry>"))

        // Tags and difficulty are author metadata: tool-only, never exported.
        // Nothing reads them back on import, so writing them only leaked
        // authoring notes into a file handed to an LMS.
        XCTAssertFalse(item.contains("<fieldlabel>difficulty</fieldlabel>"))
        XCTAssertFalse(item.contains("<fieldentry>hard</fieldentry>"))
        XCTAssertFalse(item.contains("<fieldlabel>tags</fieldlabel>"))
        XCTAssertFalse(item.contains("cells, energy"))
    }

    /// The exclusion holds for every target, not just classic.
    func testAuthorMetadataIsExcludedFromEveryTarget() throws {
        let quiz = Quiz(title: "Metadata", questions: [
            QuizQuestion(
                type: .multipleChoice,
                prompt: "Q?",
                answers: [QuizAnswer(text: "A", isCorrect: true)],
                tags: ["cells", "energy"],
                difficulty: .hard
            )
        ])

        for target in QTIExportTarget.allCases {
            let package = try QTIExporter(target: target).makePackage(for: quiz)
            let everything = package.files.map(\.contents).joined()
            XCTAssertFalse(everything.contains("difficulty"), "difficulty leaked into \(target) export")
            XCTAssertFalse(everything.contains("cells, energy"), "tags leaked into \(target) export")
        }
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

        let package = try QTIExporter().makePackage(for: quiz)

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

        let package = try QTIExporter(target: .qti21).makePackage(for: quiz)

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

    // MARK: - Surveys

    func testSurveyEngineStripsResponseProcessingAndPoints() throws {
        // A survey has no correct answers and no points; the package must omit
        // both `points_possible` and any `<resprocessing>` block.
        let quiz = Quiz(
            title: "Mid-semester feedback",
            questions: [
                QuizQuestion(
                    type: .multipleChoice,
                    prompt: "How is the pace?",
                    answers: [QuizAnswer(text: "Just right"), QuizAnswer(text: "Too fast"), QuizAnswer(text: "Too slow")],
                    points: 1
                )
            ],
            kind: .survey
        )

        let package = try QTIExporter(target: .qti12Survey).makePackage(for: quiz)
        let item = try XCTUnwrap(package.file(named: "items/question-1.xml")).contents

        XCTAssertTrue(item.contains("multiple_choice_question"))
        XCTAssertFalse(item.contains("points_possible"), "Surveys must not carry a points_possible field")
        XCTAssertFalse(item.contains("<resprocessing>"), "Surveys must not include resprocessing")
        XCTAssertFalse(item.contains("respcondition"), "Surveys must not score answers")
    }

    func testGradedQuizExportedAsSurveyEngineAlsoStripsScoring() throws {
        // Forcing the .qti12Survey target produces an ungraded package even when
        // the quiz is .graded — useful for one-off survey exports.
        let quiz = Quiz(title: "Graded content", questions: [
            QuizQuestion(type: .multipleChoice, prompt: "Pick A", answers: [QuizAnswer(text: "A", isCorrect: true)])
        ])

        let package = try QTIExporter(target: .qti12Survey).makePackage(for: quiz)
        let item = try XCTUnwrap(package.file(named: "items/question-1.xml")).contents

        XCTAssertFalse(item.contains("<resprocessing>"))
        XCTAssertFalse(item.contains("points_possible"))
    }

    // MARK: - File upload + formula

    func testFileUploadQuestionRendersWithUploadInteraction() throws {
        let question = QuizQuestion(
            type: .fileUpload,
            prompt: "Upload your essay.",
            answers: [],
            allowedFileTypes: ["application/pdf", "image/png"]
        )
        let quiz = Quiz(title: "File upload", questions: [question])

        let classic = try QTIExporter(target: .qti12).makePackage(for: quiz)
        let classicItem = try XCTUnwrap(classic.file(named: "items/question-1.xml")).contents
        XCTAssertTrue(classicItem.contains("file_upload_question"))
        XCTAssertTrue(classicItem.contains("response_str"), "Classic file uploads use response_str type=file")
        XCTAssertTrue(classicItem.contains("fibtype=\"File\""))
        XCTAssertTrue(classicItem.contains("application/pdf"))

        let newQ = try QTIExporter(target: .qti21).makePackage(for: quiz)
        let newItem = try XCTUnwrap(newQ.file(named: "items/question-1.xml")).contents
        XCTAssertTrue(newItem.contains("uploadInteraction"))
        XCTAssertTrue(newItem.contains("expectedMimeTypes"))
        XCTAssertTrue(newItem.contains("application/pdf"))
    }

    func testFileUploadMimeListStaysOutWhenEmpty() throws {
        let question = QuizQuestion(type: .fileUpload, prompt: "Upload anything.")
        let quiz = Quiz(title: "T", questions: [question])
        let package = try QTIExporter(target: .qti21).makePackage(for: quiz)
        let item = try XCTUnwrap(package.file(named: "items/question-1.xml")).contents
        XCTAssertTrue(item.contains("uploadInteraction"))
        XCTAssertFalse(item.contains("expectedMimeTypes"))
    }

    func testFormulaQuestionRendersExpressionAndVariablesInClassicMetadata() throws {
        let formula = FormulaAnswer(
            variables: [FormulaVariable(name: "m", value: 2), FormulaVariable(name: "a", value: 9.8)],
            expression: "m * a",
            tolerance: 0.01
        )
        let question = QuizQuestion(
            type: .formula,
            prompt: "Compute F.",
            answers: [],
            formula: formula
        )
        let quiz = Quiz(title: "Physics", questions: [question])

        let package = try QTIExporter(target: .qti12).makePackage(for: quiz)
        let item = try XCTUnwrap(package.file(named: "items/question-1.xml")).contents

        XCTAssertTrue(item.contains("calculated_question"))
        XCTAssertTrue(item.contains("formula_question"))
        XCTAssertTrue(item.contains("m * a"))
        XCTAssertTrue(item.contains("<variable name=\"m\">2</variable>"))
        XCTAssertTrue(item.contains("<variable name=\"a\">9.8</variable>"))
        // The precomputed value (2 * 9.8 = 19.6) and tolerance (±0.01) live in the
        // answer key, which Canvas uses to score typed numeric answers.
        XCTAssertTrue(item.contains("19.6"))
    }

    func testFormulaQuestionRendersInQTI21() throws {
        let formula = FormulaAnswer(
            variables: [FormulaVariable(name: "x", value: 5), FormulaVariable(name: "y", value: 3)],
            expression: "(x + y) * 2"
        )
        let question = QuizQuestion(type: .formula, prompt: "Compute.", formula: formula)
        let quiz = Quiz(title: "T", questions: [question])

        let package = try QTIExporter(target: .qti21).makePackage(for: quiz)
        let item = try XCTUnwrap(package.file(named: "items/question-1.xml")).contents

        XCTAssertTrue(item.contains("assessmentItem"))
        XCTAssertTrue(item.contains("textEntryInteraction"))
        // (5 + 3) * 2 = 16
        XCTAssertTrue(item.contains("<value>16</value>"))
    }

    func testFormulaEvaluatorComputesRepresentativeValue() {
        let formula = FormulaAnswer(
            variables: [FormulaVariable(name: "a", value: 3), FormulaVariable(name: "b", value: 4)],
            expression: "(a + b) * 2"
        )
        XCTAssertEqual(formula.computedValue, 14)
    }

    // MARK: - Author metadata is never exported (formula + file upload + survey)

    func testFormulaExpectedUnitIsNeverExported() throws {
        // expectedUnit is tool-only — it must not leak into the QTI package.
        let formula = FormulaAnswer(
            variables: [FormulaVariable(name: "m", value: 2)],
            expression: "m * 9.8",
            expectedUnit: "NEWTON_TOKEN"
        )
        let quiz = Quiz(title: "Physics", questions: [
            QuizQuestion(type: .formula, prompt: "F = ?", formula: formula)
        ])
        let package = try QTIExporter().makePackage(for: quiz)
        let everything = package.files.map(\.contents).joined(separator: "\n")
        XCTAssertFalse(everything.contains("NEWTON_TOKEN"))
    }

    func testAllowedFileTypesRoundTripThroughCoding() throws {
        // Allowed file types are exported (Canvas reads them); the test just
        // confirms a list of two is preserved.
        let question = QuizQuestion(
            type: .fileUpload,
            prompt: "Upload.",
            allowedFileTypes: ["application/pdf", "text/plain"]
        )
        let data = try JSONEncoder().encode(question)
        let decoded = try JSONDecoder().decode(QuizQuestion.self, from: data)
        XCTAssertEqual(decoded.allowedFileTypes, ["application/pdf", "text/plain"])
    }
}
