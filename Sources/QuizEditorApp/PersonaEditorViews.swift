import SwiftUI
import QuizEditorCore

/// Persona families offered in the editor, paired with their display names.
private let personaFamilies = ["general", "health", "science", "stem", "social-science", "humanities"]

/// A guided editor for a user persona (#24). Built-in packs are read-only; the
/// management sheet forks them to a user copy before editing. No JSON required;
/// every section maps a persona field to native controls.
struct PersonaEditorSheet: View {
    @State private var draft: Persona
    let onSave: (Persona) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var editingRule: PersonaLinterRule?
    @State private var isAddingRule = false

    init(persona: Persona, onSave: @escaping (Persona) -> Void) {
        _draft = State(initialValue: persona)
        self.onSave = onSave
    }

    private var canSave: Bool {
        !draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader("Edit Persona", systemImage: "person.crop.rectangle.badge.plus")
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    identitySection
                    Divider()
                    builtInRulesSection
                    Divider()
                    declarativeRulesSection
                    Divider()
                    aiProfileSection
                    Divider()
                    terminologySection
                    Divider()
                    exemplarsSection
                    Divider()
                    itemTypesSection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            sheetFooter(canSave: canSave) {
                onSave(draft)
                dismiss()
            } onCancel: { dismiss() }
        }
        .frame(minWidth: 620, minHeight: 640)
        .sheet(item: $editingRule) { rule in
            DeclarativeRuleForm(rule: rule) { saved in upsertRule(saved) }
        }
        .sheet(isPresented: $isAddingRule) {
            DeclarativeRuleForm(rule: PersonaLinterRule(id: "", message: "", suggestion: "")) { saved in upsertRule(saved) }
        }
    }

    // MARK: - Identity

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Identity")
            LabeledField("Name") {
                TextField("Persona name", text: $draft.displayName)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledTextEditor(title: "Summary", text: $draft.summary, minHeight: 60, placeholder: "What this persona is for.")
            LabeledField("Family") {
                Picker("Family", selection: $draft.family) {
                    ForEach(personaFamilies, id: \.self) { family in
                        Text(personaFamilyName(family)).tag(family)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            if let base = draft.basePersonaID {
                Text("Extends: \(base)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Built-in rule overrides

    private var builtInRulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Built-in rules")
            Text("Turn built-in checks off or change how strongly they're flagged. Accessibility rules are always on and aren't listed here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(LintRuleCatalog.builtInRules, id: \.rule.rawValue) { info in
                BuiltInRuleRow(
                    info: info,
                    isEnabled: enabledBinding(info),
                    severity: severityBinding(info)
                )
            }
        }
    }

    private func enabledBinding(_ info: LintRuleInfo) -> Binding<Bool> {
        Binding(
            get: { draft.linterProfile.ruleOverrides[info.rule.rawValue]?.enabled ?? true },
            set: { updateOverride(info, enabled: $0, severity: currentSeverity(info)) }
        )
    }

    private func severityBinding(_ info: LintRuleInfo) -> Binding<PersonaSeverity> {
        Binding(
            get: { currentSeverity(info) },
            set: { updateOverride(info, enabled: currentEnabled(info), severity: $0) }
        )
    }

    private func currentEnabled(_ info: LintRuleInfo) -> Bool {
        draft.linterProfile.ruleOverrides[info.rule.rawValue]?.enabled ?? true
    }

    private func currentSeverity(_ info: LintRuleInfo) -> PersonaSeverity {
        draft.linterProfile.ruleOverrides[info.rule.rawValue]?.severity ?? defaultSeverity(info)
    }

    private func defaultSeverity(_ info: LintRuleInfo) -> PersonaSeverity {
        info.defaultSeverity == .warning ? .warning : .suggestion
    }

    /// Stores an override only when it differs from the default, so an unchanged
    /// rule leaves the persona JSON (and behavior) exactly as General's.
    private func updateOverride(_ info: LintRuleInfo, enabled: Bool, severity: PersonaSeverity) {
        if enabled, severity == defaultSeverity(info) {
            draft.linterProfile.ruleOverrides[info.rule.rawValue] = nil
        } else {
            draft.linterProfile.ruleOverrides[info.rule.rawValue] = PersonaRuleOverride(enabled: enabled, severity: severity)
        }
    }

    // MARK: - Declarative rules

    private var declarativeRulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("Discipline rules")
                Spacer()
                Button {
                    isAddingRule = true
                } label: {
                    Label("Add rule", systemImage: "plus.circle")
                }
            }
            Text("Rules expressed as data: require or forbid a pattern, gated by item type, difficulty, or linked stimulus/source.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if draft.linterProfile.declarativeRules.isEmpty {
                Text("No discipline rules yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(draft.linterProfile.declarativeRules) { rule in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.id.isEmpty ? "(unnamed rule)" : rule.id)
                                .font(.subheadline.weight(.semibold))
                            Text(rule.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button("Edit") { editingRule = rule }
                        Button(role: .destructive) {
                            draft.linterProfile.declarativeRules.removeAll { $0.id == rule.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Remove rule \(rule.id)")
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(.rect(cornerRadius: 8))
                }
            }
        }
    }

    private func upsertRule(_ rule: PersonaLinterRule) {
        guard !rule.id.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let index = draft.linterProfile.declarativeRules.firstIndex(where: { $0.id == rule.id }) {
            draft.linterProfile.declarativeRules[index] = rule
        } else {
            draft.linterProfile.declarativeRules.append(rule)
        }
    }

    // MARK: - AI profile

    private var aiProfileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("AI guidance")
            LabeledTextEditor(title: "System preamble", text: $draft.aiProfile.systemPreamble, minHeight: 60, placeholder: "e.g. Adopt the perspective of a nurse educator.")
            StringListEditor(title: "Review guidelines", items: $draft.aiProfile.reviewGuidelines, placeholder: "Add a review guideline")
            StringListEditor(title: "Authoring guidelines", items: $draft.aiProfile.authoringGuidelines, placeholder: "Add an authoring guideline")
            StringListEditor(title: "Feedback guidelines", items: $draft.aiProfile.feedbackGuidelines, placeholder: "Add a feedback guideline")
            LabeledField("Distractor strategy") {
                TextField("e.g. Each distractor is a plausible-but-unsafe action.", text: optionalText($draft.aiProfile.distractorStrategy))
                    .textFieldStyle(.roundedBorder)
            }
            Toggle("Label generated distractors with the misconception they target", isOn: $draft.aiProfile.labelsMisconceptions)
            LabeledField("Tone") {
                TextField("e.g. Formal, clinical.", text: optionalText($draft.aiProfile.tone))
                    .textFieldStyle(.roundedBorder)
            }
            StringListEditor(title: "Safety clauses", items: $draft.aiProfile.safetyClauses, placeholder: "e.g. Never invent drug doses.")
            LabeledField("Temperature override (optional)") {
                TextField("e.g. 0.1", text: temperatureText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }
            Toggle("Check for recall-drift (apply/analyze objective, recall-only stem)", isOn: $draft.linterProfile.checksRecallDrift)
            Toggle("Require a linked competency (flag items mapped to no framework)", isOn: $draft.linterProfile.requiresCompetency)
            Toggle("Require an expected unit on numeric items", isOn: $draft.linterProfile.requiresNumericUnit)
        }
    }

    // MARK: - Terminology

    private var terminologySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("Terminology")
                Spacer()
                Button {
                    draft.terminology.append(PersonaTerminologyRule(preferred: ""))
                } label: {
                    Label("Add term", systemImage: "plus.circle")
                }
            }
            ForEach(Array(draft.terminology.enumerated()), id: \.offset) { index, _ in
                TerminologyRowEditor(entry: $draft.terminology[index]) {
                    draft.terminology.remove(at: index)
                }
            }
        }
    }

    // MARK: - Exemplars

    private var exemplarsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Exemplars")
            StringListEditor(title: "Examples of strong items", items: $draft.exemplars, placeholder: "Describe a strong item")
        }
    }

    // MARK: - Item types

    private var itemTypesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Default & preferred item types")
            LabeledField("Default type") {
                Picker("Default type", selection: $draft.itemTypeProfile.defaultType) {
                    Text("None").tag(QuizQuestionType?.none)
                    ForEach(QuizQuestionType.allCases) { type in
                        Text(type.displayName).tag(QuizQuestionType?.some(type))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Preferred types")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(QuizQuestionType.allCases) { type in
                        let isOn = draft.itemTypeProfile.preferredTypes.contains(type)
                        Button {
                            if isOn { draft.itemTypeProfile.preferredTypes.removeAll { $0 == type } }
                            else { draft.itemTypeProfile.preferredTypes.append(type) }
                        } label: {
                            Label(type.displayName, systemImage: isOn ? "checkmark.circle.fill" : "circle")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((isOn ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12)))
                        .clipShape(.capsule)
                        .accessibilityLabel("\(type.displayName)\(isOn ? ", selected" : "")")
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }

    /// A binding that presents an optional string as a plain string (empty → nil).
    private func optionalText(_ source: Binding<String?>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue ?? "" },
            set: { source.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }

    private var temperatureText: Binding<String> {
        Binding(
            get: { draft.aiProfile.temperatureOverride.map { String($0) } ?? "" },
            set: { draft.aiProfile.temperatureOverride = Double($0) }
        )
    }
}

/// One built-in rule row: an enable toggle plus a severity picker. Severity is
/// labeled text, never conveyed by color alone.
struct BuiltInRuleRow: View {
    let info: LintRuleInfo
    @Binding var isEnabled: Bool
    @Binding var severity: PersonaSeverity

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle(isOn: $isEnabled) { Text(info.label).font(.subheadline.weight(.semibold)) }
                Spacer()
                Picker("Severity", selection: $severity) {
                    Text("Suggestion").tag(PersonaSeverity.suggestion)
                    Text("Warning").tag(PersonaSeverity.warning)
                }
                .labelsHidden()
                .fixedSize()
                .disabled(!isEnabled)
            }
            Text(info.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
    }
}

