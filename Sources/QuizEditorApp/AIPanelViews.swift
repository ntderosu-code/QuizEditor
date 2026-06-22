import SwiftUI
import UniformTypeIdentifiers
import AppKit
import WebKit
import QuizEditorCore
#if canImport(FoundationModels)
import FoundationModels
#endif

struct AIPanel: View {
    @Binding var quiz: Quiz
    let quizTitle: String
    /// The question currently selected in the sidebar, if any. When present, the
    /// panel shows item-level tools that read and write this question directly.
    let selectedQuestion: Binding<QuizQuestion>?
    /// 1-based position of the selected question, for the section heading.
    let selectedQuestionNumber: Int?
    /// Opens the full Author with AI sheet, which ContentView owns.
    let onAuthorWithAI: () -> Void
    /// The active persona, so AI prompts carry its preamble, guidelines, safety
    /// clauses, and temperature.
    var persona: Persona = .general
    /// Competency frameworks, so linked competency labels reach the AI prompts.
    var frameworks: [Framework] = []

    @AppStorage("aiProvider") private var provider = AIProvider.openAICompatible
    @AppStorage("aiAPIKey") private var apiKey = ""
    @AppStorage("aiEndpoint") private var endpoint = "https://api.openai.com/v1/chat/completions"
    @AppStorage("aiModel") private var model = "gpt-4o-mini"
    @State private var instruction = "Check for clarity, answer-key issues, accessibility, feedback quality, and LMS import readiness."
    /// The id of the tool that is currently running, or nil when idle. Used to show
    /// a spinner on the active button and disable the others.
    @State private var runningAction: String?
    @State private var isConfigPresented = false
    @State private var aiResult: AIResultContext?
    /// Drives the paginated, applyable whole-quiz sheet. The mode picks which
    /// tool ran (review, revisions, or feedback) and the loader/focus to use.
    @State private var quizReviewMode: QuizReviewMode?
    /// A parsed item review, shown in the formatted diff sheet with per-field Apply.
    @State private var reviewPresentation: ReviewPresentation?
    /// The selected question as it was when its review started — the diff "before".
    @State private var reviewOriginal: QuizQuestion?
    @State private var status: PanelStatus?

    private var isRunning: Bool { runningAction != nil }

    /// Footer hint describing where AI results land. With an auto-run provider the
    /// tools open a sheet where each edit is applied to the quiz; copy-paste opens
    /// a window to read and paste a response back.
    private var resultsHint: String {
        provider == .copyPaste
            ? "Copy a prompt, run it in your assistant, then paste the response back here."
            : "AI suggestions open in a sheet where you apply each edit to the quiz."
    }

