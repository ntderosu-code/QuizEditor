import XCTest
@testable import QuizEditorCore

/// Performance guards for importing/exporting large documents, to catch
/// regressions. Three complementary mechanisms:
///   1. `measure {}` blocks — human-readable timings locally, and Xcode baselines
///      if opened there (note: `swift test` runs them but does not fail on a
///      baseline regression — that's an Xcode-only gate).
///   2. Scaling/ratio guards — compare 10× input and assert time stays roughly
///      linear. Machine-independent, so they fail CI on an accidental O(n²)
///      without being flaky on slow hardware.
///   3. Absolute budgets — a deliberately loose ceiling that catches catastrophic
///      regressions (e.g. an accidental quadratic or per-item disk thrash).
final class LargeDocumentPerformanceTests: XCTestCase {
    // Sizes for the scaling guards (10× apart).
    private let smallCount = 100
    private let largeCount = 1000

    /// A linear operation processing 10× the input should take well under this
    /// multiple of the small-input time. Linear is ~10×; an O(n²) regression is
    /// ~100×. Generous to absorb fixed costs and CI noise.
    private let linearFactor = 40.0

    /// Loose catastrophic-regression ceiling for a `largeCount` operation.
    private let absoluteBudgetSeconds = 20.0

    // MARK: - Fixtures

    private func makeQuiz(_ count: Int) -> Quiz {
        let questions = (0..<count).map { index in
            QuizQuestion(
                type: .multipleChoice,
                prompt: "<p>Question \(index): which option is correct for scenario \(index)?</p>",
                answers: [
                    QuizAnswer(text: "Correct answer \(index)", isCorrect: true),
                    QuizAnswer(text: "Plausible distractor A \(index)", isCorrect: false),
                    QuizAnswer(text: "Plausible distractor B \(index)", isCorrect: false),
                    QuizAnswer(text: "Plausible distractor C \(index)", isCorrect: false)
                ],
                feedback: "<p>The correct answer for \(index) is supported by the rationale.</p>",
                tags: ["topic-\(index % 12)", "unit-\(index % 5)"],
                difficulty: [.easy, .medium, .hard][index % 3]
            )
        }
        return Quiz(title: "Large Performance Quiz", questions: questions)
    }

    private func makeMarkedText(_ count: Int) -> String {
        (0..<count).map { index in
            """
            Question \(index): which option is correct?
            * Correct answer \(index)
            Plausible distractor A \(index)
            Plausible distractor B \(index)
            Plausible distractor C \(index)
            """
        }.joined(separator: "\n\n")
    }

