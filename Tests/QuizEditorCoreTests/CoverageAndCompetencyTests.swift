import XCTest
@testable import QuizEditorCore

/// #25: the coverage/blueprint report, the opt-in "no competency linked" linter
/// gate, and competency labels flowing into AI prompts.
final class CoverageAndCompetencyTests: XCTestCase {
    private let linter = QuestionLinter()

    private func mc(_ prompt: String, competencyIDs: [String] = [], objectiveIDs: [String] = []) -> QuizQuestion {
        QuizQuestion(
            type: .multipleChoice,
            prompt: prompt,
            answers: [QuizAnswer(text: "A", isCorrect: true), QuizAnswer(text: "B", isCorrect: false)],
            feedback: "x",
            objectiveIDs: objectiveIDs,
            competencyIDs: competencyIDs
        )
    }

    private func framework() -> Framework {
        Framework(id: "f", name: "F", nodes: [
            FrameworkNode(id: "n1", code: "1", label: "Alpha"),
            FrameworkNode(id: "n2", code: "2", label: "Beta")
        ])
    }

    // MARK: - Coverage report

    func testCoverageCountsItemsPerNodeAndGaps() {
        let quiz = Quiz(title: "Q", questions: [
            mc("Q1", competencyIDs: ["n1"]),
            mc("Q2", competencyIDs: ["n1"])
        ])
        let report = CoverageReport.make(quiz: quiz, frameworks: [framework()])

        let alpha = report.nodeCoverage.first { $0.node.id == "n1" }
        let beta = report.nodeCoverage.first { $0.node.id == "n2" }
        XCTAssertEqual(alpha?.questionCount, 2)
        XCTAssertEqual(beta?.questionCount, 0)
        XCTAssertTrue(report.gaps.contains { $0.node.id == "n2" })
        XCTAssertFalse(report.gaps.contains { $0.node.id == "n1" })
    }

    func testCoverageCountsUnmappedQuestions() {
        let quiz = Quiz(title: "Q", questions: [
            mc("Linked", competencyIDs: ["n1"]),
            mc("Unmapped")
        ])
        let report = CoverageReport.make(quiz: quiz, frameworks: [framework()])
        XCTAssertEqual(report.unmappedQuestionCount, 1)
        XCTAssertEqual(report.totalQuestions, 2)
    }

    func testCoverageCognitiveLevelBalanceFromObjectives() {
        let quiz = Quiz(
            title: "Q",
            questions: [mc("Q1", competencyIDs: ["n1"], objectiveIDs: ["o1"]), mc("Q2", objectiveIDs: ["o2"])],
            objectives: [
                LearningObjective(id: "o1", text: "Apply", cognitiveLevel: .apply),
                LearningObjective(id: "o2", text: "Apply too", cognitiveLevel: .apply)
            ]
        )
        let report = CoverageReport.make(quiz: quiz, frameworks: [framework()])
        XCTAssertEqual(report.cognitiveLevelCounts[.apply], 2)
        XCTAssertNil(report.cognitiveLevelCounts[.create])
    }

    // MARK: - Linter gate

    func testRequiresCompetencyGateFiresWhenAbsent() {
        let persona = Persona(
            id: "test.competency",
            displayName: "Competency Required",
            linterProfile: PersonaLinterProfile(requiresCompetency: true)
        )
        let unlinked = mc("No competency")
        XCTAssertTrue(Set(linter.findings(for: unlinked, persona: persona).map(\.rule)).contains(.noCompetencyLinked))

        let linked = mc("Linked", competencyIDs: ["n1"])
        XCTAssertFalse(Set(linter.findings(for: linked, persona: persona).map(\.rule)).contains(.noCompetencyLinked))
    }

    func testGeneralDoesNotRequireCompetency() {
        XCTAssertFalse(Set(linter.findings(for: mc("Q"), persona: .general).map(\.rule)).contains(.noCompetencyLinked))
    }

    // MARK: - AI competency labels

    func testPromptLinkContextResolvesCompetencyLabels() {
        let question = mc("Q", competencyIDs: ["n1"])
        let quiz = Quiz(title: "Q", questions: [question])
        let context = quiz.promptLinkContext(for: question, frameworks: [framework()])
        XCTAssertEqual(context.competencies, ["1 — Alpha"])
    }

    func testReviewPromptIncludesCompetencyLabels() {
        let question = mc("Q", competencyIDs: ["n1"])
        let context = PromptLinkContext(competencies: ["1 — Alpha"])
        let prompt = QuestionReviewService().makePrompt(question: question, quizTitle: "Q", linkedContext: context)
        XCTAssertTrue(prompt.contains("1 — Alpha"))
    }
}
