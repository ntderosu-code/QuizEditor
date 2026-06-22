import XCTest
@testable import QuizEditorCore

/// Phase 3: a Numeric question type with exact±margin / range / precision grading,
/// plus an advisory (tool-only, never exported) expected unit.
final class NumericQuestionTests: XCTestCase {
    private func numericQuestion(_ numeric: NumericAnswer) -> QuizQuestion {
        QuizQuestion(type: .numeric, prompt: "What is the molar mass of water?", feedback: "18 g/mol.", numeric: numeric)
    }

    // MARK: - Model

    func testNumericTypeMapsToCanvasNumericalQuestion() {
        XCTAssertEqual(QuizQuestionType.numeric.canvasQuestionType, "numerical_question")
        XCTAssertEqual(QuizQuestionType.numeric.displayName, "Numeric")
    }

    func testNumericAnswerRoundTripsThroughJSON() throws {
        let question = numericQuestion(NumericAnswer(
            mode: .exact, value: 18, margin: 0.5, expectedUnit: "g/mol"
        ))
        let data = try JSONEncoder().encode(question)
        let decoded = try JSONDecoder().decode(QuizQuestion.self, from: data)
        XCTAssertEqual(decoded, question)
        XCTAssertEqual(decoded.numeric?.expectedUnit, "g/mol")
    }

    func testQuestionSavedBeforeNumericExistedStillDecodes() throws {
        let legacy = """
        { "type": "multipleChoice", "prompt": "Q?", "answers": [] }
        """.data(using: .utf8)!
        let question = try JSONDecoder().decode(QuizQuestion.self, from: legacy)
        XCTAssertNil(question.numeric)
    }

    func testIsConfiguredReflectsMode() {
        XCTAssertTrue(NumericAnswer(mode: .exact, value: 5).isConfigured)
        XCTAssertFalse(NumericAnswer(mode: .exact, value: nil).isConfigured)
        XCTAssertTrue(NumericAnswer(mode: .range, rangeMin: 1, rangeMax: 3).isConfigured)
        XCTAssertFalse(NumericAnswer(mode: .range, rangeMin: 1, rangeMax: nil).isConfigured)
        XCTAssertTrue(NumericAnswer(mode: .precision, value: 3.14159, precisionDigits: 3).isConfigured)
    }

    // MARK: - Export: Classic (QTI 1.2)

    func testClassicExportRendersNumericWithToleranceRange() throws {
        let quiz = Quiz(title: "Chem", questions: [numericQuestion(
            NumericAnswer(mode: .exact, value: 18, margin: 0.5, expectedUnit: "g/mol")
        )])
        let item = try XCTUnwrap(CanvasQTIExporter(engine: .classicQuizzes).makePackage(for: quiz).file(named: "items/question-1.xml")).contents
        XCTAssertTrue(item.contains("numerical_question"))
        XCTAssertTrue(item.contains("fibtype=\"Decimal\""))
        // value ± margin → [17.5, 18.5]
        XCTAssertTrue(item.contains("vargte"))
        XCTAssertTrue(item.contains("varlte"))
        XCTAssertTrue(item.contains("17.5"))
        XCTAssertTrue(item.contains("18.5"))
    }

    func testClassicExportRendersRange() throws {
        let quiz = Quiz(title: "Chem", questions: [numericQuestion(
            NumericAnswer(mode: .range, rangeMin: 8, rangeMax: 10)
        )])
        let item = try XCTUnwrap(CanvasQTIExporter(engine: .classicQuizzes).makePackage(for: quiz).file(named: "items/question-1.xml")).contents
        XCTAssertTrue(item.contains("8"))
        XCTAssertTrue(item.contains("10"))
        XCTAssertTrue(item.contains("vargte"))
    }

    // MARK: - Export: New Quizzes (QTI 2.1)

    func testNewQuizzesExportDeclaresFloatResponse() throws {
        let quiz = Quiz(title: "Chem", questions: [numericQuestion(
            NumericAnswer(mode: .exact, value: 18, margin: 0.5)
        )])
        let item = try XCTUnwrap(CanvasQTIExporter(engine: .newQuizzes).makePackage(for: quiz).file(named: "items/question-1.xml")).contents
        XCTAssertTrue(item.contains("baseType=\"float\""))
        XCTAssertTrue(item.contains("textEntryInteraction"))
        XCTAssertTrue(item.contains("18"))
    }

    // MARK: - Import round-trip

    func testClassicNumericRoundTripsThroughImport() throws {
        let quiz = Quiz(title: "Chem", questions: [numericQuestion(
            NumericAnswer(mode: .range, rangeMin: 8, rangeMax: 10)
        )])
        let imported = try roundTripThroughDirectory(quiz, engine: .classicQuizzes)
        let q = try XCTUnwrap(imported.questions.first)
        XCTAssertEqual(q.type, .numeric)
        XCTAssertEqual(q.numeric?.rangeMin, 8)
        XCTAssertEqual(q.numeric?.rangeMax, 10)
    }

    /// Writes an exported package to a temp directory and imports it back.
    private func roundTripThroughDirectory(_ quiz: Quiz, engine: CanvasQuizEngine) throws -> Quiz {
        let package = try CanvasQTIExporter(engine: engine).makePackage(for: quiz)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("numeric-rt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for file in package.files {
            let url = dir.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return try QTIImporter().importQuiz(fromDirectory: dir)
    }

    // MARK: - Unit is never exported

    func testExpectedUnitIsNotExported() throws {
        let quiz = Quiz(title: "Chem", questions: [numericQuestion(
            NumericAnswer(mode: .exact, value: 18, margin: 0.5, expectedUnit: "UNIT_TOKEN_GML")
        )])
        for engine in CanvasQuizEngine.allCases {
            let everything = try CanvasQTIExporter(engine: engine).makePackage(for: quiz).files.map(\.contents).joined()
            XCTAssertFalse(everything.contains("UNIT_TOKEN_GML"), "unit leaked into \(engine) export")
        }
    }
}
