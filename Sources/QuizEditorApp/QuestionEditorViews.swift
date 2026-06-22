import SwiftUI
import UniformTypeIdentifiers
import AppKit
import WebKit
import QuizEditorCore
#if canImport(FoundationModels)
import FoundationModels
#endif

struct QuestionEditor: View {
    @Binding var question: QuizQuestion
    let quizTitle: String
    let questionNumber: Int
    let questionTotal: Int
    /// The quiz's reusable linking entities (issue #23), so this question can link
    /// to and create objectives, sources, and a shared stimulus.
    @Binding var objectives: [LearningObjective]
    @Binding var sources: [Source]
    @Binding var stimuli: [Stimulus]
    /// The competency frameworks, for the linking section's competency picker and
    /// for feeding competency labels to the AI.
    var frameworks: [Framework] = []
    /// The active persona, so the inline item-writing checks reflect the discipline.
    var persona: Persona = .general
    /// Opens the formatted preview for this question (owned by ContentView).
    var onPreview: () -> Void = {}
    let onDelete: () -> Void

    @AppStorage("aiProvider") private var provider = AIProvider.openAICompatible
    @AppStorage("aiAPIKey") private var apiKey = ""
    @AppStorage("aiEndpoint") private var endpoint = "https://api.openai.com/v1/chat/completions"
    @AppStorage("aiModel") private var model = "gpt-4o-mini"

    @State private var isReviewing = false
    @State private var reviewError: String?
    @State private var reviewPresentation: ReviewPresentation?
    @State private var undoSnapshot: QuizQuestion?
    @State private var isFeedbackExpanded = false
    @State private var isGenerating = false
    @State private var generationError: String?

    private var runner: ConfiguredAIRunner {
        ConfiguredAIRunner(provider: provider, apiKey: apiKey, endpoint: endpoint, model: model)
    }

    private var findings: [LintFinding] {
        QuestionLinter().findings(for: question, persona: persona)
    }

    /// A non-optional binding to the question's numeric spec, materializing a
    /// default when none exists yet.
    private var numericBinding: Binding<NumericAnswer> {
        Binding(
            get: { question.numeric ?? NumericAnswer() },
            set: { question.numeric = $0 }
        )
    }

