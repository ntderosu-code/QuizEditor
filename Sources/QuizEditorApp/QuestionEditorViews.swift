import SwiftUI
import UniformTypeIdentifiers
import AppKit
import WebKit
import QuizEditorCore
#if canImport(FoundationModels)
import FoundationModels
#endif

enum QuestionEditorSection: CaseIterable, Hashable {
    case type, stem, answer, feedback, checks, details

    static let defaultOrder: [QuestionEditorSection] = [.type, .stem, .answer, .feedback, .checks, .details]
}

struct QuestionEditor: View {
    @Binding var question: QuizQuestion
    let quizTitle: String
    let questionNumber: Int
    let questionTotal: Int
    /// Resolved author metadata from saved links. The editor no longer exposes
    /// linking controls, but older files may still carry this context for AI.
    var linkedContext: PromptLinkContext = .empty
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

    var body: some View {
        VStack(spacing: 0) {
            stickyHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    QuestionTypeEditor(question: $question)

                    RichTextField(title: "Question stem", text: $question.prompt, minHeight: 96)

                    if let reviewError {
                        aiMessageBox(reviewError, title: AppCopy.aiSuggestions) { self.reviewError = nil }
                    }

                    if let generationError {
                        aiMessageBox(generationError, title: "AI Tools") { self.generationError = nil }
                    }

                    if question.type == .matching {
                        MatchingEditor(matches: $question.matches)
                    } else if question.type == .numeric {
                        NumericAnswerEditor(numeric: numericBinding)
                    } else if question.type != .essay {
                        AnswerEditor(question: $question)
                    }

                    feedbackSection

                    let readiness = QuestionReadiness(question: question)
                    if readiness.status != .ready {
                        QuestionReadinessView(readiness: readiness)
                    }

                    LintFindingsSection(findings: findings)

                    QuestionDetailsEditor(question: $question)
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
    /// and exactly one prominent question-level AI action (Review with AI).
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
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .imageScale(.large)
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
                    Label("Review with AI", systemImage: "sparkles")
                }
            }
            .disabled(isReviewing)
            .buttonStyle(.glassProminent)
            .foregroundStyle(.white)
            .fixedSize()
            .help("Ask AI to review this question and offer suggested edits")