/// An add/remove list of free-text bullet strings.
struct StringListEditor: View {
    let title: String
    @Binding var items: [String]
    var placeholder: String = "Add an item"

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top) {
                    Text("•").foregroundStyle(.secondary).accessibilityHidden(true)
                    Text(item).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(role: .destructive) {
                        items.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(item)")
                }
            }
            HStack {
                TextField(placeholder, text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func add() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(trimmed)
        draft = ""
    }
}

/// Edits one terminology rule: a preferred term, its discouraged variants, and a
/// rationale.
struct TerminologyRowEditor: View {
    @Binding var entry: PersonaTerminologyRule
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                LabeledField("Prefer") {
                    TextField("preferred term", text: $entry.preferred)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField("Instead of") {
                    TextField("comma, separated", text: discouragedText)
                        .textFieldStyle(.roundedBorder)
                }
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove terminology rule")
            }
            TextField("Rationale (optional)", text: rationaleText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
    }

    private var discouragedText: Binding<String> {
        Binding(
            get: { entry.discouraged.joined(separator: ", ") },
            set: { entry.discouraged = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        )
    }

    private var rationaleText: Binding<String> {
        Binding(
            get: { entry.rationale ?? "" },
            set: { entry.rationale = $0.isEmpty ? nil : $0 }
        )
    }
}

/// A guided form for one declarative rule, so non-programmers can express a
/// discipline check without writing JSON.
struct DeclarativeRuleForm: View {
    @State private var draft: PersonaLinterRule
    let onSave: (PersonaLinterRule) -> Void
    @Environment(\.dismiss) private var dismiss

