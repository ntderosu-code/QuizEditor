import SwiftUI
import QuizEditorCore

/// Generates new questions from a topic or learning objective using the
/// configured AI provider, then lets the user accept any subset for insertion.
struct AIAuthoringSheet: View {
    let quizTitle: String
    /// The active persona, so authoring prompts carry its preamble, guidelines,
    /// distractor strategy, and exemplars.
    var persona: Persona = .general
    let onAdd: ([QuizQuestion]) -> Void
    @Environment(\.dismiss) private var dismiss

    @AppStorage("aiProvider") private var provider = AIProvider.openAICompatible
    @AppStorage("aiAPIKey") private var apiKey = ""
    @AppStorage("aiEndpoint") private var endpoint = "https://api.openai.com/v1/chat/completions"
    @AppStorage("aiModel") private var model = "gpt-4o-mini"

    @State private var topic = ""
    @State private var count = 3
    @State private var selectedTypes: Set<QuizQuestionType> = [.multipleChoice]
    @State private var additional = ""
    @State private var isRunning = false
    @State private var errorMessage: String?
    @State private var generated: [GeneratedItem] = []
    @State private var pastedResponse = ""

    private let service = QuestionAuthoringService()
    private let html = HTMLUtilities()

    private struct GeneratedItem: Identifiable {
        let id = UUID()
        let question: QuizQuestion
    }

    private var runner: ConfiguredAIRunner {
        ConfiguredAIRunner(provider: provider, apiKey: apiKey, endpoint: endpoint, model: model)
    }

    private var types: [QuizQuestionType] {
        selectedTypes.isEmpty ? [] : QuizQuestionType.allCases.filter { selectedTypes.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Author with AI")
                .font(.title2.bold())
                .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    inputSection
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if provider == .copyPaste {
                        pasteSection
                    }
                    if !generated.isEmpty {
                        resultsSection
                    }
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .frame(minWidth: 620, minHeight: 640)
    }

    // MARK: - Sections

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledField("Topic or learning objective") {
                TextEditor(text: $topic)
                    .frame(minHeight: 70)
                    .font(.body)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                    .accessibilityLabel("Topic or learning objective")
            }

            HStack(alignment: .center, spacing: 20) {
                LabeledField("How many") {
                    Stepper(value: $count, in: 1...10) {
                        Text("\(count) question\(count == 1 ? "" : "s")")
                    }
                    .fixedSize()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Question types")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(QuizQuestionType.allCases) { type in
                        TypeChip(
                            title: type.displayName,
                            isOn: selectedTypes.contains(type)
                        ) {
                            if selectedTypes.contains(type) { selectedTypes.remove(type) }
                            else { selectedTypes.insert(type) }
                        }
                    }
                }
            }

            LabeledField("Extra instructions (optional)") {
                TextField("e.g. focus on application, not recall", text: $additional)
                    .textFieldStyle(.roundedBorder)
            }

            if !persona.exemplars.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(persona.exemplars.enumerated()), id: \.offset) { _, exemplar in
                            Label {
                                Text(exemplar)
                                    .font(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "star")
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                } label: {
                    Label("What a strong \(persona.displayName) item looks like", systemImage: "lightbulb")
                        .font(.caption)
                }
            }

            HStack {
                Button {
                    generate()
                } label: {
                    if isRunning {
                        ProgressView().controlSize(.small)
                        Text("Generating…")
                    } else {
                        Label(provider == .copyPaste ? "Copy Prompt" : "Generate", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning || topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Text(providerHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pasteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Paste the model's JSON response")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $pastedResponse)
                .frame(minHeight: 100)
                .font(.body.monospaced())
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(.rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                .accessibilityLabel("Pasted model response")
            Button("Parse Response") { parse(pastedResponse) }
                .disabled(pastedResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Generated questions — review before adding")
                .font(.headline)
            Text("Each question is reviewed here before it enters your quiz. Edit anything after adding.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(generated) { item in
                GeneratedQuestionCard(question: item.question, plainPrompt: plainPrompt(item.question)) {
                    onAdd([item.question])
                    generated.removeAll { $0.id == item.id }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if !generated.isEmpty {
                Text("\(generated.count) ready to add")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Add All") {
                onAdd(generated.map(\.question))
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(generated.isEmpty)
        }
        .padding(20)
    }

    private var providerHint: String {
        switch provider {
        case .openAICompatible: "Uses your configured API."
        case .foundationModels: "Runs on-device with Apple Intelligence."
        case .copyPaste: "Copies a prompt for Claude/ChatGPT; paste the reply below."
        }
    }

    // MARK: - Actions

    private func generate() {
        errorMessage = nil
        let prompt = service.makeGenerationPrompt(
            topic: topic,
            count: count,
            types: types,
            additionalInstructions: additional,
            persona: persona
        )

        if provider == .copyPaste {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(service.systemInstruction(persona: persona) + "\n\n" + prompt, forType: .string)
            errorMessage = nil
            return
        }

        isRunning = true
        let runner = self.runner
        let systemInstruction = service.systemInstruction(persona: persona)
        Task {
            do {
                let raw = try await runner.runQuestions(system: systemInstruction, user: prompt, temperature: 0.7)
                await MainActor.run {
                    isRunning = false
                    parse(raw)
                }
            } catch {
                await MainActor.run {
                    isRunning = false
                    errorMessage = "Generation failed: \(error)"
                }
            }
        }
    }

    private func parse(_ raw: String) {
        let questions = service.parseGeneratedQuestions(raw)
        if questions.isEmpty {
            errorMessage = "Couldn't read any questions from the response. Check the format and try again."
        } else {
            errorMessage = nil
            generated = questions.map { GeneratedItem(question: $0) }
        }
    }

    private func plainPrompt(_ question: QuizQuestion) -> String {
        let text = html.plainText(fromHTML: question.prompt)
        return text.isEmpty ? "Untitled question" : text
    }
}

private struct TypeChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .accessibilityHidden(true)
                Text(title)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isOn ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1))
            .clipShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

private struct GeneratedQuestionCard: View {
    let question: QuizQuestion
    let plainPrompt: String
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(question.type.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add", action: onAdd)
                    .buttonStyle(.bordered)
            }
            Text(plainPrompt)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if question.type == .matching {
                ForEach(question.matches) { pair in
                    Text("• \(pair.prompt) → \(pair.match)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(question.answers) { answer in
                    Label(answer.text, systemImage: answer.isCorrect ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(answer.isCorrect ? .green : .secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 10))
    }
}
