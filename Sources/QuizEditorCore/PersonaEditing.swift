import Foundation

// MARK: - Forking

public extension Persona {
    /// Returns an editable user copy: a fresh id, `isBuiltIn` false, and
    /// `basePersonaID` pointing at this persona so the fork *composes on top of it*
    /// rather than copying its profiles. Because resolution appends the base's
    /// guideline bullets, exemplars, and rules, the fork starts with empty profiles
    /// (so it resolves identically to its source, with no duplication) and the user
    /// layers their own additions on top. Only display metadata is carried over.
    func fork() -> Persona {
        Persona(
            id: "user.\(UUID().uuidString.lowercased())",
            displayName: "\(displayName) (Copy)",
            family: family,
            summary: summary,
            basePersonaID: id,
            isBuiltIn: false
        )
    }
}

// MARK: - Built-in rule catalog

/// Describes one built-in linter rule for the persona editor's override UI.
public struct LintRuleInfo: Sendable, Equatable {
    public let rule: LintFinding.Rule
    public let label: String
    public let summary: String
    public let defaultSeverity: LintFinding.Severity

    public init(rule: LintFinding.Rule, label: String, summary: String, defaultSeverity: LintFinding.Severity) {
        self.rule = rule
        self.label = label
        self.summary = summary
        self.defaultSeverity = defaultSeverity
    }
}

/// The built-in linter rules a persona may enable, disable, or re-weight, with the
/// human labels the editor shows. Non-overridable (accessibility/platform) rules
/// are excluded so the editor can never disable them.
public enum LintRuleCatalog {
    public static let builtInRules: [LintRuleInfo] = allRules.filter {
        !QuestionLinter.nonOverridableRuleIDs.contains($0.rule)
    }

    private static let allRules: [LintRuleInfo] = [
        LintRuleInfo(rule: .noCorrectAnswer, label: "No correct answer marked",
                     summary: "Flags a question with no option (or accepted answer) marked correct.", defaultSeverity: .warning),
        LintRuleInfo(rule: .multipleCorrectAnswers, label: "Multiple correct on single-answer",
                     summary: "Flags more than one correct option on a single-answer question.", defaultSeverity: .warning),
        LintRuleInfo(rule: .allOrNoneOfTheAbove, label: "“All/none of the above”",
                     summary: "Discourages “all/none of the above” options, which cue test-wise guessing.", defaultSeverity: .suggestion),
        LintRuleInfo(rule: .unemphasizedNegativeStem, label: "Unemphasized negative stem",
                     summary: "Flags a NOT/EXCEPT stem where the negative word is not emphasized.", defaultSeverity: .suggestion),
        LintRuleInfo(rule: .longestOptionIsCorrect, label: "Longest option is correct",
                     summary: "Flags a length cue when the correct option is noticeably longer.", defaultSeverity: .suggestion),
        LintRuleInfo(rule: .duplicateOptions, label: "Duplicate options",
                     summary: "Flags two or more options with identical text.", defaultSeverity: .warning),
        LintRuleInfo(rule: .emptyOption, label: "Empty option",
                     summary: "Flags a blank answer option or matching pair.", defaultSeverity: .warning),
        LintRuleInfo(rule: .missingFeedback, label: "Missing feedback",
                     summary: "Flags a question with no feedback for students.", defaultSeverity: .suggestion),
        LintRuleInfo(rule: .articleCue, label: "Article cue (a/an)",
                     summary: "Flags a stem ending in “a”/“an”, which can grammatically cue the answer.", defaultSeverity: .suggestion)
    ]
}

// MARK: - Import

public struct PersonaImportResult: Sendable {
    public let persona: Persona
    /// Human-readable, non-fatal warnings (e.g. unknown fields from a newer schema).
    public let warnings: [String]

    public init(persona: Persona, warnings: [String]) {
        self.persona = persona
        self.warnings = warnings
    }
}

public extension Persona {
    /// Known top-level keys, so import can warn about anything else (forward-compatible).
    private static let knownKeys: Set<String> = [
        "id", "displayName", "family", "version", "summary", "basePersonaID",
        "linterProfile", "aiProfile", "itemTypeProfile", "terminology", "exemplars",
        "linkingPresets", "isBuiltIn"
    ]

    /// Decodes a persona from `.qepersona`/JSON data, surfacing warnings for unknown
    /// top-level keys. Throws only when required fields (`id`, `displayName`) are
    /// missing — unknown fields are tolerated, never fatal.
    static func importResult(fromJSON data: Data) throws -> PersonaImportResult {
        let persona = try JSONDecoder().decode(Persona.self, from: data)

        var warnings: [String] = []
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let unknown = object.keys.filter { !knownKeys.contains($0) }.sorted()
            if !unknown.isEmpty {
                warnings.append("Ignored unknown field\(unknown.count == 1 ? "" : "s"): \(unknown.joined(separator: ", ")). They may be from a newer version of QuizEditor.")
            }
        }
        return PersonaImportResult(persona: persona, warnings: warnings)
    }
}