            Menu {
                Button("Suggest Distractors") { generateDistractors() }
                    .disabled(!canGenerateDistractors)
                Button("Draft Feedback") { generateFeedback() }
                if undoSnapshot != nil {
                    Divider()
                    Button("Undo AI Changes") { undoAIChanges() }
                }
                Divider()
                Button("Delete Question", role: .destructive, action: onDelete)
            } label: {
                Label("More actions", systemImage: "ellipsis")
            }
            .menuIndicator(.hidden)
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .imageScale(.large)
            .fixedSize()
            .help("Suggest distractors, draft feedback, undo AI edits, or delete this question")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
    }

    /// Student feedback, surfaced as readiness-critical rather than buried in a
    /// collapsed disclosure: a status line shows at a glance whether it is present,
    /// and drafting feedback is a contextual action right here next to the field.
    @ViewBuilder
    private var feedbackSection: some View {
        let hasFeedback = !HTMLUtilities()
            .plainText(fromHTML: question.feedback)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Feedback for students")
                    .font(.subheadline.weight(.semibold))
                Label(hasFeedback ? "Complete" : "Missing",
                      systemImage: hasFeedback ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(hasFeedback ? .green : .orange)
                    .accessibilityLabel(hasFeedback ? "Feedback complete" : "Feedback missing")
                Spacer()
                Button {
                    generateFeedback()
                } label: {
                    if isGenerating {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Generate draft feedback", systemImage: "text.bubble")
                    }
                }
                .font(.caption)
                .disabled(isGenerating)
                .help("Draft feedback for this question with AI")
            }
            RichTextField(title: "Feedback", text: $question.feedback, minHeight: 90, showsTitle: false)
        }
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
        }
    }

    private func runGeneration(perform: @escaping () async throws -> String, apply: @escaping (String) -> Void) {
        generationError = nil
        guard runner.supportsAutoRun else {
            generationError = "Switch to the API or Apple Foundation Models provider to generate here, or use Draft with AI for copy/paste."
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
                Label(AppCopy.aiSuggestions, systemImage: "sparkles")
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
            HStack(spacing: 8) {
                Text("Answers")
                    .font(.subheadline.weight(.semibold))
                Text(usesSingleCorrectAnswer ? "Select the one correct answer." : "Check every correct answer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ForEach($question.answers) { $answer in
                answerRow($answer)
            }

            // "Add answer" sits directly under the list it extends.
            Button(action: addAnswer) {
                Label("Add answer", systemImage: "plus")
            }
            .buttonStyle(.bordered)

            answerValidation
        }
        .onChange(of: question.type) {
            normalizeAnswersForQuestionType()
        }
    }

    @ViewBuilder
    private func answerRow(_ answer: Binding<QuizAnswer>) -> some View {
        let index = question.answers.firstIndex { $0.id == answer.wrappedValue.id } ?? 0
        let letter = Self.answerLetter(index)
        // One line per answer, with a fixed layout, so marking an answer correct
        // never adds or removes a row and the choices never reflow.
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(letter)
                .font(.callout.weight(.semibold).monospaced())
                .frame(width: 18, alignment: .leading)
                .accessibilityHidden(true)

            correctSelector(for: answer.wrappedValue.id, letter: letter, isCorrect: answer.wrappedValue.isCorrect)

            TextField("Answer text", text: answer.text)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Answer \(letter) text")

            Button(role: .destructive) {
                question.answers.removeAll { $0.id == answer.wrappedValue.id }
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove answer \(letter)")
        }
    }

    /// Single-select questions use a radio so only one answer can ever be correct;
    /// multi-select uses a checkbox. Both carry an answer-specific accessible name.
    @ViewBuilder
    private func correctSelector(for answerID: UUID, letter: String, isCorrect: Bool) -> some View {
        if usesSingleCorrectAnswer {
            Button {
                markOnlyCorrect(answerID)
            } label: {
                Image(systemName: isCorrect ? "largecircle.fill.circle" : "circle")
                    .imageScale(.large)
                    .foregroundStyle(isCorrect ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Mark answer \(letter) as correct")
            .accessibilityAddTraits(isCorrect ? .isSelected : [])
            .help("Mark answer \(letter) as the correct answer")
        } else {
            Toggle("", isOn: correctBinding(for: answerID))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel("Mark answer \(letter) as correct")
        }
    }

    /// Answer-related readiness problems (no/extra key, too few choices, blanks,
    /// duplicates), shown right under the list so validation is where the user is
    /// working. Reuses the deterministic Core checks so the rules can't drift.
    @ViewBuilder
    private var answerValidation: some View {
        let relevant: Set<String> = ["key", "choices", "blanks", "duplicates"]
        let issues = QuestionReadiness(question: question).checks
            .filter { relevant.contains($0.id) && !$0.isSatisfied }
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(issues) { issue in
                    Label {
                        Text(issue.message).font(.caption)
                    } icon: {
                        Image(systemName: issue.severity == .required ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(issue.severity == .required ? .red : .orange)
                    .accessibilityLabel("\(issue.title) problem: \(issue.message)")
                }
            }
            .padding(.top, 2)
        }
    }

    private static func answerLetter(_ index: Int) -> String {
        index < 26 ? String(UnicodeScalar(UInt8(65 + index))) : "\(index + 1)"
    }

    /// Sets exactly one answer correct (single-select). A radio can only select, so
    /// single-answer questions can never end up with two correct options.
    private func markOnlyCorrect(_ answerID: UUID) {
        for i in question.answers.indices {
            question.answers[i].isCorrect = (question.answers[i].id == answerID)
        }
    }

    private var usesSingleCorrectAnswer: Bool {
        question.type == .multipleChoice || question.type == .trueFalse
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
