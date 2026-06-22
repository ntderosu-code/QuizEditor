import Foundation

/// Shared helpers that fold an active persona's AI profile and a question's linked
/// context into prompts (#21). Every addition is append-only and empty for the
/// General persona / an empty context, so prompts stay byte-identical to today
/// unless a discipline persona or links are actually in play.
enum PersonaPrompt {
    static func bullets(_ items: [String]) -> String {
        items.map { "- \($0)" }.joined(separator: "\n")
    }

    /// Prepends the persona's system preamble to a base reviewer/author role.
    /// Returns `base` unchanged when the preamble is empty (General).
    static func systemInstruction(base: String, persona: Persona) -> String {
        let preamble = persona.aiProfile.systemPreamble.trimmingCharacters(in: .whitespacesAndNewlines)
        return preamble.isEmpty ? base : "\(preamble)\n\n\(base)"
    }

    /// A labelled trailer of guideline bullets, empty when `guidelines` is empty.
    static func guidelineSection(title: String, _ guidelines: [String]) -> String {
        guard !guidelines.isEmpty else { return "" }
        return "\n\n\(title)\n\(bullets(guidelines))"
    }

    /// The safety-clause trailer, empty when there are no clauses.
    static func safetySection(_ clauses: [String]) -> String {
        guard !clauses.isEmpty else { return "" }
        return "\n\nSafety constraints (do not violate):\n\(bullets(clauses))"
    }

    /// A single free-text trailer (e.g. distractor strategy), empty when blank.
    static func textSection(title: String, _ text: String?) -> String {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return "" }
        return "\n\n\(title) \(text)"
    }

    /// The linked-context trailer (stimulus, sources, objectives), empty when the
    /// context is empty. When sources are present the model is told to defer to them.
    static func linkedContextSection(_ context: PromptLinkContext) -> String {
        guard !context.isEmpty else { return "" }
        var lines = ["Linked context for this item — review the whole item, not just the stem:"]
        if let stimulus = context.stimulus, !stimulus.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("\(stimulus.kind.displayName): \(stimulus.body)")
            if let alt = stimulus.altText?.trimmingCharacters(in: .whitespacesAndNewlines), !alt.isEmpty {
                lines.append("Figure alt text: \(alt)")
            }
            if let table = stimulus.dataTable?.trimmingCharacters(in: .whitespacesAndNewlines), !table.isEmpty {
                lines.append("Data: \(table)")
            }
        }
        if !context.sources.isEmpty {
            lines.append("Linked sources — defer to these; do not fabricate facts, doses, or citations beyond them:")
            lines.append(contentsOf: context.sources.map { "- \($0.shortLabel)" })
        }
        if !context.objectives.isEmpty {
            lines.append("Aligned objectives:")
            lines.append(contentsOf: context.objectives.map { objective in
                let level = objective.cognitiveLevel.map { " [\($0.displayName)]" } ?? ""
                return "- \(objective.text)\(level)"
            })
        }
        if !context.competencies.isEmpty {
            lines.append("Aligned competencies:")
            lines.append(contentsOf: context.competencies.map { "- \($0)" })
        }
        return "\n\n" + lines.joined(separator: "\n")
    }
}
