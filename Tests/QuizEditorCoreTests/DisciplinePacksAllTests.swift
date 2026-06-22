import XCTest
@testable import QuizEditorCore

/// Validates the remaining Phase 4 discipline packs (STEM, social sciences,
/// humanities). Each assertion exercises the pack's signature behavior through the
/// real engine; AI-only packs are checked via the prompt preamble.
final class DisciplinePacksAllTests: XCTestCase {
    private let linter = QuestionLinter()
    private let review = QuestionReviewService()

    private func ruleIDs(_ findings: [LintFinding]) -> Set<String> {
        Set(findings.map(\.rule.rawValue))
    }

    private func flagsTerm(_ persona: Persona, prompt: String, suggests: String) -> Bool {
        let q = QuizQuestion(type: .multipleChoice, prompt: prompt,
                             answers: [QuizAnswer(text: "A", isCorrect: true), QuizAnswer(text: "B", isCorrect: false)],
                             feedback: "x")
        return linter.findings(for: q, persona: persona).contains { $0.suggestion.localizedCaseInsensitiveContains(suggests) }
    }

    private func numericFiresMissingUnit(_ persona: Persona) -> Bool {
        let q = QuizQuestion(type: .numeric, prompt: "Compute the quantity.", feedback: "x",
                             numeric: NumericAnswer(mode: .exact, value: 42))
        return ruleIDs(linter.findings(for: q, persona: persona)).contains("numericMissingUnit")
    }

    private func preamble(_ persona: Persona) -> String { review.systemInstruction(persona: persona) }

    // MARK: - Registry

    func testAllFamiliesPresentDistinctAndBuiltIn() {
        let packs = Persona.builtInDisciplines
        XCTAssertEqual(packs.count, 21)
        XCTAssertEqual(Set(packs.map(\.id)).count, packs.count)
        XCTAssertTrue(packs.allSatisfy(\.isBuiltIn))
        XCTAssertEqual(Set(packs.map(\.family)), ["health", "science", "stem", "social-science", "humanities"])
        // Every pack resolves through the resolver.
        let resolver = PersonaResolver(personas: packs)
        for pack in packs {
            XCTAssertEqual(resolver.resolve(pack.id).id, pack.id)
        }
    }

    // MARK: - STEM / natural sciences

    func testBiologyFlagsProves() {
        XCTAssertTrue(flagsTerm(.biology, prompt: "This experiment proves the hypothesis.", suggests: "data support"))
    }

    func testChemistryFlagsMissingNumericUnit() { XCTAssertTrue(numericFiresMissingUnit(.chemistry)) }
    func testPhysicsFlagsMissingNumericUnit() { XCTAssertTrue(numericFiresMissingUnit(.physics)) }
    func testEngineeringFlagsMissingNumericUnit() { XCTAssertTrue(numericFiresMissingUnit(.engineering)) }

    func testComputerSciencePreamble() {
        XCTAssertTrue(preamble(.computerScience).localizedCaseInsensitiveContains("output"))
    }

    func testMathematicsPreambleAcceptsEquivalentForms() {
        let prompt = review.makePrompt(question: QuizQuestion(type: .multipleChoice, prompt: "Q", answers: [QuizAnswer(text: "A", isCorrect: true)], feedback: "x"), quizTitle: "Math", persona: .mathematics)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("equivalent"))
    }

    func testStatisticsFlagsCausation() {
        XCTAssertTrue(flagsTerm(.statistics, prompt: "Exposure causes the outcome in this survey.", suggests: "associated with"))
    }

    // MARK: - Social sciences

    func testCounselingRequiresCompetencyAndPersonFirst() {
        let q = QuizQuestion(type: .multipleChoice, prompt: "Scenario.", answers: [QuizAnswer(text: "A", isCorrect: true)], feedback: "x")
        XCTAssertTrue(ruleIDs(linter.findings(for: q, persona: .counseling)).contains("noCompetencyLinked"))
        XCTAssertTrue(flagsTerm(.counseling, prompt: "Working with the addict in the case", suggests: "person with a substance use disorder"))
    }

    func testEconomicsPreambleCeterisParibus() {
        XCTAssertTrue(preamble(.economics).localizedCaseInsensitiveContains("ceteris"))
    }

    func testLawEscalatesNegativeStem() {
        let q = QuizQuestion(type: .multipleChoice, prompt: "Which of these is not a valid defense?",
                             answers: [QuizAnswer(text: "A", isCorrect: false), QuizAnswer(text: "B", isCorrect: true), QuizAnswer(text: "C", isCorrect: false)], feedback: "x")
        let finding = linter.findings(for: q, persona: .law).first { $0.rule == .unemphasizedNegativeStem }
        XCTAssertEqual(finding?.severity, .warning)
    }

    func testPoliticalSciencePreamble() {
        XCTAssertTrue(preamble(.politicalScience).localizedCaseInsensitiveContains("comparative"))
    }

    func testPsychologyFlagsPopPsychAndCausation() {
        XCTAssertTrue(flagsTerm(.psychology, prompt: "Are left-brained learners more creative?", suggests: "people who"))
        XCTAssertTrue(flagsTerm(.psychology, prompt: "Screen time causes anxiety, per a correlational study.", suggests: "associated with"))
    }

    func testSociologyFlagsDeficitLanguage() {
        XCTAssertTrue(flagsTerm(.sociology, prompt: "Which policy best helps the poor described here?", suggests: "person experiencing poverty"))
    }

    // MARK: - Humanities

    func testHistoryPreamblePeriodization() {
        XCTAssertTrue(preamble(.history).localizedCaseInsensitiveContains("periodization"))
    }

    func testLiteraturePreamblePassage() {
        XCTAssertTrue(preamble(.literature).localizedCaseInsensitiveContains("passage"))
    }

    func testPhilosophyPreambleValidity() {
        XCTAssertTrue(preamble(.philosophy).localizedCaseInsensitiveContains("validity"))
    }

    // MARK: - General unaffected

    func testGeneralUnaffectedByAllPacks() {
        let q = QuizQuestion(type: .numeric, prompt: "Exposure causes the outcome.", feedback: "x", numeric: NumericAnswer(mode: .exact, value: 42))
        let fired = ruleIDs(linter.findings(for: q, persona: .general))
        XCTAssertFalse(fired.contains("numericMissingUnit"))
        XCTAssertFalse(fired.contains { $0.hasPrefix("terminology:") })
        XCTAssertEqual(review.systemInstruction(persona: .general), review.systemInstruction())
    }
}