    private let scopes = ["stem", "options", "feedback"]

    init(rule: PersonaLinterRule, onSave: @escaping (PersonaLinterRule) -> Void) {
        _draft = State(initialValue: rule)
        self.onSave = onSave
    }

    private var canSave: Bool {
        !draft.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader("Discipline Rule", systemImage: "ruler")
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LabeledField("Rule id") {
                        TextField("e.g. sataCountCue", text: $draft.id)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledField("Scope") {
                        Picker("Scope", selection: $draft.scope) {
                            ForEach(scopes, id: \.self) { Text($0.capitalized).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    LabeledField("Require this pattern (fires when absent)") {
                        TextField("regex or text, optional", text: optional($draft.requiresPattern))
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledField("Forbid this pattern (fires when present)") {
                        TextField("regex or text, optional", text: optional($draft.forbidsPattern))
                            .textFieldStyle(.roundedBorder)
                    }
                    Toggle("Fire when no stimulus is linked", isOn: $draft.requiresStimulus)
                    Toggle("Fire when no source is linked", isOn: $draft.requiresSource)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Only these item types (none = all)")
                            .font(.caption).foregroundStyle(.secondary)
                        FlowLayout(spacing: 6) {
                            ForEach(QuizQuestionType.allCases) { type in
                                let isOn = draft.itemTypes.contains(type)
                                Button {
                                    if isOn { draft.itemTypes.removeAll { $0 == type } } else { draft.itemTypes.append(type) }
                                } label: {
                                    Label(type.displayName, systemImage: isOn ? "checkmark.circle.fill" : "circle").font(.caption)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(isOn ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                                .clipShape(.capsule)
                                .accessibilityLabel("\(type.displayName)\(isOn ? ", selected" : "")")
                            }
                        }
                    }

                    LabeledField("Severity") {
                        Picker("Severity", selection: $draft.severity) {
                            Text("Suggestion").tag(PersonaSeverity.suggestion)
                            Text("Warning").tag(PersonaSeverity.warning)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    LabeledTextEditor(title: "Message", text: $draft.message, minHeight: 50, placeholder: "What's wrong, in plain language.")
                    LabeledTextEditor(title: "Suggestion", text: $draft.suggestion, minHeight: 50, placeholder: "How to fix it.")
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            sheetFooter(canSave: canSave) {
                draft.id = draft.id.trimmingCharacters(in: .whitespacesAndNewlines)
                onSave(draft)
                dismiss()
            } onCancel: { dismiss() }
        }
        .frame(minWidth: 520, minHeight: 560)
    }

    private func optional(_ source: Binding<String?>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue ?? "" },
            set: { source.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}
