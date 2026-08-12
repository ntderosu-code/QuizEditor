import XCTest
@testable import QuizEditorCore

/// Validates the built-in discipline pack roster (#89: General plus Social Work,
/// Nursing, Medicine, Pharmacy, and Biology) and the packs whose signature
/// behavior isn't covered by the focused tests in DisciplinePackTests.
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

    // MARK: - Registry

    func testRosterIsTheFivePhase2PacksPlusGeneralElsewhere() {
        let packs = Persona.builtInDisciplines
        XCTAssertEqual(packs.map(\.displayName).sorted(),
                       ["Biology", "Medicine", "Nursing", "Pharmacy", "Social Work"])
        XCTAssertEqual(Set(packs.map(\.id)).count, packs.count)
        XCTAssertTrue(packs.allSatisfy(\.isBuiltIn))
        XCTAssertFalse(packs.contains { $0.id == Persona.generalID }, "General is surfaced separately, not as a pack")
        // Every pack resolves through the resolver.
        let resolver = PersonaResolver(personas: packs)
        for pack in packs {
            XCTAssertEqual(resolver.resolve(pack.id).id, pack.id)
        }
    }

    func testRemovedPackIDsResolveToGeneral() {
        // Quizzes saved while the larger roster shipped may still name a removed
        // pack; they must quietly fall back to General.
        let resolver = PersonaResolver(personas: Persona.builtInDisciplines + [.general])
        XCTAssertEqual(resolver.resolve("app.quizeditor.persona.chemistry").id, Persona.generalID)
        XCTAssertEqual(resolver.resolve("app.quizeditor.persona.psychology").id, Persona.generalID)
    }

    // MARK: - Biology

    func testBiologyFlagsProves() {
        XCTAssertTrue(flagsTerm(.biology, prompt: "This experiment proves the hypothesis.", suggests: "data support"))
    }

    // MARK: - General unaffected

    func testGeneralUnaffectedByAllPacks() {
        let q = QuizQuestion(type: .numeric, prompt: "Exposure causes the outcome.", feedback: "x", numeric: NumericAnswer(mode: .exact, value: 42))
        let fired = ruleIDs(linter.findings(for: q, persona: .general))
        XCTAssertFalse(fired.contains("numericMissingUnit"))
        XCTAssertFalse(fired.contains { $0.hasPrefix("terminology:") })
    }
}
