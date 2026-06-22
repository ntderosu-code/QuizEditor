import XCTest
@testable import QuizEditorCore

/// Phase 3 / #24: personas become user-authorable, forkable, and shareable. These
/// cover the core pieces the editor and packaging rely on: forking a built-in, the
/// built-in rule catalog the override UI renders, round-trip fidelity for a fully
/// populated persona, and import validation with forward-compatible warnings.
final class PersonaEditorTests: XCTestCase {
    // MARK: - Fork

    func testForkProducesEditableUserCopy() {
        let source = Persona.general
        let fork = source.fork()

        XCTAssertNotEqual(fork.id, source.id)
        XCTAssertFalse(fork.isBuiltIn)
        XCTAssertEqual(fork.basePersonaID, source.id)
        XCTAssertTrue(fork.id.hasPrefix("user."))
        XCTAssertTrue(fork.displayName.contains(source.displayName))
    }

    func testForkIsAThinExtenderThatComposesOntoSource() {
        let source = Persona(
            id: "app.quizeditor.persona.nursing",
            displayName: "Nursing",
            family: "health",
            summary: "Clinical judgment.",
            aiProfile: PersonaAIProfile(systemPreamble: "Be a nurse educator.", reviewGuidelines: ["Flag unsafe actions."]),
            exemplars: ["A single-best-action vignette."],
            isBuiltIn: true
        )
        let fork = source.fork()

        // The fork itself carries only display metadata + the base link; its
        // profiles are empty so resolution doesn't duplicate the base's content.
        XCTAssertEqual(fork.family, "health")
        XCTAssertEqual(fork.basePersonaID, source.id)
        XCTAssertTrue(fork.aiProfile.reviewGuidelines.isEmpty)
        XCTAssertTrue(fork.exemplars.isEmpty)

        // Resolving the fork reproduces the source's behavior exactly — once.
        let resolved = PersonaResolver(personas: [source, fork]).resolve(fork.id)
        XCTAssertEqual(resolved.aiProfile.systemPreamble, "Be a nurse educator.")
        XCTAssertEqual(resolved.aiProfile.reviewGuidelines, ["Flag unsafe actions."])
        XCTAssertEqual(resolved.exemplars, ["A single-best-action vignette."])
    }

    // MARK: - Built-in rule catalog

    func testRuleCatalogListsOverridableBuiltInRules() {
        let ids = Set(LintRuleCatalog.builtInRules.map(\.rule))
        XCTAssertTrue(ids.contains(.noCorrectAnswer))
        XCTAssertTrue(ids.contains(.unemphasizedNegativeStem))
        // Every catalog entry has a non-empty human label.
        XCTAssertTrue(LintRuleCatalog.builtInRules.allSatisfy { !$0.label.isEmpty })
        // Non-overridable rules are excluded.
        for ruleID in QuestionLinter.nonOverridableRuleIDs {
            XCTAssertFalse(ids.contains(ruleID))
        }
    }

    // MARK: - Round-trip fidelity

    func testFullyPopulatedPersonaRoundTripsThroughJSON() throws {
        let persona = Persona(
            id: "user.test.full",
            displayName: "Full Test",
            family: "stem",
            version: 2,
            summary: "Everything set.",
            basePersonaID: "app.quizeditor.persona.general",
            linterProfile: PersonaLinterProfile(
                ruleOverrides: ["unemphasizedNegativeStem": PersonaRuleOverride(enabled: true, severity: .warning)],
                declarativeRules: [
                    PersonaLinterRule(
                        id: "unitMissing",
                        scope: "options",
                        requiresPattern: "(mg|mL)",
                        itemTypes: [.multipleChoice],
                        difficulties: [.hard],
                        requiresSource: true,
                        severity: .suggestion,
                        message: "Units missing.",
                        suggestion: "Add units."
                    )
                ],
                checksRecallDrift: true
            ),
            aiProfile: PersonaAIProfile(
                systemPreamble: "Preamble.",
                reviewGuidelines: ["R1"],
                authoringGuidelines: ["A1"],
                feedbackGuidelines: ["F1"],
                distractorStrategy: "Strategy.",
                tone: "Formal.",
                safetyClauses: ["No fabrication."],
                temperatureOverride: 0.1
            ),
            itemTypeProfile: PersonaItemTypeProfile(defaultType: .multipleChoice, preferredTypes: [.multipleChoice, .multipleAnswer]),
            terminology: [PersonaTerminologyRule(preferred: "associated with", discouraged: ["causes"], rationale: "Correlation.")],
            exemplars: ["Exemplar one."],
            linkingPresets: PersonaLinkingPresets(competencyFrameworks: ["ABET"], suggestObjectiveLink: true)
        )

        let data = try JSONEncoder().encode(persona)
        let decoded = try JSONDecoder().decode(Persona.self, from: data)
        XCTAssertEqual(decoded, persona)
    }

    // MARK: - Import validation

    func testImportAcceptsValidPersonaAndFlagsUnknownKeys() throws {
        let json = """
        {
          "id": "user.imported",
          "displayName": "Imported",
          "family": "humanities",
          "futureOnlyField": {"x": 1}
        }
        """
        let result = try Persona.importResult(fromJSON: Data(json.utf8))
        XCTAssertEqual(result.persona.id, "user.imported")
        XCTAssertEqual(result.persona.displayName, "Imported")
        XCTAssertTrue(result.warnings.contains { $0.contains("futureOnlyField") })
    }

    func testImportRejectsPersonaMissingRequiredFields() {
        let json = """
        { "family": "humanities" }
        """
        XCTAssertThrowsError(try Persona.importResult(fromJSON: Data(json.utf8)))
    }
}
