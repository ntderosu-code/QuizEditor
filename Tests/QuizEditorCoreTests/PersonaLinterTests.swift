import XCTest
@testable import QuizEditorCore

/// Phase 1: the offline linter becomes persona-aware. A persona can disable or
/// re-weight built-in rules and add discipline rules expressed as data, while
/// General reproduces today's behavior exactly.
final class PersonaLinterTests: XCTestCase {
    private let linter = QuestionLinter()

    private func rules(_ findings: [LintFinding]) -> Set<LintFinding.Rule> {
        Set(findings.map(\.rule))
    }

    // MARK: - General reproduces today's behavior

    func testGeneralPersonaMatchesDefaultFindings() {
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "Which of these is not a prime number?",
            answers: [
                QuizAnswer(text: "2", isCorrect: false),
                QuizAnswer(text: "4", isCorrect: true),
                QuizAnswer(text: "3", isCorrect: false)
            ],
            feedback: ""
        )
        XCTAssertEqual(linter.findings(for: question, persona: .general), linter.findings(for: question))
    }

    // MARK: - Rule overrides

    func testPersonaCanDisableBuiltInRule() {
        let question = QuizQuestion(type: .essay, prompt: "Discuss mitosis.", feedback: "")
        XCTAssertTrue(rules(linter.findings(for: question)).contains(.missingFeedback))

        let persona = Persona(
            id: "test.disable",
            displayName: "Disable Feedback Rule",
            linterProfile: PersonaLinterProfile(
                ruleOverrides: ["missingFeedback": PersonaRuleOverride(enabled: false)]
            )
        )
        XCTAssertFalse(rules(linter.findings(for: question, persona: persona)).contains(.missingFeedback))
    }

    func testPersonaCanReweightBuiltInRuleSeverity() {
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "Which of these is not a prime number?",
            answers: [
                QuizAnswer(text: "2", isCorrect: false),
                QuizAnswer(text: "4", isCorrect: true),
                QuizAnswer(text: "3", isCorrect: false)
            ],
            feedback: "4 is composite."
        )
        // Default severity is suggestion.
        let defaultFinding = linter.findings(for: question)
            .first { $0.rule == .unemphasizedNegativeStem }
        XCTAssertEqual(defaultFinding?.severity, .suggestion)

        // Medicine-style escalation to warning.
        let persona = Persona(
            id: "test.escalate",
            displayName: "Escalate Negative Stem",
            linterProfile: PersonaLinterProfile(
                ruleOverrides: ["unemphasizedNegativeStem": PersonaRuleOverride(severity: .warning)]
            )
        )
        let escalated = linter.findings(for: question, persona: persona)
            .first { $0.rule == .unemphasizedNegativeStem }
        XCTAssertEqual(escalated?.severity, .warning)
    }

    // MARK: - Declarative rule engine

    /// Acceptance criterion: a nursing "select all that apply" count-cue rule
    /// fires from pure data (forbidden pattern present in the stem), gated to the
    /// Multiple Answer item type, at the persona-specified severity.
    private func nursingPersona() -> Persona {
        Persona(
            id: "test.nursing",
            displayName: "Nursing",
            linterProfile: PersonaLinterProfile(declarativeRules: [
                PersonaLinterRule(
                    id: "sataCountCue",
                    scope: "stem",
                    forbidsPattern: "select (two|three|four|\\d+)",
                    itemTypes: [.multipleAnswer],
                    severity: .warning,
                    message: "A \u{201C}select all that apply\u{201D} stem reveals how many options are correct.",
                    suggestion: "Remove the count cue; let the candidate judge each option independently."
                )
            ])
        )
    }

    func testDeclarativeForbiddenPatternFiresFromData() {
        let question = QuizQuestion(
            type: .multipleAnswer,
            prompt: "Select two of the following findings that indicate hypoglycemia.",
            answers: [
                QuizAnswer(text: "Diaphoresis", isCorrect: true),
                QuizAnswer(text: "Tremor", isCorrect: true),
                QuizAnswer(text: "Bradycardia", isCorrect: false)
            ],
            feedback: "Diaphoresis and tremor are classic."
        )
        let finding = linter.findings(for: question, persona: nursingPersona())
            .first { $0.rule == LintFinding.Rule("sataCountCue") }
        XCTAssertNotNil(finding)
        XCTAssertEqual(finding?.severity, .warning)
    }

    func testDeclarativeRuleRespectsItemTypeGate() {
        // Same forbidden phrasing, but a Multiple Choice item the rule does not gate to.
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "Select two numbers, then pick the larger one.",
            answers: [
                QuizAnswer(text: "7", isCorrect: true),
                QuizAnswer(text: "3", isCorrect: false)
            ],
            feedback: "7 is larger."
        )
        let fired = rules(linter.findings(for: question, persona: nursingPersona()))
            .contains(LintFinding.Rule("sataCountCue"))
        XCTAssertFalse(fired)
    }

    /// Acceptance criterion: a chemistry "numeric answers need units" rule fires
    /// when a required token (a unit) is ABSENT from the options.
    func testDeclarativeRequiredTokenAbsentFires() {
        let persona = Persona(
            id: "test.chemistry",
            displayName: "Chemistry",
            linterProfile: PersonaLinterProfile(declarativeRules: [
                PersonaLinterRule(
                    id: "unitMissingOnNumericItem",
                    scope: "options",
                    requiresPattern: "(mg|mL|g|mol|°C|K|J|kPa)",
                    itemTypes: [.multipleChoice],
                    severity: .suggestion,
                    message: "Numeric options have no units.",
                    suggestion: "Add the correct unit to each numeric option."
                )
            ])
        )
        let missing = QuizQuestion(
            type: .multipleChoice,
            prompt: "What is the molar mass of water?",
            answers: [
                QuizAnswer(text: "18", isCorrect: true),
                QuizAnswer(text: "16", isCorrect: false),
                QuizAnswer(text: "20", isCorrect: false)
            ],
            feedback: "Water is 18 g/mol."
        )
        XCTAssertTrue(rules(linter.findings(for: missing, persona: persona)).contains(LintFinding.Rule("unitMissingOnNumericItem")))

        let withUnits = QuizQuestion(
            type: .multipleChoice,
            prompt: "What is the molar mass of water?",
            answers: [
                QuizAnswer(text: "18 g/mol", isCorrect: true),
                QuizAnswer(text: "16 g/mol", isCorrect: false)
            ],
            feedback: "Water is 18 g/mol."
        )
        XCTAssertFalse(rules(linter.findings(for: withUnits, persona: persona)).contains(LintFinding.Rule("unitMissingOnNumericItem")))
    }

    func testGeneralPersonaHasNoDeclarativeFindings() {
        let question = QuizQuestion(
            type: .multipleAnswer,
            prompt: "Select two of the following.",
            answers: [QuizAnswer(text: "A", isCorrect: true), QuizAnswer(text: "B", isCorrect: true)],
            feedback: "x"
        )
        XCTAssertFalse(rules(linter.findings(for: question, persona: .general)).contains(LintFinding.Rule("sataCountCue")))
    }

    // MARK: - Lexicon scanner (terminology)

    private func terminologyPersona() -> Persona {
        Persona(
            id: "test.terminology",
            displayName: "Terminology",
            terminology: [
                PersonaTerminologyRule(
                    preferred: "associated with",
                    discouraged: ["causes"],
                    rationale: "Most exam items describe correlation, not proven causation."
                )
            ]
        )
    }

    func testLexiconFlagsDiscouragedTerm() {
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "Which factor causes type 2 diabetes?",
            answers: [QuizAnswer(text: "Obesity", isCorrect: true), QuizAnswer(text: "Cold weather", isCorrect: false)],
            feedback: "Obesity is a major risk factor."
        )
        let finding = linter.findings(for: question, persona: terminologyPersona())
            .first { $0.severity == .suggestion && $0.suggestion.localizedCaseInsensitiveContains("associated with") }
        XCTAssertNotNil(finding)
    }

    func testLexiconDoesNotFlagPreferredTerm() {
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "Which factor is associated with type 2 diabetes?",
            answers: [QuizAnswer(text: "Obesity", isCorrect: true), QuizAnswer(text: "Cold weather", isCorrect: false)],
            feedback: "Obesity is a major risk factor."
        )
        let flagged = linter.findings(for: question, persona: terminologyPersona())
            .contains { $0.suggestion.localizedCaseInsensitiveContains("associated with") }
        XCTAssertFalse(flagged)
    }

    func testLexiconMatchesWholeWordsOnly() {
        // "causes" must not match inside "becauses"/"because"-style longer words.
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "Obesity is a risk factor because insulin resistance develops.",
            answers: [QuizAnswer(text: "True", isCorrect: true), QuizAnswer(text: "False", isCorrect: false)],
            feedback: "Correct."
        )
        let flagged = linter.findings(for: question, persona: terminologyPersona())
            .contains { $0.suggestion.localizedCaseInsensitiveContains("associated with") }
        XCTAssertFalse(flagged)
    }

    func testGeneralHasNoLexiconFindings() {
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "Which factor causes type 2 diabetes?",
            answers: [QuizAnswer(text: "Obesity", isCorrect: true), QuizAnswer(text: "Cold weather", isCorrect: false)],
            feedback: "Obesity is a major risk factor."
        )
        // General carries no terminology, so it adds no lexicon findings.
        XCTAssertEqual(linter.findings(for: question, persona: .general), linter.findings(for: question))
    }
}
