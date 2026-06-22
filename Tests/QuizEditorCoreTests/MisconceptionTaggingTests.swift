import XCTest
@testable import QuizEditorCore

/// Phase 3: per-distractor misconception tagging. AI distractor generation can
/// return misconception labels (opt-in per persona), and the parser tolerates both
/// the plain and labeled response shapes.
final class MisconceptionTaggingTests: XCTestCase {
    private let service = QuestionAuthoringService()

    func testParseLabeledDistractorsAcceptsObjectShape() {
        let raw = """
        { "distractors": [
            {"text": "Bradycardia", "misconception": "confuses with hyperglycemia"},
            {"text": "Warm dry skin", "misconception": "ignores sympathetic response"}
        ] }
        """
        let parsed = service.parseLabeledDistractors(raw)
        XCTAssertEqual(parsed.map(\.text), ["Bradycardia", "Warm dry skin"])
        XCTAssertEqual(parsed.first?.misconception, "confuses with hyperglycemia")
    }

    func testParseLabeledDistractorsAcceptsPlainStringShape() {
        // Back-compat: a plain string array still parses, with nil misconceptions.
        let raw = """
        { "distractors": ["Option A", "Option B"] }
        """
        let parsed = service.parseLabeledDistractors(raw)
        XCTAssertEqual(parsed.map(\.text), ["Option A", "Option B"])
        XCTAssertNil(parsed.first?.misconception)
    }

    func testParseLabeledDistractorsAcceptsBareArray() {
        let parsed = service.parseLabeledDistractors("[\"X\", \"Y\"]")
        XCTAssertEqual(parsed.map(\.text), ["X", "Y"])
    }

    func testParseDistractorsStillReturnsTextOnly() {
        // The existing text-only parser keeps working for callers that want strings.
        let raw = """
        { "distractors": [{"text": "Bradycardia", "misconception": "m"}] }
        """
        XCTAssertEqual(service.parseDistractors(raw), ["Bradycardia"])
    }

    func testDistractorPromptUnchangedWhenPersonaDoesNotOptIn() {
        // Byte-equivalent to today (the base prompt already mentions "misconceptions";
        // opt-in adds the labeled response shape, which General must not).
        XCTAssertEqual(
            service.makeDistractorsPrompt(prompt: "Stem", correctAnswer: "X", count: 3, persona: .general),
            service.makeDistractorsPrompt(prompt: "Stem", correctAnswer: "X", count: 3)
        )
        XCTAssertFalse(
            service.makeDistractorsPrompt(prompt: "Stem", correctAnswer: "X", count: 3, persona: .general)
                .contains("name the misconception it targets")
        )
    }

    func testDistractorPromptRequestsLabelsWhenPersonaOptsIn() {
        let persona = Persona(
            id: "test.mis",
            displayName: "Misconception",
            aiProfile: PersonaAIProfile(labelsMisconceptions: true)
        )
        let prompt = service.makeDistractorsPrompt(prompt: "Stem", correctAnswer: "X", count: 3, persona: persona)
        XCTAssertTrue(prompt.contains("name the misconception it targets"))
    }
}