    /// This question's links resolved into the quiz's actual entities, fed to the
    /// AI so it reviews the whole item (stimulus, sources, objectives).
    private var linkedContext: PromptLinkContext {
        PromptLinkContext(
            stimulus: question.stimulusID.flatMap { id in stimuli.first { $0.id == id } },
            sources: question.sourceIDs.compactMap { id in sources.first { $0.id == id } },
            objectives: question.objectiveIDs.compactMap { id in objectives.first { $0.id == id } },
            competencies: question.competencyIDs.compactMap { id in
                frameworks.lazy.compactMap { $0.node(withID: id)?.displayLabel }.first
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            stickyHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    QuestionReadinessView(readiness: QuestionReadiness(question: question))

                    QuestionMetadataEditor(question: $question)

                QuestionLinkingSection(
                    question: $question,
                    objectives: $objectives,
                    sources: $sources,
                    stimuli: $stimuli,
                    frameworks: frameworks
                )

                if let reviewError {
                    aiMessageBox(reviewError, title: "AI Review") { self.reviewError = nil }
                }

                if let generationError {
                    aiMessageBox(generationError, title: "AI Tools") { self.generationError = nil }
                }

                LintFindingsSection(findings: findings)

                RichTextField(title: "Prompt", text: $question.prompt, minHeight: 160)

                if question.type == .matching {
                    MatchingEditor(matches: $question.matches)
                } else if question.type == .numeric {
                    NumericAnswerEditor(numeric: numericBinding)
                } else if question.type != .essay {
                    AnswerEditor(question: $question)
                }

                DisclosureGroup(isExpanded: $isFeedbackExpanded) {
                    RichTextField(title: "Feedback", text: $question.feedback, minHeight: 140, showsTitle: false)
                        .padding(.top, 8)
                } label: {
                    Text("Feedback for students")
                        .font(.subheadline.weight(.semibold))
                }

                Divider()

                    QuestionTagsEditor(question: $question)
                }
                .padding(24)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .sheet(item: $reviewPresentation) { presentation in
            QuestionReviewSheet(review: presentation.review, original: question, onApply: applyEdit)
        }
    }

    // MARK: - Sticky header

    /// A compact, non-scrolling header: question position, type, readiness badge,
    /// and exactly one prominent question-level AI action (Review question).
    /// Preview and secondary/field actions live alongside it (an overflow menu)
    /// rather than as competing top-level buttons.
    private var stickyHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Question \(questionNumber) of \(questionTotal)")
                        .font(.headline)
                    ReadinessBadge(status: QuestionReadiness(question: question).status)
                }
                Text(question.type.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isGenerating {
                ProgressView().controlSize(.small)
            }

            Button(action: onPreview) {
                Label("Preview", systemImage: "eye")
            }
            .labelStyle(.iconOnly)
            .help("Preview this question (⇧⌘P)")

            Button {
                reviewQuestion()
            } label: {
                if isReviewing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Reviewing…")
                    }
                } else {
                    Label("Review question", systemImage: "sparkles")
                }
            }
            .disabled(isReviewing)
            .buttonStyle(.glassProminent)
            .foregroundStyle(.white)
            .fixedSize()
            .help("Review this question for item-writing quality and apply suggested edits")

            Menu {
                Button("Generate Distractors") { generateDistractors() }
                    .disabled(!canGenerateDistractors)
                Button("Generate Feedback") { generateFeedback() }
                if undoSnapshot != nil {
                    Divider()
                    Button("Undo AI Changes") { undoAIChanges() }
                }
                Divider()
                Button("Delete Question", role: .destructive, action: onDelete)
            } label: {
                Label("More actions", systemImage: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .labelStyle(.iconOnly)
            .fixedSize()
            .help("Generate distractors or feedback, undo AI edits, or delete this question")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func applyEdit(_ mutate: (inout QuizQuestion) -> Void) {
        if undoSnapshot == nil { undoSnapshot = question }
        mutate(&question)
    }

    private func undoAIChanges() {
        if let undoSnapshot { question = undoSnapshot }
        undoSnapshot = nil
    }

    @ViewBuilder
    private func aiMessageBox(_ message: String, title: String, onDismiss: @escaping () -> Void) -> some View {
        GroupBox {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Dismiss", action: onDismiss)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(title, systemImage: "sparkles")
        }
    }

    private var canGenerateDistractors: Bool {
        (question.type == .multipleChoice || question.type == .multipleAnswer)
            && question.answers.contains { $0.isCorrect }
    }

    /// Generates distractors for the current stem + correct answer and appends
    /// them through the same apply/undo path the AI review uses.
    private func generateDistractors() {
        guard let correct = question.answers.first(where: { $0.isCorrect })?.text,
              !correct.trimmingCharacters(in: .whitespaces).isEmpty else {
            generationError = "Mark a correct answer first so distractors can be contrasted against it."
            return
        }
        let service = QuestionAuthoringService()
        let stem = HTMLUtilities().plainText(fromHTML: question.prompt)
        let prompt = service.makeDistractorsPrompt(prompt: stem, correctAnswer: correct, count: 3, persona: persona)
        let system = service.systemInstruction(persona: persona)
        let temperature = persona.aiProfile.temperatureOverride ?? 0.7
        let labels = persona.aiProfile.labelsMisconceptions
        let runner = self.runner
        runGeneration(perform: { try await runner.runDistractors(system: system, user: prompt, labelsMisconceptions: labels, temperature: temperature) }) { raw in
            let distractors = service.parseLabeledDistractors(raw)
            guard !distractors.isEmpty else {
                generationError = "No distractors were returned. Try again or rephrase the stem."
                return
            }
            applyEdit { question in
                question.answers.append(contentsOf: distractors.map { QuizAnswer(text: $0.text, isCorrect: false, misconceptionTag: $0.misconception) })
            }
        }
    }

    private func generateFeedback() {
        let service = QuestionAuthoringService()
        let prompt = service.makeFeedbackPrompt(question: question, quizTitle: quizTitle, persona: persona, linkedContext: linkedContext)
        let system = service.systemInstruction(persona: persona)
        let temperature = persona.aiProfile.temperatureOverride ?? 0.4
        let runner = self.runner
        runGeneration(perform: { try await runner.runFeedback(system: system, user: prompt, temperature: temperature) }) { raw in
            guard let feedback = service.parseFeedback(raw) else {
                generationError = "No feedback was returned."
                return
            }
            applyEdit { $0.feedback = feedback }
            isFeedbackExpanded = true
        }
    }

    private func runGeneration(perform: @escaping () async throws -> String, apply: @escaping (String) -> Void) {
        generationError = nil
        guard runner.supportsAutoRun else {
            generationError = "Switch to the API or Apple Foundation Models provider to generate here, or use Author with AI for copy/paste."
            return
        }
        isGenerating = true
        Task {
            do {
                let raw = try await perform()
                await MainActor.run {
                    isGenerating = false
                    apply(raw)
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    generationError = "AI request failed: \(error)"
                }
            }
        }
    }

    private func reviewQuestion() {
        let service = QuestionReviewService()
        let prompt = service.makePrompt(question: question, quizTitle: quizTitle, persona: persona, linkedContext: linkedContext)
        let systemInstruction = service.systemInstruction(persona: persona)
        let snapshot = question
        let temperature = persona.aiProfile.temperatureOverride ?? 0.2
        reviewError = nil
        isReviewing = true

        let runner = self.runner
        Task {
            do {
                let raw = try await runner.runReview(system: systemInstruction, user: prompt, temperature: temperature)
                let review = service.parse(raw, original: snapshot)
                await MainActor.run {
                    isReviewing = false
                    reviewPresentation = ReviewPresentation(review: review)
                }
            } catch {
                await MainActor.run {
                    isReviewing = false
                    reviewError = "\(error)"
                }
            }
        }
    }

}

struct ReviewPresentation: Identifiable {
    let id = UUID()
    let review: QuestionReview
}

struct QuestionReviewSheet: View {
    let review: QuestionReview
    /// The question as it was when the review opened — the "before" side of each diff.
    let original: QuizQuestion
    let onApply: (@escaping (inout QuizQuestion) -> Void) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Label("AI Review", systemImage: "sparkles")
                    .font(.title2.bold())
                Text(original.prompt.isEmpty ? "Untitled question" : original.prompt)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(24)

            Divider()

            ScrollView {
                QuestionReviewDetail(review: review, original: original, onApply: onApply)
                    .padding(24)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(24)
        }
        .frame(minWidth: 620, minHeight: 540)
    }
}