    private var runner: ConfiguredAIRunner {
        ConfiguredAIRunner(provider: provider, apiKey: apiKey, endpoint: endpoint, model: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                providerSection
                instructionSection
                quizToolsSection
                if let selectedQuestion {
                    itemToolsSection(selectedQuestion)
                }
                if let status {
                    Label(status.text, systemImage: status.isError ? "exclamationmark.triangle.fill" : "info.circle")
                        .font(.caption)
                        .foregroundStyle(status.isError ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Label(resultsHint, systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 24)
            .padding(.leading, 24)
            .padding(.trailing, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $isConfigPresented) {
            AISettingsSheet()
        }
        .sheet(item: $aiResult) { result in
            AIResultSheet(result: result)
        }
        .sheet(item: $reviewPresentation) { presentation in
            if let original = reviewOriginal, let selectedQuestion {
                QuestionReviewSheet(review: presentation.review, original: original) { mutate in
                    mutate(&selectedQuestion.wrappedValue)
                }
            }
        }
        .sheet(item: $quizReviewMode) { mode in
            QuizReviewSheet(
                quizTitle: quizTitle,
                questions: $quiz.questions,
                loadBatch: mode == .feedback ? makeFeedbackBatchLoader() : makeReviewBatchLoader(),
                title: mode.title,
                focus: mode.focus
            )
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AI Assistant")
                .font(.title2.bold())
            Text("Improve your quiz with an API, Apple's on-device models, or copy and paste to another assistant.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Provider")
                .font(.caption)
                .foregroundStyle(.secondary)
            Menu {
                Picker("Provider", selection: $provider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.inline)

                Divider()

                Button {
                    isConfigPresented = true
                } label: {
                    Label("Configure…", systemImage: "gearshape")
                }
            } label: {
                Text(provider.displayName)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.button)
            .help("Choose the AI provider and configure API credentials")
        }
    }

    private var instructionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledTextEditor(
                title: "Instruction",
                text: $instruction,
                minHeight: 96,
                placeholder: "Tell the AI what to focus on…"
            )
            Text("Edit this to say what the AI should look at, like \u{201C}tighten the wording\u{201D} or \u{201C}check the answer keys.\u{201D} It applies to the tools below.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var quizToolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Whole quiz")
            toolButton("Review Quiz", systemImage: "sparkles", id: quizActionID(.review), prominent: true) {
                runQuizFeature(.review)
            }
            toolButton("Suggest Revisions", systemImage: "pencil.and.outline", id: quizActionID(.revise)) {
                runQuizFeature(.revise)
            }
            toolButton("Draft Feedback", systemImage: "text.bubble", id: quizActionID(.generateFeedback)) {
                runQuizFeature(.generateFeedback)
            }
            toolButton("Author New Questions…", systemImage: "plus.square.on.square", id: "author", action: onAuthorWithAI)

            if provider == .copyPaste {
                Button("Paste Response", action: pasteAIResponse)
                    .buttonStyle(.glass)
                    .disabled(isRunning)
            }
            if provider == .foundationModels {
                Text("Large quizzes run in batches to fit Apple's on-device limit, then combine into one document.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func itemToolsSection(_ binding: Binding<QuizQuestion>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.vertical, 2)
            sectionHeader(selectedQuestionNumber.map { "Question \($0)" } ?? "Selected question")
            toolButton("Review This Question", systemImage: "sparkles", id: "item-review") {
                reviewSelectedQuestion(binding)
            }
            toolButton("Generate Distractors", systemImage: "rectangle.stack.badge.plus", id: "item-distractors", disabled: !canGenerateDistractors(binding.wrappedValue)) {
                generateItemDistractors(binding)
            }
            toolButton("Generate Feedback", systemImage: "text.bubble", id: "item-feedback") {
                generateItemFeedback(binding)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    /// A full-width tool button. Shows a spinner in place of its icon while its own
    /// action is running, and is disabled while any tool is running.
    @ViewBuilder
    private func toolButton(
        _ title: String,
        systemImage: String,
        id: String,
        prominent: Bool = false,
        disabled: Bool = false,
        disabledWhenRunning: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            HStack(spacing: 7) {
                if runningAction == id {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: systemImage).frame(width: 18)
                }
                Text(title)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .disabled(disabled || (disabledWhenRunning && isRunning))

        if prominent {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
        }
    }

    // MARK: - Quiz-level actions

    private func quizActionID(_ feature: AIFeature) -> String { "quiz-\(feature.rawValue)" }

    private func runQuizFeature(_ feature: AIFeature) {
        // Review, Suggest Revisions, and Draft Feedback all open the paginated,
        // applyable sheet for the auto-run providers, so every quiz-level tool
        // writes its result back into the quiz. Copy-paste still copies a prompt.
        if let mode = QuizReviewMode(feature: feature) {
            if provider == .copyPaste {
                copyQuizPrompt(feature)
                return
            }
            if provider == .openAICompatible, URL(string: endpoint) == nil {
                status = PanelStatus(text: "Enter a valid endpoint URL.", isError: true)
                return
            }
            quizReviewMode = mode
        }
    }

    /// Builds the per-page review loader for the current provider. Each call
    /// reviews one page of questions in a single request and parses the JSON
    /// array into one review per question.
    private func makeReviewBatchLoader() -> ([QuizQuestion]) async throws -> [QuestionReview] {
        let service = QuestionReviewService()
        let quizTitle = self.quizTitle
        let provider = self.provider
        let apiKey = self.apiKey
        let endpoint = self.endpoint
        let model = self.model
        let persona = self.persona
        let quiz = self.quiz
        let frameworks = self.frameworks
        let systemInstruction = service.systemInstruction(persona: persona)
        let temperature = persona.aiProfile.temperatureOverride ?? 0.2
        let runner = ConfiguredAIRunner(provider: provider, apiKey: apiKey, endpoint: endpoint, model: model)
        return { questions in
            let contexts = questions.map { quiz.promptLinkContext(for: $0, frameworks: frameworks) }
            let prompt = service.makeBatchPrompt(questions: questions, quizTitle: quizTitle, persona: persona, contexts: contexts)
            let raw = try await runner.runBatchReview(system: systemInstruction, user: prompt, temperature: temperature)
            return service.parseBatch(raw, originals: questions)
        }
    }

    /// Builds the per-page loader for the Draft Feedback tool. Each question on a
    /// page is given freshly drafted feedback (sequentially, so the on-device model
    /// handles one request at a time); the result is shown as a per-question diff
    /// with Apply, reusing the same sheet as Review Quiz.
    private func makeFeedbackBatchLoader() -> ([QuizQuestion]) async throws -> [QuestionReview] {
        let service = QuestionAuthoringService()
        let runner = self.runner
        let quizTitle = self.quizTitle
        let persona = self.persona
        let quiz = self.quiz
        let frameworks = self.frameworks
        let system = service.systemInstruction(persona: persona)
        let temperature = persona.aiProfile.temperatureOverride ?? 0.4
        return { questions in
            var results: [QuestionReview] = []
            for question in questions {
                let context = quiz.promptLinkContext(for: question, frameworks: frameworks)
                let prompt = service.makeFeedbackPrompt(question: question, quizTitle: quizTitle, persona: persona, linkedContext: context)
                let raw = try await runner.runFeedback(system: system, user: prompt, temperature: temperature)
                let drafted = service.parseFeedback(raw)
                let changed = (drafted?.isEmpty == false && drafted != question.feedback) ? drafted : nil
                results.append(QuestionReview(summary: "Drafted feedback.", revisedFeedback: changed))
            }
            return results
        }
    }

    private func copyQuizPrompt(_ feature: AIFeature) {
        let prompt = AIPromptBuilder().makePrompt(feature: feature, quiz: quiz, userInstruction: instruction)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        status = PanelStatus(text: "\(feature.displayName) prompt copied. Run it in your assistant, then Paste Response.", isError: false)
    }

    private func pasteAIResponse() {
        guard let pasted = NSPasteboard.general.string(forType: .string),
              !pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = PanelStatus(text: "Clipboard does not contain text.", isError: true)
            return
        }
        presentResult(pasted, title: "AI Response")
    }

    // MARK: - Item-level actions

    private func canGenerateDistractors(_ question: QuizQuestion) -> Bool {
        (question.type == .multipleChoice || question.type == .multipleAnswer)
            && question.answers.contains { $0.isCorrect }
    }

    private func reviewSelectedQuestion(_ binding: Binding<QuizQuestion>) {
        let service = QuestionReviewService()
        let context = quiz.promptLinkContext(for: binding.wrappedValue, frameworks: frameworks)
        let system = service.systemInstruction(persona: persona)
        let prompt = service.makePrompt(question: binding.wrappedValue, quizTitle: quizTitle, persona: persona, linkedContext: context)
        if provider == .copyPaste {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(system + "\n\n" + prompt, forType: .string)
            status = PanelStatus(text: "Question review prompt copied. Run it, then Paste Response.", isError: false)
            return
        }
        runningAction = "item-review"
        status = nil
        let runner = self.runner
        let snapshot = binding.wrappedValue
        let temperature = persona.aiProfile.temperatureOverride ?? 0.2
        Task {
            do {
                let raw = try await runner.runReview(system: system, user: prompt, temperature: temperature)
                await MainActor.run {
                    runningAction = nil
                    // Parse into the formatted review sheet (summary, suggestions,
                    // and per-field diffs with Apply) instead of showing raw JSON.
                    reviewOriginal = snapshot
                    reviewPresentation = ReviewPresentation(review: service.parse(raw, original: snapshot))
                }
            } catch {
                await MainActor.run {
                    runningAction = nil
                    status = PanelStatus(text: "AI request failed: \(error)", isError: true)
                }
            }
        }
    }

    private func generateItemDistractors(_ binding: Binding<QuizQuestion>) {
        guard let correct = binding.wrappedValue.answers.first(where: { $0.isCorrect })?.text,
              !correct.trimmingCharacters(in: .whitespaces).isEmpty else {
            status = PanelStatus(text: "Mark a correct answer first so distractors can be contrasted against it.", isError: true)
            return
        }
        let service = QuestionAuthoringService()
        let stem = HTMLUtilities().plainText(fromHTML: binding.wrappedValue.prompt)
        let prompt = service.makeDistractorsPrompt(prompt: stem, correctAnswer: correct, count: 3, persona: persona)
        let system = service.systemInstruction(persona: persona)
        let temperature = persona.aiProfile.temperatureOverride ?? 0.7
        let labels = persona.aiProfile.labelsMisconceptions
        let runner = self.runner
        runItemGeneration(id: "item-distractors", perform: { try await runner.runDistractors(system: system, user: prompt, labelsMisconceptions: labels, temperature: temperature) }) { raw in
            let distractors = service.parseLabeledDistractors(raw)
            guard !distractors.isEmpty else {
                status = PanelStatus(text: "No distractors were returned. Try again or rephrase the stem.", isError: true)
                return
            }
            binding.wrappedValue.answers.append(contentsOf: distractors.map { QuizAnswer(text: $0.text, isCorrect: false, misconceptionTag: $0.misconception) })
            status = PanelStatus(text: "Added \(distractors.count) distractor\(distractors.count == 1 ? "" : "s") to this question.", isError: false)
        }
    }

    private func generateItemFeedback(_ binding: Binding<QuizQuestion>) {
        let service = QuestionAuthoringService()
        let prompt = service.makeFeedbackPrompt(question: binding.wrappedValue, quizTitle: quizTitle, persona: persona, linkedContext: quiz.promptLinkContext(for: binding.wrappedValue, frameworks: frameworks))
        let system = service.systemInstruction(persona: persona)
        let temperature = persona.aiProfile.temperatureOverride ?? 0.4
        let runner = self.runner
        runItemGeneration(id: "item-feedback", perform: { try await runner.runFeedback(system: system, user: prompt, temperature: temperature) }) { raw in
            guard let feedback = service.parseFeedback(raw) else {
                status = PanelStatus(text: "No feedback was returned.", isError: true)
                return
            }
            binding.wrappedValue.feedback = feedback
            status = PanelStatus(text: "Feedback added to this question.", isError: false)
        }
    }

    private func runItemGeneration(id: String, perform: @escaping () async throws -> String, apply: @escaping (String) -> Void) {
        guard runner.supportsAutoRun else {
            status = PanelStatus(text: "Switch to the API or Apple Foundation Models provider to generate here, or use Author with AI for copy and paste.", isError: true)
            return
        }
        runningAction = id
        status = nil
        Task {
            do {
                let raw = try await perform()
                await MainActor.run {
                    runningAction = nil
                    apply(raw)
                }
            } catch {
                await MainActor.run {
                    runningAction = nil
                    status = PanelStatus(text: "AI request failed: \(error)", isError: true)
                }
            }
        }
    }

    private func presentResult(_ markdown: String, title: String) {
        aiResult = AIResultContext(title: title, markdown: markdown)
    }
}

/// Modal that configures the AI provider and API credentials. Edits the same
/// @AppStorage-backed values the AI panel reads, so changes persist immediately.
struct AISettingsSheet: View {
    @AppStorage("aiProvider") private var provider = AIProvider.openAICompatible
    @AppStorage("aiAPIKey") private var apiKey = ""
    @AppStorage("aiEndpoint") private var endpoint = "https://api.openai.com/v1/chat/completions"
    @AppStorage("aiModel") private var model = "gpt-4o-mini"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AI Configuration")
                .font(.title2.bold())
                .padding(20)

            Divider()

            Form {
                Picker("Provider", selection: $provider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                switch provider {
                case .openAICompatible:
                    Section("API Credentials") {
                        SecureField("API key", text: $apiKey, prompt: Text("sk-…"))
                        TextField("Endpoint", text: $endpoint, prompt: Text("https://api.openai.com/v1/chat/completions"))
                        TextField("Model", text: $model, prompt: Text("gpt-4o-mini"))
                    }
                case .copyPaste:
                    Section {
                        Text("Copies a model-ready prompt to your clipboard. Paste the response back into the panel — no API key needed.")
                            .foregroundStyle(.secondary)
                    }
                case .foundationModels:
                    Section {
                        Text("Uses Apple Foundation Models on-device when Apple Intelligence is available on this Mac. No API key needed.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 460, height: 420)
    }
}


/// Which quiz-level AI tool opened the paginated, applyable sheet, and how that
/// sheet should present and load each question.
enum QuizReviewMode: String, Identifiable {
    case review, revisions, feedback

    var id: String { rawValue }

    init?(feature: AIFeature) {
        switch feature {
        case .review: self = .review
        case .revise: self = .revisions
        case .generateFeedback: self = .feedback
        case .author: return nil
        }
    }

    var title: String {
        switch self {
        case .review: "Quiz Review"
        case .revisions: "Suggested Revisions"
        case .feedback: "Drafted Feedback"
        }
    }

    var focus: ReviewFocus {
        switch self {
        case .review: .full
        case .revisions: .revisions
        case .feedback: .feedback
        }
    }
}

