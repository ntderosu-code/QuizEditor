import XCTest
@testable import QuizEditorCore

/// Phase 4: discipline packs are pure data on the engine. These validate each
/// built-in pack's signature behavior through the real linter and prompt builder,
/// and confirm General stays unaffected.
final class DisciplinePackTests: XCTestCase {
    private let linter = QuestionLinter()
    private let review = QuestionReviewService()

    private func rules(_ findings: [LintFinding]) -> Set<LintFinding.Rule> {
        Set(findings.map(\.rule))
    }

    // MARK: - Registry

    func testBuiltInDisciplinesAreReadOnlyAndDistinct() {
        let packs = Persona.builtInDisciplines
        XCTAssertTrue(packs.contains { $0.id.contains("nursing") })
        XCTAssertTrue(packs.allSatisfy(\.isBuiltIn))
        XCTAssertEqual(Set(packs.map(\.id)).count, packs.count)
        XCTAssertFalse(packs.contains { $0.id == Persona.generalID })
    }

    // MARK: - Nursing

    func testNursingFlagsCountedSATA() {
        let question = QuizQuestion(
            type: .multipleAnswer,
            prompt: "Select the three findings that indicate hypoglycemia.",
            answers: [QuizAnswer(text: "Diaphoresis", isCorrect: true), QuizAnswer(text: "Tremor", isCorrect: true)],
            feedback: "x"
        )
        let fired = rules(linter.findings(for: question, persona: .nursing))
        XCTAssertTrue(fired.contains(LintFinding.Rule("sataCountCue")))
    }

    func testNursingFlagsBannedAbbreviationViaLexicon() {
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "The order reads insulin 10 U subcutaneously. What is the priority action?",
            answers: [QuizAnswer(text: "Clarify the order", isCorrect: true), QuizAnswer(text: "Administer", isCorrect: false)],
            feedback: "x"
        )
        let flagged = linter.findings(for: question, persona: .nursing)
            .contains { $0.rule.rawValue.hasPrefix("terminology:") }
        XCTAssertTrue(flagged, "Nursing should flag the banned abbreviation 'U' via the lexicon")
    }

    func testNursingReviewPromptCarriesClinicalJudgmentPreamble() {
        let prompt = review.systemInstruction(persona: .nursing)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("clinical judgment"))
    }

    // MARK: - Medicine

    func testMedicineEscalatesNegativeStemToWarning() {
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "Which of the following is not a first-line antihypertensive?",
            answers: [QuizAnswer(text: "A", isCorrect: false), QuizAnswer(text: "B", isCorrect: true), QuizAnswer(text: "C", isCorrect: false)],
            feedback: "x"
        )
        let finding = linter.findings(for: question, persona: .medicine)
            .first { $0.rule == .unemphasizedNegativeStem }
        XCTAssertEqual(finding?.severity, .warning)
    }

    // MARK: - Pharmacy

    func testPharmacyFlagsUnitlessNumericDose() {
        let question = QuizQuestion(
            type: .numeric,
            prompt: "Calculate the dose in milligrams.",
            feedback: "x",
            numeric: NumericAnswer(mode: .exact, value: 250)
        )
        // Pharmacy opts into the numeric-unit check; a numeric answer with no
        // expected unit is flagged.
        let fired = rules(linter.findings(for: question, persona: .pharmacy))
        XCTAssertTrue(fired.contains(.numericMissingUnit))
    }

    // MARK: - Public Health

    func testPublicHealthFlagsCausationLanguage() {
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "Smoking causes lung cancer in this cohort study.",
            answers: [QuizAnswer(text: "True", isCorrect: true), QuizAnswer(text: "False", isCorrect: false)],
            feedback: "x"
        )
        let flagged = linter.findings(for: question, persona: .publicHealth)
            .contains { $0.suggestion.localizedCaseInsensitiveContains("associated with") }
        XCTAssertTrue(flagged)
    }

    // MARK: - Social Work

    func testSocialWorkRequiresCompetency() {
        let question = QuizQuestion(type: .multipleChoice, prompt: "A scenario.", answers: [QuizAnswer(text: "A", isCorrect: true)], feedback: "x")
        let fired = rules(linter.findings(for: question, persona: .socialWork))
        XCTAssertTrue(fired.contains(.noCompetencyLinked))
    }

    func testSocialWorkFlagsStigmatizingLanguage() {
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "Which intervention best supports the addict described in the vignette?",
            answers: [QuizAnswer(text: "Motivational interviewing", isCorrect: true), QuizAnswer(text: "Discharge", isCorrect: false)],
            feedback: "x"
        )
        let flagged = linter.findings(for: question, persona: .socialWork)
            .contains { $0.rule.rawValue.hasPrefix("terminology:") }
        XCTAssertTrue(flagged, "Social Work should flag stigmatizing 'addict' in favor of person-first language")
    }

    // MARK: - General unaffected

    func testGeneralDoesNotFireDisciplineRules() {
        let question = QuizQuestion(
            type: .multipleAnswer,
            prompt: "Select the three findings that indicate hypoglycemia.",
            answers: [QuizAnswer(text: "A", isCorrect: true), QuizAnswer(text: "B", isCorrect: true)],
            feedback: "x"
        )
        let fired = rules(linter.findings(for: question, persona: .general))
        XCTAssertFalse(fired.contains(LintFinding.Rule("sataCountCue")))
        XCTAssertFalse(fired.contains(.noCompetencyLinked))
    }
}