struct AnswerEditor: View {
    @Binding var question: QuizQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Answers")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    addAnswer()
                } label: {
                    Label("Add Answer", systemImage: "plus")
                }
            }

            ForEach($question.answers) { $answer in
                let number = (question.answers.firstIndex { $0.id == answer.id } ?? 0) + 1
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Toggle("Correct", isOn: correctBinding(for: answer.id))
                            .toggleStyle(.checkbox)
                            .frame(width: 90, alignment: .leading)
                            .accessibilityLabel("Answer \(number) is correct")
                        TextField("Answer text", text: $answer.text)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Answer \(number) text")
                        Button(role: .destructive) {
                            question.answers.removeAll { $0.id == answer.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove answer \(number)")
                    }

                    // A distractor can name the misconception it targets (#25 / Phase 3).
                    if showsMisconception, !answer.isCorrect {
                        HStack(spacing: 10) {
                            Spacer().frame(width: 90)
                            Image(systemName: "lightbulb")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            TextField("Misconception this distractor targets (optional)", text: misconceptionBinding(for: answer.id))
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                                .accessibilityLabel("Answer \(number) misconception")
                        }
                    }
                }
            }
        }
        .onChange(of: question.type) {
            normalizeAnswersForQuestionType()
        }
    }

    private var usesSingleCorrectAnswer: Bool {
        question.type == .multipleChoice || question.type == .trueFalse
    }

    /// Misconception tags apply to selectable distractors only.
    private var showsMisconception: Bool {
        question.type == .multipleChoice || question.type == .multipleAnswer
    }

    private func misconceptionBinding(for answerID: UUID) -> Binding<String> {
        Binding(
            get: { question.answers.first(where: { $0.id == answerID })?.misconceptionTag ?? "" },
            set: { newValue in
                guard let index = question.answers.firstIndex(where: { $0.id == answerID }) else { return }
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                question.answers[index].misconceptionTag = trimmed.isEmpty ? nil : newValue
            }
        )
    }

    private func correctBinding(for answerID: UUID) -> Binding<Bool> {
        Binding(
            get: { question.answers.first(where: { $0.id == answerID })?.isCorrect ?? false },
            set: { newValue in
                guard let index = question.answers.firstIndex(where: { $0.id == answerID }) else { return }
                if usesSingleCorrectAnswer {
                    for answerIndex in question.answers.indices {
                        question.answers[answerIndex].isCorrect = false
                    }
                }
                question.answers[index].isCorrect = newValue
            }
        )
    }

    private func addAnswer() {
        question.answers.append(QuizAnswer(text: "", isCorrect: question.answers.isEmpty))
    }

    private func normalizeAnswersForQuestionType() {
        if question.type == .trueFalse {
            question.answers = [
                QuizAnswer(text: "True", isCorrect: true),
                QuizAnswer(text: "False", isCorrect: false)
            ]
        }
    }
}

