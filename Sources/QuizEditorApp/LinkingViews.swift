import SwiftUI
import AppKit
import QuizEditorCore

/// The question's linking section (issue #23): attach learning objectives, source
/// materials, and one shared case/vignette stimulus. Objectives and sources are
/// authored once on the quiz and reused across items; a stimulus edited here
/// propagates to every question that references it. All of this is author metadata
/// and is never written into an export.
struct QuestionLinkingSection: View {
    @Binding var question: QuizQuestion
    @Binding var objectives: [LearningObjective]
    @Binding var sources: [Source]
    @Binding var stimuli: [Stimulus]

    @State private var editingObjective: LearningObjective?
    @State private var editingSource: Source?
    @State private var editingStimulus: Stimulus?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                objectivesSubsection
                Divider()
                sourcesSubsection
                Divider()
                stimulusSubsection

                Text("Links help the linter and AI reason about the whole item and power competency-coverage reports. They are author metadata and are not exported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Label("Links", systemImage: "link")
        }
        .sheet(item: $editingObjective) { objective in
            ObjectiveEditorSheet(objective: objective) { saved in upsertObjective(saved, linkToQuestion: true) }
        }
        .sheet(item: $editingSource) { source in
            SourceEditorSheet(source: source) { saved in upsertSource(saved, linkToQuestion: true) }
        }
        .sheet(item: $editingStimulus) { stimulus in
            StimulusEditorSheet(stimulus: stimulus) { saved in upsertStimulus(saved, attachToQuestion: true) }
        }
    }

    // MARK: - Objectives

    private var linkedObjectives: [LearningObjective] {
        question.objectiveIDs.compactMap { id in objectives.first { $0.id == id } }
    }

    private var objectivesSubsection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Learning objectives")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Menu {
                    ForEach(objectives) { objective in
                        Toggle(isOn: bindingForObjectiveLink(objective.id)) {
                            Text(objective.text.isEmpty ? "Untitled objective" : objective.text)
                        }
                    }
                    if !objectives.isEmpty { Divider() }
                    Button("New objective…") { editingObjective = LearningObjective() }
                } label: {
                    Label("Link objective", systemImage: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Attach a learning objective to this question")
            }

            if linkedObjectives.isEmpty {
                emptyHint("No objectives linked.")
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(linkedObjectives) { objective in
                        RemovableChip(
                            text: objectiveChipText(objective),
                            accessibilityLabel: "Objective: \(objective.text). \(objective.cognitiveLevel?.displayName ?? "No cognitive level"). Activate to edit, or remove.",
                            onEdit: { editingObjective = objective },
                            onRemove: { question.objectiveIDs.removeAll { $0 == objective.id } }
                        )
                    }
                }
            }
        }
    }

    private func objectiveChipText(_ objective: LearningObjective) -> String {
        let level = objective.cognitiveLevel.map { " · \($0.displayName)" } ?? ""
        let text = objective.text.isEmpty ? "Untitled objective" : objective.text
        return text + level
    }

    private func bindingForObjectiveLink(_ id: String) -> Binding<Bool> {
        Binding(
            get: { question.objectiveIDs.contains(id) },
            set: { isOn in
                if isOn {
                    if !question.objectiveIDs.contains(id) { question.objectiveIDs.append(id) }
                } else {
                    question.objectiveIDs.removeAll { $0 == id }
                }
            }
        )
    }

    private func upsertObjective(_ objective: LearningObjective, linkToQuestion: Bool) {
        if let index = objectives.firstIndex(where: { $0.id == objective.id }) {
            objectives[index] = objective
        } else {
            objectives.append(objective)
        }
        if linkToQuestion, !question.objectiveIDs.contains(objective.id) {
            question.objectiveIDs.append(objective.id)
        }
    }

    // MARK: - Sources

    private var linkedSources: [Source] {
        question.sourceIDs.compactMap { id in sources.first { $0.id == id } }
    }

    private var sourcesSubsection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sources")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Menu {
                    ForEach(sources) { source in
                        Toggle(isOn: bindingForSourceLink(source.id)) {
                            Text(source.shortLabel)
                        }
                    }
                    if !sources.isEmpty { Divider() }
                    Button("New source…") { editingSource = Source() }
                } label: {
                    Label("Link source", systemImage: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Attach a source material to this question")
            }

            if linkedSources.isEmpty {
                emptyHint("No sources linked.")
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(linkedSources) { source in
                        RemovableChip(
                            text: source.shortLabel,
                            accessibilityLabel: "Source: \(source.shortLabel). Activate to edit, or remove.",
                            onEdit: { editingSource = source },
                            onRemove: { question.sourceIDs.removeAll { $0 == source.id } }
                        )
                    }
                }
            }
        }
    }

    private func bindingForSourceLink(_ id: String) -> Binding<Bool> {
        Binding(
            get: { question.sourceIDs.contains(id) },
            set: { isOn in
                if isOn {
                    if !question.sourceIDs.contains(id) { question.sourceIDs.append(id) }
                } else {
                    question.sourceIDs.removeAll { $0 == id }
                }
            }
        )
    }

    private func upsertSource(_ source: Source, linkToQuestion: Bool) {
        if let index = sources.firstIndex(where: { $0.id == source.id }) {
            sources[index] = source
        } else {
            sources.append(source)
        }
        if linkToQuestion, !question.sourceIDs.contains(source.id) {
            question.sourceIDs.append(source.id)
        }
    }

    // MARK: - Stimulus (single, shared)

    private var attachedStimulus: Stimulus? {
        guard let id = question.stimulusID else { return nil }
        return stimuli.first { $0.id == id }
    }

    private var stimulusSubsection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Stimulus")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Menu {
                    ForEach(stimuli) { stimulus in
                        Button {
                            question.stimulusID = stimulus.id
                        } label: {
                            Label(stimulusMenuLabel(stimulus), systemImage: question.stimulusID == stimulus.id ? "checkmark" : "")
                        }
                    }
                    if !stimuli.isEmpty { Divider() }
                    Button("New stimulus…") { editingStimulus = Stimulus() }
                    if question.stimulusID != nil {
                        Divider()
                        Button("Detach", role: .destructive) { question.stimulusID = nil }
                    }
                } label: {
                    Label(question.stimulusID == nil ? "Attach stimulus" : "Change", systemImage: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Attach a shared case, vignette, passage, or figure")
            }

            if let stimulus = attachedStimulus {
                StimulusPreviewCard(
                    stimulus: stimulus,
                    onEdit: { editingStimulus = stimulus }
                )
            } else {
                emptyHint("No stimulus attached. A stimulus authored here can be reused by other questions.")
            }
        }
    }

    private func stimulusMenuLabel(_ stimulus: Stimulus) -> String {
        let snippet = stimulus.body.split(separator: "\n").first.map(String.init) ?? ""
        let trimmed = snippet.count > 48 ? String(snippet.prefix(48)) + "…" : snippet
        return "\(stimulus.kind.displayName): \(trimmed.isEmpty ? "Untitled" : trimmed)"
    }

    private func upsertStimulus(_ stimulus: Stimulus, attachToQuestion: Bool) {
        if let index = stimuli.firstIndex(where: { $0.id == stimulus.id }) {
            stimuli[index] = stimulus
        } else {
            stimuli.append(stimulus)
        }
        if attachToQuestion { question.stimulusID = stimulus.id }
    }

    // MARK: - Shared

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A capsule chip with an edit action (the chip body) and a remove button. State
/// is conveyed by text and the trash glyph, never color alone.
struct RemovableChip: View {
    let text: String
    let accessibilityLabel: String
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onEdit) {
                Text(text)
                    .font(.caption)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help("Edit")

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove")
            .accessibilityLabel("Remove \(text)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.15))
        .clipShape(.capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// A read-only summary of an attached stimulus, with an Edit button. Surfaces a
/// missing-alt-text warning with an icon and text so it is never color-only.
struct StimulusPreviewCard: View {
    let stimulus: Stimulus
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(stimulus.kind.displayName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(.capsule)
                Spacer()
                Button("Edit", action: onEdit)
                    .help("Edit this stimulus (changes apply to every question using it)")
            }

            if !stimulus.body.isEmpty {
                Text(stimulus.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if stimulus.figureImage != nil {
                Label(
                    stimulus.figureNeedsAltText ? "Figure attached — needs alt text" : "Figure attached, with alt text",
                    systemImage: stimulus.figureNeedsAltText ? "exclamationmark.triangle.fill" : "photo"
                )
                .font(.caption)
                .foregroundStyle(stimulus.figureNeedsAltText ? .orange : .secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.18)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Editor sheets

/// Creates or edits a learning objective: its text and Bloom cognitive level.
struct ObjectiveEditorSheet: View {
    @State private var draft: LearningObjective
    let onSave: (LearningObjective) -> Void
    @Environment(\.dismiss) private var dismiss

    init(objective: LearningObjective, onSave: @escaping (LearningObjective) -> Void) {
        _draft = State(initialValue: objective)
        self.onSave = onSave
    }

    private var canSave: Bool {
        !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader("Learning Objective", systemImage: "target")
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LabeledTextEditor(title: "Objective", text: $draft.text, minHeight: 80, placeholder: "By the end of this unit, students will be able to…")

                    LabeledField("Cognitive level (Bloom)") {
                        Picker("Cognitive level", selection: $draft.cognitiveLevel) {
                            Text("Unspecified").tag(CognitiveLevel?.none)
                            ForEach(CognitiveLevel.allCases) { level in
                                Text(level.displayName).tag(CognitiveLevel?.some(level))
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }

                    Text("The cognitive level lets the linter flag an item that only asks for recall when its objective expects higher-order thinking.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            sheetFooter(canSave: canSave) {
                draft.text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
                onSave(draft)
                dismiss()
            } onCancel: { dismiss() }
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}

/// Creates or edits a source material.
struct SourceEditorSheet: View {
    @State private var draft: Source
    let onSave: (Source) -> Void
    @Environment(\.dismiss) private var dismiss

    init(source: Source, onSave: @escaping (Source) -> Void) {
        _draft = State(initialValue: source)
        self.onSave = onSave
    }

    private var canSave: Bool {
        !draft.citation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draft.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader("Source", systemImage: "doc.text")
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LabeledField("Citation") {
                        TextField("Full citation as it should appear", text: $draft.citation)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack(spacing: 16) {
                        LabeledField("Author") {
                            TextField("Author", text: $draft.author)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledField("Date") {
                            TextField("Date", text: $draft.date)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                        }
                    }
                    HStack(spacing: 16) {
                        LabeledField("Place") {
                            TextField("Place", text: $draft.place)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledField("Type") {
                            Picker("Type", selection: $draft.type) {
                                Text("Unspecified").tag(SourceType?.none)
                                ForEach(SourceType.allCases) { type in
                                    Text(type.displayName).tag(SourceType?.some(type))
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
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
        .frame(minWidth: 520, minHeight: 360)
    }
}

/// Creates or edits a reusable stimulus. A figure requires alt text before it can
/// be saved, so accessibility is enforced at authoring time, not deferred.
struct StimulusEditorSheet: View {
    @State private var draft: Stimulus
    let onSave: (Stimulus) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var figureFileName: String?

    init(stimulus: Stimulus, onSave: @escaping (Stimulus) -> Void) {
        _draft = State(initialValue: stimulus)
        self.onSave = onSave
    }

    private var altText: Binding<String> {
        Binding(get: { draft.altText ?? "" }, set: { draft.altText = $0 })
    }

    private var dataTable: Binding<String> {
        Binding(get: { draft.dataTable ?? "" }, set: { draft.dataTable = $0.isEmpty ? nil : $0 })
    }

    /// A figure attached without alt text is the one thing that blocks saving.
    private var canSave: Bool { !draft.figureNeedsAltText }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader("Stimulus", systemImage: "rectangle.on.rectangle")
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("A stimulus is authored once and can be attached to many questions. Editing it updates every question that uses it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    LabeledField("Kind") {
                        Picker("Kind", selection: $draft.kind) {
                            ForEach(StimulusKind.allCases) { kind in
                                Text(kind.displayName).tag(kind)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }

                    LabeledTextEditor(title: "Body", text: $draft.body, minHeight: 140, placeholder: "The case, vignette, passage, code, or dataset description…")

                    LabeledField("Figure (optional)") {
                        HStack {
                            Button("Choose Image…", action: chooseFigure)
                            if draft.figureImage != nil {
                                Text(figureFileName ?? "Image attached")
                                    .font(.callout)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Button("Remove") {
                                    draft.figureImage = nil
                                    draft.altText = nil
                                    figureFileName = nil
                                }
                            } else {
                                Text("No image")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if draft.figureImage != nil {
                        LabeledField("Figure alt text (required)") {
                            TextField("Describe the figure for screen readers", text: altText)
                                .textFieldStyle(.roundedBorder)
                        }
                        if draft.figureNeedsAltText {
                            Label("Alt text is required for an attached figure and cannot be skipped.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    LabeledTextEditor(title: "Data table (optional)", text: dataTable, minHeight: 80, placeholder: "Tabular data, e.g. lab values, presented once for all linked items.")
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
        .frame(minWidth: 560, minHeight: 520)
    }

    private func chooseFigure() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        let mime = mimeTypeForImage(url.pathExtension.lowercased())
        figureFileName = url.lastPathComponent
        draft.figureImage = "data:\(mime);base64,\(data.base64EncodedString())"
    }
}

// MARK: - Shared sheet chrome

@ViewBuilder
func sheetHeader(_ title: String, systemImage: String) -> some View {
    HStack {
        Label(title, systemImage: systemImage)
            .font(.title2.bold())
        Spacer()
    }
    .padding(20)
}

@ViewBuilder
func sheetFooter(canSave: Bool, onSave: @escaping () -> Void, onCancel: @escaping () -> Void) -> some View {
    HStack {
        Spacer()
        Button("Cancel", action: onCancel)
            .keyboardShortcut(.cancelAction)
        Button("Save", action: onSave)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
    }
    .padding(20)
}

func mimeTypeForImage(_ ext: String) -> String {
    switch ext {
    case "png": "image/png"
    case "jpg", "jpeg": "image/jpeg"
    case "gif": "image/gif"
    case "svg": "image/svg+xml"
    case "webp": "image/webp"
    default: "image/png"
    }
}
