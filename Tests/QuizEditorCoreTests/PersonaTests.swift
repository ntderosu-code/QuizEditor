import XCTest
@testable import QuizEditorCore

final class PersonaTests: XCTestCase {

    // MARK: - General built-in

    func testGeneralIsBuiltInWithEmptyProfilesSoBehaviorIsUnchanged() {
        let general = Persona.general
        XCTAssertEqual(general.id, Persona.generalID)
        XCTAssertTrue(general.isBuiltIn)
        XCTAssertTrue(general.linterProfile.ruleOverrides.isEmpty)
        XCTAssertTrue(general.linterProfile.declarativeRules.isEmpty)
        XCTAssertEqual(general.aiProfile.systemPreamble, "")
        XCTAssertTrue(general.aiProfile.reviewGuidelines.isEmpty)
        XCTAssertNil(general.itemTypeProfile.defaultType)
        XCTAssertTrue(general.terminology.isEmpty)
    }

    // MARK: - Resolution

    func testResolverFallsBackToGeneralForNilAndUnknownIDs() {
        let resolver = PersonaResolver(personas: [])
        XCTAssertEqual(resolver.resolve(nil).id, Persona.generalID)
        XCTAssertEqual(resolver.resolve("does.not.exist").id, Persona.generalID)
    }

    func testResolverReturnsRequestedPersona() {
        let nursing = Persona(id: "app.quizeditor.persona.nursing", displayName: "Nursing", family: "health")
        let resolver = PersonaResolver(personas: [nursing])
        XCTAssertEqual(resolver.resolve(nursing.id).displayName, "Nursing")
    }

    func testResolverMergesChildOntoBase() {
        let base = Persona(
            id: "base",
            displayName: "Base",
            linterProfile: PersonaLinterProfile(ruleOverrides: ["missingFeedback": PersonaRuleOverride(enabled: false)]),
            aiProfile: PersonaAIProfile(systemPreamble: "Base preamble.", reviewGuidelines: ["Base bullet."]),
            terminology: [PersonaTerminologyRule(preferred: "associated with", discouraged: ["causes"])],
            linkingPresets: PersonaLinkingPresets(competencyFrameworks: ["QSEN"], suggestObjectiveLink: true)
        )
        let child = Persona(
            id: "child",
            displayName: "Child",
            basePersonaID: "base",
            linterProfile: PersonaLinterProfile(ruleOverrides: ["allOfTheAbove": PersonaRuleOverride(severity: .warning)]),
            aiProfile: PersonaAIProfile(systemPreamble: "Child preamble.", reviewGuidelines: ["Child bullet."]),
            terminology: [PersonaTerminologyRule(preferred: "myocardial infarction")],
            linkingPresets: PersonaLinkingPresets(competencyFrameworks: ["AACN"], suggestSourceLink: true)
        )
        let resolved = PersonaResolver(personas: [base, child]).resolve("child")

        // Identity stays the child's.
        XCTAssertEqual(resolved.id, "child")
        XCTAssertEqual(resolved.displayName, "Child")
        // Rule overrides from both, child added.
        XCTAssertEqual(resolved.linterProfile.ruleOverrides["missingFeedback"]?.enabled, false)
        XCTAssertEqual(resolved.linterProfile.ruleOverrides["allOfTheAbove"]?.severity, .warning)
        // Child scalar wins; bullets append base-then-child.
        XCTAssertEqual(resolved.aiProfile.systemPreamble, "Child preamble.")
        XCTAssertEqual(resolved.aiProfile.reviewGuidelines, ["Base bullet.", "Child bullet."])
        // Terminology merges; both present.
        XCTAssertEqual(resolved.terminology.count, 2)
        // Linking booleans OR together; frameworks union.
        XCTAssertTrue(resolved.linkingPresets.suggestObjectiveLink)
        XCTAssertTrue(resolved.linkingPresets.suggestSourceLink)
        XCTAssertEqual(resolved.linkingPresets.competencyFrameworks, ["QSEN", "AACN"])
    }

    func testChildOverrideWinsOverBaseForSameRuleID() {
        let base = Persona(id: "base", displayName: "Base",
            linterProfile: PersonaLinterProfile(ruleOverrides: ["allOfTheAbove": PersonaRuleOverride(severity: .suggestion)]))
        let child = Persona(id: "child", displayName: "Child", basePersonaID: "base",
            linterProfile: PersonaLinterProfile(ruleOverrides: ["allOfTheAbove": PersonaRuleOverride(severity: .warning)]))
        let resolved = PersonaResolver(personas: [base, child]).resolve("child")
        XCTAssertEqual(resolved.linterProfile.ruleOverrides["allOfTheAbove"]?.severity, .warning)
    }

    func testResolverSurvivesSelfReferenceAndCycles() {
        let selfRef = Persona(id: "loop", displayName: "Loop", basePersonaID: "loop")
        XCTAssertEqual(PersonaResolver(personas: [selfRef]).resolve("loop").id, "loop")

        let a = Persona(id: "a", displayName: "A", basePersonaID: "b")
        let b = Persona(id: "b", displayName: "B", basePersonaID: "a")
        // Should terminate rather than recurse forever.
        XCTAssertEqual(PersonaResolver(personas: [a, b]).resolve("a").id, "a")
    }

    // MARK: - Tolerant decoding

    func testDecodesMinimalPersonaWithDefaults() throws {
        let json = #"{"id":"x","displayName":"X"}"#.data(using: .utf8)!
        let persona = try JSONDecoder().decode(Persona.self, from: json)
        XCTAssertEqual(persona.id, "x")
        XCTAssertEqual(persona.family, "general")
        XCTAssertEqual(persona.version, 1)
        XCTAssertFalse(persona.isBuiltIn)
        XCTAssertTrue(persona.exemplars.isEmpty)
        XCTAssertTrue(persona.aiProfile.reviewGuidelines.isEmpty)
    }

    func testPersonaRoundTripsThroughCodable() throws {
        let original = Persona(
            id: "app.quizeditor.persona.chemistry",
            displayName: "Chemistry",
            family: "science",
            summary: "Units and notation aware.",
            aiProfile: PersonaAIProfile(reviewGuidelines: ["Require units."]),
            terminology: [PersonaTerminologyRule(preferred: "mole", discouraged: ["mol unit"], rationale: "clarity")],
            isBuiltIn: true
        )
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Persona.self, from: data)
        XCTAssertEqual(original, restored)
    }

    // MARK: - Quiz per-quiz override

    func testQuizDecodesWithoutPersonaIDAsNil() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000000","title":"Old Quiz","questions":[]}"#.data(using: .utf8)!
        let quiz = try JSONDecoder().decode(Quiz.self, from: json)
        XCTAssertNil(quiz.personaID)
    }

    func testQuizPersonaIDRoundTrips() throws {
        var quiz = Quiz(title: "Cell Biology")
        quiz.personaID = "app.quizeditor.persona.biology"
        let data = try JSONEncoder().encode(quiz)
        let restored = try JSONDecoder().decode(Quiz.self, from: data)
        XCTAssertEqual(restored.personaID, "app.quizeditor.persona.biology")
    }
}