    /// Writes an exported package to a temp directory for import timing. Returned
    /// URL is cleaned up by the caller via `addTeardownBlock`.
    private func exportedDirectory(_ quiz: Quiz, engine: CanvasQuizEngine) throws -> URL {
        let package = try CanvasQTIExporter(engine: engine).makePackage(for: quiz)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("perf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for file in package.files {
            let url = dir.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.contents.write(to: url, atomically: true, encoding: .utf8)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    /// Best (minimum) wall-clock of `runs` executions — min is the most stable
    /// estimator (least perturbed by scheduler noise), which keeps the ratio
    /// guards reliable.
    private func bestTime(runs: Int = 3, _ body: () -> Void) -> TimeInterval {
        var best = TimeInterval.greatestFiniteMagnitude
        for _ in 0..<runs {
            let start = Date()
            body()
            best = min(best, Date().timeIntervalSince(start))
        }
        return best
    }

    private func assertScalesLinearly(_ label: String, small: TimeInterval, large: TimeInterval) {
        // Guard against a ~0 small time making the ratio meaningless.
        guard small > 0.0005 else { return }
        XCTAssertLessThan(
            large, small * linearFactor,
            "\(label) scaled worse than linear: \(smallCount)→\(String(format: "%.4f", small))s, \(largeCount)→\(String(format: "%.4f", large))s (×\(String(format: "%.1f", large / small)))"
        )
    }

    // MARK: - Classic QTI export

    func testMeasureClassicExport() {
        let quiz = makeQuiz(largeCount)
        measure { _ = try? CanvasQTIExporter(engine: .classicQuizzes).makePackage(for: quiz) }
    }

    func testClassicExportScalesLinearly() {
        let small = makeQuiz(smallCount), large = makeQuiz(largeCount)
        let tSmall = bestTime { _ = try? CanvasQTIExporter(engine: .classicQuizzes).makePackage(for: small) }
        let tLarge = bestTime { _ = try? CanvasQTIExporter(engine: .classicQuizzes).makePackage(for: large) }
        assertScalesLinearly("Classic export", small: tSmall, large: tLarge)
        XCTAssertLessThan(tLarge, absoluteBudgetSeconds, "Classic export of \(largeCount) questions took \(tLarge)s")
    }

    // MARK: - New Quizzes export

    func testMeasureNewQuizzesExport() {
        let quiz = makeQuiz(largeCount)
        measure { _ = try? CanvasQTIExporter(engine: .newQuizzes).makePackage(for: quiz) }
    }

    func testNewQuizzesExportScalesLinearly() {
        let small = makeQuiz(smallCount), large = makeQuiz(largeCount)
        let tSmall = bestTime { _ = try? CanvasQTIExporter(engine: .newQuizzes).makePackage(for: small) }
        let tLarge = bestTime { _ = try? CanvasQTIExporter(engine: .newQuizzes).makePackage(for: large) }
        assertScalesLinearly("New Quizzes export", small: tSmall, large: tLarge)
        XCTAssertLessThan(tLarge, absoluteBudgetSeconds, "New Quizzes export of \(largeCount) questions took \(tLarge)s")
    }

    // MARK: - QTI import (parse a large package)

    func testMeasureQTIImport() throws {
        let dir = try exportedDirectory(makeQuiz(largeCount), engine: .classicQuizzes)
        measure { _ = try? QTIImporter().importQuiz(fromDirectory: dir) }
    }

    func testQTIImportScalesLinearly() throws {
        let smallDir = try exportedDirectory(makeQuiz(smallCount), engine: .classicQuizzes)
        let largeDir = try exportedDirectory(makeQuiz(largeCount), engine: .classicQuizzes)
        let tSmall = bestTime { _ = try? QTIImporter().importQuiz(fromDirectory: smallDir) }
        let tLarge = bestTime { _ = try? QTIImporter().importQuiz(fromDirectory: largeDir) }
        assertScalesLinearly("QTI import", small: tSmall, large: tLarge)
        XCTAssertLessThan(tLarge, absoluteBudgetSeconds, "QTI import of \(largeCount) questions took \(tLarge)s")

        // Sanity: the import actually recovered every question.
        let imported = try QTIImporter().importQuiz(fromDirectory: largeDir)
        XCTAssertEqual(imported.questions.count, largeCount)
    }

    // MARK: - Marked-text parse (paste import)

    func testMeasureMarkedTextParse() {
        let text = makeMarkedText(largeCount)
        measure { _ = try? MarkedTextParser().parse(text) }
    }

    func testMarkedTextParseScalesLinearly() {
        let small = makeMarkedText(smallCount), large = makeMarkedText(largeCount)
        let tSmall = bestTime { _ = try? MarkedTextParser().parse(small) }
        let tLarge = bestTime { _ = try? MarkedTextParser().parse(large) }
        assertScalesLinearly("Marked-text parse", small: tSmall, large: tLarge)
        XCTAssertLessThan(tLarge, absoluteBudgetSeconds, "Marked-text parse of \(largeCount) questions took \(tLarge)s")
    }

    // MARK: - Whole-quiz lint

    func testMeasureQuizLint() {
        let quiz = makeQuiz(largeCount)
        let linter = QuestionLinter()
        measure { _ = linter.findings(for: quiz, persona: .general) }
    }

    func testQuizLintScalesLinearly() {
        let small = makeQuiz(smallCount), large = makeQuiz(largeCount)
        let linter = QuestionLinter()
        let tSmall = bestTime { _ = linter.findings(for: small, persona: .nursing) }
        let tLarge = bestTime { _ = linter.findings(for: large, persona: .nursing) }
        assertScalesLinearly("Quiz lint (Nursing)", small: tSmall, large: tLarge)
        XCTAssertLessThan(tLarge, absoluteBudgetSeconds, "Linting \(largeCount) questions took \(tLarge)s")
    }
}