/// Edits a numeric question's grading (exact ± margin / range / precision) and an
/// advisory expected unit that is explicitly tool-only — never sent to the LMS.
struct NumericAnswerEditor: View {
    @Binding var numeric: NumericAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Numeric answer")
                .font(.subheadline.weight(.semibold))

            LabeledField("Grading") {
                Picker("Grading", selection: $numeric.mode) {
                    ForEach(NumericGradingMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            switch numeric.mode {
            case .exact:
                HStack(spacing: 16) {
                    LabeledField("Answer") {
                        numberField("Value", value: $numeric.value)
                    }
                    LabeledField("± Margin") {
                        numberField("0", value: $numeric.margin)
                    }
                }
                Text("Absolute margin only. (Percent margin is supported by New Quizzes but not Classic, so it isn't offered here.)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .range:
                HStack(spacing: 16) {
                    LabeledField("Minimum") {
                        numberField("Min", value: $numeric.rangeMin)
                    }
                    LabeledField("Maximum") {
                        numberField("Max", value: $numeric.rangeMax)
                    }
                }
            case .precision:
                HStack(spacing: 16) {
                    LabeledField("Answer") {
                        numberField("Value", value: $numeric.value)
                    }
                    LabeledField("Significant digits") {
                        TextField("digits", value: $numeric.precisionDigits, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }
                Text("Precision exports to New Quizzes; Classic Quizzes approximates it as an exact match.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            LabeledField("Expected unit (optional)") {
                TextField("e.g. g/mol", text: expectedUnitBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
            }
            Label("Not sent to your LMS — used only inside QuizEditor (linter and AI). LMS numeric questions grade the number alone.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func numberField(_ placeholder: String, value: Binding<Double?>) -> some View {
        TextField(placeholder, value: value, format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 110)
    }

    private var expectedUnitBinding: Binding<String> {
        Binding(
            get: { numeric.expectedUnit ?? "" },
            set: { numeric.expectedUnit = $0.isEmpty ? nil : $0 }
        )
    }
}

struct MatchingEditor: View {
    @Binding var matches: [MatchingPair]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Matching Pairs")
                    .font(.headline)
                Spacer()
                Button {
                    matches.append(MatchingPair(prompt: "", match: ""))
                } label: {
                    Label("Add Pair", systemImage: "plus")
                }
            }

            ForEach($matches) { $pair in
                let number = (matches.firstIndex { $0.id == pair.id } ?? 0) + 1
                HStack(spacing: 10) {
                    TextField("Term", text: $pair.prompt)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Pair \(number) term")
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("Match", text: $pair.match)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Pair \(number) match")
                    Button(role: .destructive) {
                        matches.removeAll { $0.id == pair.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove matching pair \(number)")
                }
            }
        }
    }
}

