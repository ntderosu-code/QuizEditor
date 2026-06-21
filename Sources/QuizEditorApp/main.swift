import SwiftUI
import UniformTypeIdentifiers
import AppKit
import WebKit
import QuizEditorCore
#if canImport(FoundationModels)
import FoundationModels
#endif

extension UTType {
    /// The app's native document type. Must match UTExportedTypeDeclarations in Info.plist.
    static let quizEditorDocument = UTType(exportedAs: "com.byronroush.quizeditor.quiz")
}

/// The document-based wrapper around a `Quiz`, persisted as pretty-printed JSON.
struct QuizDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.quizEditorDocument] }
    static var writableContentTypes: [UTType] { [.quizEditorDocument] }

    var quiz: Quiz

    init() {
        quiz = Quiz(title: "Untitled Quiz", questions: [])
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        quiz = try JSONDecoder().decode(Quiz.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(quiz))
    }
}

@main
struct QuizEditorApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: QuizDocument()) { file in
            ContentView(quiz: file.$document.quiz)
                .frame(minWidth: 1200, idealWidth: 1320, minHeight: 720)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .help) {
                AcknowledgementsMenuButton()
            }
        }

        Window("Acknowledgements", id: "acknowledgements") {
            AcknowledgementsView()
        }
        .windowResizability(.contentSize)
    }
}

/// Help-menu entry that opens the Acknowledgements window.
struct AcknowledgementsMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Acknowledgements") {
            openWindow(id: "acknowledgements")
        }
    }
}

struct AcknowledgementsView: View {
    private struct Credit: Identifiable {
        let id = UUID()
        let name: String
        let detail: String
    }

    private let credits: [Credit] = [
        Credit(name: "SwiftUI, AppKit & WebKit", detail: "Apple's UI frameworks, used under the Apple SDK License."),
        Credit(name: "SF Symbols", detail: "Icon set © Apple Inc., used under the SF Symbols license."),
        Credit(name: "IMS QTI 1.2 & 2.1", detail: "Question & Test Interoperability specifications by IMS Global / 1EdTech."),
        Credit(name: "Canvas LMS", detail: "QTI import/export targets the Canvas Classic and New Quizzes engines.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Quiz Editor")
                    .font(.title2.bold())
                Text("Released under the MIT License © 2026 Byron R Roush. No third-party open-source libraries are bundled; the app is built entirely on Apple frameworks.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Text("Acknowledgements")
                .font(.headline)

            ForEach(credits) { credit in
                VStack(alignment: .leading, spacing: 2) {
                    Text(credit.name)
                        .font(.subheadline.weight(.semibold))
                    Text(credit.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 460, height: 380)
    }
}

struct ContentView: View {
    @Binding var quiz: Quiz
    @State private var selectedQuestionID: UUID?
    @State private var isImporterPresented = false
    @State private var isQTIImporterPresented = false
    @State private var importText = sampleImportText
    @State private var errorMessage: String?
    @State private var exportDocument = QTIArchiveDocument(data: Data())
    @State private var isExporterPresented = false
    @State private var correctMarkerSymbol = "*"
    @State private var correctMarkerLocation = CorrectAnswerMarker.Location.beginningOfLine
    @State private var isAIPanelVisible = true
    @State private var importPreservesFormatting = true
    @State private var isPreviewPresented = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                quiz: $quiz,
                selectedQuestionID: $selectedQuestionID,
                onAddQuestion: addQuestion,
                onImportMarkedText: { isImporterPresented = true },
                onImportQTI: { keepFormatting in
                    importPreservesFormatting = keepFormatting
                    isQTIImporterPresented = true
                }
            )
            .navigationSplitViewColumnWidth(min: 300, ideal: 320, max: 360)
        } detail: {
            editorDetail
                .frame(minWidth: 520)
        }
        .inspector(isPresented: $isAIPanelVisible) {
            AIPanel(quiz: quiz)
                .inspectorColumnWidth(min: 380, ideal: 420, max: 540)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    addQuestion()
                } label: {
                    Label("Add Question", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help("Add a new question (⇧⌘N)")

                Divider()

                Button {
                    isImporterPresented = true
                } label: {
                    Label("Import Marked Text", systemImage: "text.badge.plus")
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .help("Import questions from marked plain text (⇧⌘I)")

                Menu {
                    Button("Keep Formatting…") {
                        importPreservesFormatting = true
                        isQTIImporterPresented = true
                    }
                    Button("Plain Text…") {
                        importPreservesFormatting = false
                        isQTIImporterPresented = true
                    }
                } label: {
                    Label("Import QTI Zip", systemImage: "archivebox")
                } primaryAction: {
                    importPreservesFormatting = true
                    isQTIImporterPresented = true
                }
                .help("Import a Canvas QTI .zip package — keep formatting or import as plain text")

                Menu {
                    Section("Canvas QTI Package") {
                        ForEach(CanvasQuizEngine.allCases) { engine in
                            Button(engine.displayName) {
                                prepareExport(engine: engine)
                            }
                        }
                    }
                    Divider()
                    Button("Formatted Document (HTML)…") {
                        exportFormattedDocument()
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .menuIndicator(.hidden)
                .help("Export as a Canvas QTI package or a formatted document")

                Button {
                    isPreviewPresented = true
                } label: {
                    Label("Preview", systemImage: "eye")
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .help("Preview a formatted version of the quiz (⇧⌘P)")

                Divider()

                Menu {
                    Button("Check Spelling", action: checkSpelling)
                    Button("Show Spelling and Grammar", action: showSpellingPanel)
                    Button("Toggle Check Spelling While Typing", action: toggleContinuousSpellChecking)
                } label: {
                    Label("Spelling", systemImage: "text.magnifyingglass")
                }
                .menuIndicator(.hidden)
                .help("Spelling and grammar tools")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAIPanelVisible.toggle()
                } label: {
                    Label("AI Assistant", systemImage: isAIPanelVisible ? "sidebar.trailing" : "sidebar.right")
                }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .help(isAIPanelVisible ? "Hide the AI Assistant panel (⌥⌘A)" : "Show the AI Assistant panel (⌥⌘A)")
            }
        }
        .onAppear {
            if selectedQuestionID == nil {
                selectedQuestionID = quiz.questions.first?.id
            }
        }
        .sheet(isPresented: $isImporterPresented) {
            ImportSheet(
                importText: $importText,
                correctMarkerSymbol: $correctMarkerSymbol,
                correctMarkerLocation: $correctMarkerLocation
            ) { text in
                importMarkedText(text)
            }
        }
        .fileImporter(
            isPresented: $isQTIImporterPresented,
            allowedContentTypes: [.zip],
            allowsMultipleSelection: false
        ) { result in
            importQTIArchive(result)
        }
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            contentType: .zip,
            defaultFilename: defaultExportFilename
        ) { result in
            switch result {
            case .success: break
            case .failure(let error): errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $isPreviewPresented) {
            QuizPreviewSheet(quiz: quiz, selectedQuestion: selectedQuestionForPreview)
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
            presenting: errorMessage
        ) { _ in
            Button("OK", role: .cancel) { }
        } message: { message in
            Text(message)
        }
    }

    private var selectedQuestionForPreview: (number: Int, question: QuizQuestion)? {
        guard let index = quiz.questions.firstIndex(where: { $0.id == selectedQuestionID }) else { return nil }
        return (index + 1, quiz.questions[index])
    }

    @ViewBuilder
    private var editorDetail: some View {
        if let selectedIndex = quiz.questions.firstIndex(where: { $0.id == selectedQuestionID }) {
            QuestionEditor(
                question: $quiz.questions[selectedIndex],
                quizTitle: quiz.title,
                questionNumber: selectedIndex + 1,
                questionTotal: quiz.questions.count
            ) {
                deleteQuestion(at: selectedIndex)
            }
            .id(quiz.questions[selectedIndex].id)
        } else {
            ContentUnavailableView(
                "No Question Selected",
                systemImage: "questionmark.square.dashed",
                description: Text("Choose a question or add a new one to start writing.")
            )
        }
    }

    private var defaultExportFilename: String {
        let safeTitle = quiz.title
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return (safeTitle.isEmpty ? "canvas-quiz" : safeTitle) + ".zip"
    }

    private func addQuestion() {
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "New question",
            answers: [
                QuizAnswer(text: "Correct answer", isCorrect: true),
                QuizAnswer(text: "Distractor", isCorrect: false)
            ]
        )
        quiz.questions.append(question)
        selectedQuestionID = question.id
    }

    private func deleteQuestion(at index: Int) {
        quiz.questions.remove(at: index)
        selectedQuestionID = quiz.questions.first?.id
    }

    private func importQTIArchive(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            quiz = try QTIImporter(preserveFormatting: importPreservesFormatting).importQuiz(fromZipAt: url)
            selectedQuestionID = quiz.questions.first?.id
        } catch {
            errorMessage = "QTI import failed: \(error.localizedDescription)"
        }
    }

    private func importMarkedText(_ text: String) {
        do {
            let marker = CorrectAnswerMarker(symbol: correctMarkerSymbol, location: correctMarkerLocation)
            quiz = try MarkedTextParser(correctAnswerMarker: marker).parse(text)
            selectedQuestionID = quiz.questions.first?.id
            isImporterPresented = false
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func exportFormattedDocument() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = (defaultExportFilename as NSString).deletingPathExtension + ".html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let document = FormattedDocumentBuilder().document(for: quiz)
            try document.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Document export failed: \(error.localizedDescription)"
        }
    }

    private func prepareExport(engine: CanvasQuizEngine) {
        let altIssues = QuizAccessibilityValidator().imagesMissingAltText(in: quiz)
        guard altIssues.isEmpty else {
            errorMessage = "Export blocked — add alt text first. \(altIssues.joined(separator: "; "))."
            return
        }

        do {
            exportDocument = try QTIArchiveDocument(quiz: quiz, engine: engine)
            isExporterPresented = true
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func checkSpelling() {
        NSApp.sendAction(#selector(NSText.checkSpelling(_:)), to: nil, from: nil)
    }

    private func showSpellingPanel() {
        NSApp.sendAction(#selector(NSText.showGuessPanel(_:)), to: nil, from: nil)
    }

    private func toggleContinuousSpellChecking() {
        NSApp.sendAction(#selector(NSTextView.toggleContinuousSpellChecking(_:)), to: nil, from: nil)
    }
}

struct SidebarView: View {
    @Binding var quiz: Quiz
    @Binding var selectedQuestionID: UUID?
    let onAddQuestion: () -> Void
    let onImportMarkedText: () -> Void
    let onImportQTI: (Bool) -> Void
    var body: some View {
        // Standard source-list sidebar: List(selection:) supplies the Liquid Glass
        // material, focus-aware selection highlight, and keyboard navigation for free.
        List(selection: $selectedQuestionID) {
            Section("Quiz Title") {
                TextField("Quiz title", text: $quiz.title)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Quiz title")
            }

            Section("Questions") {
                ForEach(Array(quiz.questions.enumerated()), id: \.element.id) { index, question in
                    SidebarQuestionRow(number: index + 1, question: question)
                        .tag(question.id)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Quiz")
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button(action: onAddQuestion) {
                    Label("Add Question", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .help("Add a new question (⇧⌘N)")

                Menu {
                    Button("Marked Text…", action: onImportMarkedText)
                    Divider()
                    Button("QTI Zip — Keep Formatting…") { onImportQTI(true) }
                    Button("QTI Zip — Plain Text…") { onImportQTI(false) }
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Import questions from marked text or a Canvas QTI zip")

                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}

struct SidebarQuestionRow: View {
    let number: Int
    let question: QuizQuestion

    private var plainPrompt: String {
        let text = HTMLUtilities().plainText(fromHTML: question.prompt)
        return text.isEmpty ? "Untitled question" : text
    }

    var body: some View {
        // No manual selection coloring: the enclosing List inverts foreground colors
        // for the selected row automatically, which also adapts to Increase Contrast.
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(plainPrompt)
                    .font(.body)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(question.type.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Question \(number), \(question.type.displayName): \(plainPrompt)")
    }
}

struct QuestionEditor: View {
    @Binding var question: QuizQuestion
    let quizTitle: String
    let questionNumber: Int
    let questionTotal: Int
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Question \(questionNumber) of \(questionTotal)")
                            .font(.title2.bold())
                        Text("Edit the prompt, answer choices, and feedback.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    if undoSnapshot != nil {
                        Button {
                            undoAIChanges()
                        } label: {
                            Label("Undo AI Changes", systemImage: "arrow.uturn.backward")
                        }
                        .labelStyle(.iconOnly)
                        .help("Undo AI changes — revert edits applied from the last AI review")
                    }

                    Button {
                        reviewQuestion()
                    } label: {
                        if isReviewing {
                            ProgressView().controlSize(.small)
                            Text("Reviewing…")
                        } else {
                            Label("AI Review", systemImage: "sparkles")
                        }
                    }
                    .disabled(isReviewing)
                    .fixedSize()
                    .help("Review this question for item-writing quality and apply suggested edits")

                    Button(role: .destructive, action: onDelete) {
                        Label("Delete Question", systemImage: "trash")
                    }
                    .labelStyle(.iconOnly)
                    .help("Delete this question")
                }

                LabeledField("Question Type") {
                    Picker("Question Type", selection: $question.type) {
                        ForEach(QuizQuestionType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                if let reviewError {
                    GroupBox {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                            Text(reviewError)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button("Dismiss") { self.reviewError = nil }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("AI Review", systemImage: "sparkles")
                    }
                }

                RichTextField(title: "Prompt", text: $question.prompt, minHeight: 160)

                if question.type == .matching {
                    MatchingEditor(matches: $question.matches)
                } else if question.type != .essay {
                    AnswerEditor(question: $question)
                }

                DisclosureGroup(isExpanded: $isFeedbackExpanded) {
                    RichTextField(title: "Feedback", text: $question.feedback, minHeight: 140, showsTitle: false)
                        .padding(.top, 8)
                } label: {
                    Text("Feedback")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .sheet(item: $reviewPresentation) { presentation in
            QuestionReviewSheet(review: presentation.review, original: question, onApply: applyEdit)
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

    private func reviewQuestion() {
        let service = QuestionReviewService()
        let prompt = service.makePrompt(question: question, quizTitle: quizTitle)
        let systemInstruction = service.systemInstruction
        let snapshot = question
        reviewError = nil
        isReviewing = true

        Task {
            do {
                let raw = try await runReviewPrompt(systemInstruction: systemInstruction, userPrompt: prompt)
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

    private func runReviewPrompt(systemInstruction: String, userPrompt: String) async throws -> String {
        switch provider {
        case .openAICompatible:
            let endpointURL = URL(string: endpoint) ?? URL(string: "https://api.openai.com/v1/chat/completions")!
            let configuration = AIConfiguration(apiKey: apiKey, endpoint: endpointURL, model: model)
            return try await AIClient().complete(systemInstruction: systemInstruction, userPrompt: userPrompt, configuration: configuration)
        case .foundationModels:
            return await FoundationModelsRunner.run(prompt: systemInstruction + "\n\n" + userPrompt)
        case .copyPaste:
            throw InlineReviewError.unsupportedProvider
        }
    }
}

private enum InlineReviewError: Error, CustomStringConvertible {
    case unsupportedProvider

    var description: String {
        switch self {
        case .unsupportedProvider:
            "Inline review needs the OpenAI-compatible API or Apple Foundation Models provider. Change it in the AI Assistant panel on the right."
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

    private enum Field { case prompt, answers, matches, feedback }
    @State private var appliedFields: Set<Field> = []

    // Bullet glyph size scales with Dynamic Type instead of a fixed point size.
    @ScaledMetric(relativeTo: .callout) private var suggestionBulletSize: CGFloat = 5

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
                VStack(alignment: .leading, spacing: 16) {
                    Text(review.summary)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)

                    if !review.suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("What to improve")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            ForEach(Array(review.suggestions.enumerated()), id: \.offset) { _, suggestion in
                                Label {
                                    Text(suggestion)
                                        .font(.callout)
                                        .fixedSize(horizontal: false, vertical: true)
                                } icon: {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: suggestionBulletSize))
                                        .foregroundStyle(.secondary)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                    }

                    if review.hasRevisions {
                        Divider()
                        Text("Suggested edits")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        if let revisedPrompt = review.revisedPrompt {
                            diffRow(title: "Prompt", before: original.prompt, after: revisedPrompt, field: .prompt) {
                                $0.prompt = revisedPrompt
                            }
                        }
                        if appliesToAnswers, let revisedAnswers = review.revisedAnswers {
                            diffRow(title: "Answers", before: answersText(original.answers), after: answersText(revisedAnswers), field: .answers) {
                                $0.answers = revisedAnswers
                            }
                        }
                        if original.type == .matching, let revisedMatches = review.revisedMatches {
                            diffRow(title: "Matching pairs", before: matchesText(original.matches), after: matchesText(revisedMatches), field: .matches) {
                                $0.matches = revisedMatches
                            }
                        }
                        if let revisedFeedback = review.revisedFeedback {
                            diffRow(title: "Feedback", before: original.feedback.isEmpty ? "(none)" : original.feedback, after: revisedFeedback, field: .feedback) {
                                $0.feedback = revisedFeedback
                            }
                        }
                    } else {
                        Label("No rewrites suggested — this question already reads well.", systemImage: "checkmark.seal")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                if review.hasRevisions {
                    Button("Apply All", action: applyAll)
                        .buttonStyle(.borderedProminent)
                        .disabled(applicableFields.isSubset(of: appliedFields))
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(24)
        }
        .frame(minWidth: 620, minHeight: 540)
    }

    @ViewBuilder
    private func diffRow(title: String, before: String, after: String, field: Field, apply: @escaping (inout QuizQuestion) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if appliedFields.contains(field) {
                    Label("Applied", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Button("Apply") {
                        onApply(apply)
                        appliedFields.insert(field)
                    }
                    .help("Replace the current \(title.lowercased()) with this rewrite")
                }
            }

            diffBlock(tag: "Before", text: before, tint: .red)
            diffBlock(tag: "After", text: after, tint: .green)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 10))
    }

    @ViewBuilder
    private func diffBlock(tag: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tag.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(tint.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(tint.opacity(0.35))
                )
                .clipShape(.rect(cornerRadius: 6))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tag): \(text)")
    }

    private var appliesToAnswers: Bool {
        original.type != .essay && original.type != .matching
    }

    private var applicableFields: Set<Field> {
        var fields: Set<Field> = []
        if review.revisedPrompt != nil { fields.insert(.prompt) }
        if appliesToAnswers, review.revisedAnswers != nil { fields.insert(.answers) }
        if original.type == .matching, review.revisedMatches != nil { fields.insert(.matches) }
        if review.revisedFeedback != nil { fields.insert(.feedback) }
        return fields
    }

    private func applyAll() {
        if let revisedPrompt = review.revisedPrompt, !appliedFields.contains(.prompt) {
            onApply { $0.prompt = revisedPrompt }
            appliedFields.insert(.prompt)
        }
        if appliesToAnswers, let revisedAnswers = review.revisedAnswers, !appliedFields.contains(.answers) {
            onApply { $0.answers = revisedAnswers }
            appliedFields.insert(.answers)
        }
        if original.type == .matching, let revisedMatches = review.revisedMatches, !appliedFields.contains(.matches) {
            onApply { $0.matches = revisedMatches }
            appliedFields.insert(.matches)
        }
        if let revisedFeedback = review.revisedFeedback, !appliedFields.contains(.feedback) {
            onApply { $0.feedback = revisedFeedback }
            appliedFields.insert(.feedback)
        }
    }

    private func answersText(_ answers: [QuizAnswer]) -> String {
        answers.map { "\($0.text)\($0.isCorrect ? "  (correct)" : "")" }.joined(separator: "\n")
    }

    private func matchesText(_ matches: [MatchingPair]) -> String {
        matches.map { "\($0.prompt) → \($0.match)" }.joined(separator: "\n")
    }
}

struct AnswerEditor: View {
    @Binding var question: QuizQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Answers")
                    .font(.headline)
                Spacer()
                Button {
                    addAnswer()
                } label: {
                    Label("Add Answer", systemImage: "plus")
                }
            }

            ForEach($question.answers) { $answer in
                let number = (question.answers.firstIndex { $0.id == answer.id } ?? 0) + 1
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
            }
        }
        .onChange(of: question.type) {
            normalizeAnswersForQuestionType()
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

struct AIPanel: View {
    let quiz: Quiz

    @AppStorage("aiProvider") private var provider = AIProvider.openAICompatible
    @AppStorage("aiAPIKey") private var apiKey = ""
    @AppStorage("aiEndpoint") private var endpoint = "https://api.openai.com/v1/chat/completions"
    @AppStorage("aiModel") private var model = "gpt-4o-mini"
    @State private var feature = AIFeature.review
    @State private var instruction = "Check the quiz for clarity, answer-key issues, accessibility, feedback quality, and Canvas import readiness."
    @State private var output = "Run a feature to see results here."
    @State private var isRunning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("AI Assistant")
                    .font(.title2.bold())
                Text("Review and improve your quiz with an API, Apple's on-device models, or copy/paste to another assistant.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox("Provider") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Provider", selection: $provider) {
                            ForEach(AIProvider.allCases) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .labelsHidden()

                        if provider == .openAICompatible {
                            LabeledField("API key") {
                                SecureField("sk-…", text: $apiKey)
                            }
                            LabeledField("Endpoint") {
                                TextField("https://api.openai.com/v1/chat/completions", text: $endpoint)
                            }
                            LabeledField("Model") {
                                TextField("gpt-4o-mini", text: $model)
                            }
                        } else if provider == .copyPaste {
                            Text("Copies a model-ready prompt. Paste the response back below.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Uses Apple Foundation Models on supported macOS versions when the local model is available.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Picker("Feature", selection: $feature) {
                    ForEach(AIFeature.allCases) { feature in
                        Text(feature.displayName).tag(feature)
                    }
                }

                LabeledTextEditor(title: "Instruction", text: $instruction, minHeight: 120)

                HStack {
                    Button {
                        runAI()
                    } label: {
                        if isRunning {
                            ProgressView()
                                .controlSize(.small)
                            Text("Running…")
                        } else {
                            Label(primaryActionTitle, systemImage: primaryActionIcon)
                        }
                    }
                    .disabled(isRunning)
                    .buttonStyle(.borderedProminent)

                    if provider == .copyPaste {
                        Button("Paste Response", action: pasteAIResponse)
                    }
                }

                LabeledTextEditor(title: "Result", text: $output, minHeight: 240)
            }
            .padding(.vertical, 24)
            .padding(.leading, 24)
            .padding(.trailing, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var primaryActionTitle: String {
        switch provider {
        case .openAICompatible: "Run \(feature.displayName)"
        case .copyPaste: "Copy Prompt"
        case .foundationModels: "Run Locally"
        }
    }

    private var primaryActionIcon: String {
        switch provider {
        case .openAICompatible: "sparkles"
        case .copyPaste: "doc.on.doc"
        case .foundationModels: "apple.logo"
        }
    }

    private func runAI() {
        switch provider {
        case .openAICompatible:
            runOpenAICompatibleRequest()
        case .copyPaste:
            copyPromptToClipboard()
        case .foundationModels:
            runFoundationModelsRequest()
        }
    }

    private func runOpenAICompatibleRequest() {
        guard let endpointURL = URL(string: endpoint) else {
            output = "Enter a valid endpoint URL."
            return
        }

        isRunning = true
        output = "Running \(feature.displayName)…"
        let configuration = AIConfiguration(apiKey: apiKey, endpoint: endpointURL, model: model)

        Task {
            let result: String
            do {
                result = try await AIClient().run(feature: feature, quiz: quiz, instruction: instruction, configuration: configuration)
            } catch {
                result = "AI request failed: \(error)"
            }

            await MainActor.run {
                output = result
                isRunning = false
            }
        }
    }

    private func copyPromptToClipboard() {
        let prompt = AIPromptBuilder().makePrompt(feature: feature, quiz: quiz, userInstruction: instruction)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        output = "Prompt copied. Paste it into Claude, ChatGPT, or another model, then paste the response back here."
    }

    private func pasteAIResponse() {
        output = NSPasteboard.general.string(forType: .string) ?? "Clipboard does not contain text."
    }

    private func runFoundationModelsRequest() {
        isRunning = true
        output = "Checking Apple Foundation Models availability…"
        let prompt = AIPromptBuilder().makePrompt(feature: feature, quiz: quiz, userInstruction: instruction)

        Task {
            let result = await FoundationModelsRunner.run(prompt: prompt)
            await MainActor.run {
                output = result
                isRunning = false
            }
        }
    }
}


enum FoundationModelsRunner {
    static func run(prompt: String) async -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                return "Apple Foundation Models is not available on this Mac. Enable Apple Intelligence on a supported Mac, or use the Copy/Paste provider."
            }
            do {
                let session = LanguageModelSession(model: model, instructions: "You are a concise quiz review assistant.")
                let response = try await session.respond(to: prompt)
                return response.content
            } catch {
                return "Foundation Models request failed: \(error)"
            }
        }
        #endif
        return "Apple Foundation Models requires a FoundationModels-capable macOS SDK/runtime. Use the Copy/Paste provider or an OpenAI-compatible API on this Mac."
    }
}
struct ImportSheet: View {
    @Binding var importText: String
    @Binding var correctMarkerSymbol: String
    @Binding var correctMarkerLocation: CorrectAnswerMarker.Location
    let onImport: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Marked Text")
                .font(.title2.bold())
            Text("Choose the correct-answer marker used in the text. Distractors can still start with `-`; matching pairs use `Term => Match`.")
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 12) {
                LabeledField("Correct marker") {
                    TextField("*", text: $correctMarkerSymbol)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }

                LabeledField("Marker position") {
                    Picker("Marker position", selection: $correctMarkerLocation) {
                        ForEach(CorrectAnswerMarker.Location.allCases) { location in
                            Text(location.displayName).tag(location)
                        }
                    }
                    .labelsHidden()
                }
            }

            LabeledTextEditor(title: "Marked quiz text", text: $importText, minHeight: 360)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") { onImport(importText) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 620)
    }
}

struct LabeledField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
                .accessibilityLabel(title)
        }
    }
}

struct LabeledTextEditor: View {
    let title: String
    @Binding var text: String
    let minHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled(false)
                .padding(8)
                .frame(minHeight: minHeight)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(.rect(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25))
                )
                .accessibilityLabel(title)
        }
    }
}

// MARK: - Rich text (WYSIWYG) editing

/// Bridges SwiftUI toolbar actions to the contentEditable web view.
@MainActor
final class RichTextController: ObservableObject {
    weak var webView: WKWebView?

    func exec(_ command: String, value: String? = nil) {
        let arg = value.map { "'\($0.replacingOccurrences(of: "'", with: "\\'"))'" } ?? "null"
        webView?.evaluateJavaScript("editorExec('\(command)', \(arg));")
    }

    func insertHTML(_ html: String) {
        let escaped = html
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        webView?.evaluateJavaScript("editorInsert(`\(escaped)`);")
    }
}

/// A true WYSIWYG editor: a styled contentEditable web view that round-trips HTML.
struct RichTextEditor: NSViewRepresentable {
    @Binding var html: String
    let controller: RichTextController

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "changed")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        controller.webView = webView
        webView.loadHTMLString(Self.template, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Only push when the value changed externally (e.g. AI apply), not while typing.
        guard context.coordinator.isLoaded, html != context.coordinator.lastReportedHTML else { return }
        context.coordinator.setContent(html)
    }

    func makeCoordinator() -> Coordinator { Coordinator(html: $html) }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let html: Binding<String>
        weak var webView: WKWebView?
        var isLoaded = false
        var lastReportedHTML: String

        init(html: Binding<String>) {
            self.html = html
            self.lastReportedHTML = html.wrappedValue
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            setContent(html.wrappedValue)
        }

        func setContent(_ content: String) {
            lastReportedHTML = content
            let escaped = content
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
            webView?.evaluateJavaScript("editorSetContent(`\(escaped)`);")
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? String else { return }
            lastReportedHTML = body
            html.wrappedValue = body
        }
    }

    private static let template = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      :root { color-scheme: light dark; }
      html, body { margin: 0; height: 100%; }
      #editor {
        font: -apple-system-body;
        font-family: -apple-system, system-ui, sans-serif;
        padding: 10px; min-height: 100%; outline: none; line-height: 1.4;
        color: canvastext;
      }
      #editor:empty::before { content: "Start typing…"; color: gray; }
      table { border-collapse: collapse; margin: 8px 0; }
      th, td { border: 1px solid color-mix(in srgb, canvastext 35%, transparent); padding: 4px 8px; }
      img { max-width: 100%; height: auto; }
    </style>
    </head>
    <body>
    <div id="editor" contenteditable="true"></div>
    <script>
      const editor = document.getElementById('editor');
      function report() { window.webkit.messageHandlers.changed.postMessage(editor.innerHTML); }
      function editorSetContent(html) { editor.innerHTML = html; }
      function editorExec(cmd, val) { editor.focus(); document.execCommand(cmd, false, val); report(); }
      function editorInsert(html) { editor.focus(); document.execCommand('insertHTML', false, html); report(); }
      editor.addEventListener('input', report);
      editor.addEventListener('blur', report);
    </script>
    </body>
    </html>
    """
}

/// WYSIWYG rich text field with a formatting toolbar and enforced image alt text.
struct RichTextField: View {
    let title: String
    @Binding var text: String
    var minHeight: CGFloat = 160
    var showsTitle: Bool = true

    @StateObject private var controller = RichTextController()
    @State private var isImageSheetPresented = false
    private let html = HTMLUtilities()

    private var imagesMissingAlt: Int { html.imagesMissingAlt(in: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if showsTitle {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                formattingToolbar
            }

            if imagesMissingAlt > 0 {
                Label("\(imagesMissingAlt) image\(imagesMissingAlt == 1 ? "" : "s") missing alt text — add it before exporting.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            RichTextEditor(html: $text, controller: controller)
                .frame(minHeight: minHeight)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(.rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                .accessibilityLabel(title)
        }
        .sheet(isPresented: $isImageSheetPresented) {
            ImageInsertSheet { markup in
                controller.insertHTML(markup)
            }
        }
    }

    private var formattingToolbar: some View {
        HStack(spacing: 6) {
            toolbarButton("Bold", systemImage: "bold") { controller.exec("bold") }
            toolbarButton("Italic", systemImage: "italic") { controller.exec("italic") }
            toolbarButton("Underline", systemImage: "underline") { controller.exec("underline") }

            toolbarDivider

            toolbarButton("Bulleted list", systemImage: "list.bullet") { controller.exec("insertUnorderedList") }
            toolbarButton("Numbered list", systemImage: "list.number") { controller.exec("insertOrderedList") }

            toolbarDivider

            toolbarButton("Link", systemImage: "link") {
                controller.insertHTML("<a href=\"https://\">link text</a>")
            }
            toolbarButton("Table", systemImage: "tablecells") {
                controller.insertHTML("<table><tr><th>Header 1</th><th>Header 2</th></tr><tr><td>Cell</td><td>Cell</td></tr></table>")
            }
            toolbarButton("Insert image", systemImage: "photo") { isImageSheetPresented = true }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.quaternary, in: .rect(cornerRadius: 8))
    }

    private var toolbarDivider: some View {
        Divider().frame(height: 16)
    }

    private func toolbarButton(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .imageScale(.large)
                .frame(minWidth: 26, minHeight: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Picks an image file, embeds it, and requires alt text (or an explicit decorative choice).
struct ImageInsertSheet: View {
    let onInsert: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var fileName: String?
    @State private var dataURI: String?
    @State private var altText = ""
    @State private var isDecorative = false

    private var canInsert: Bool {
        dataURI != nil && (isDecorative || !altText.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Insert Image")
                .font(.title2.bold())
            Text("Choose an image file. Images need alt text describing their content, or mark the image decorative if it adds no information.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LabeledField("Image file") {
                HStack {
                    Button("Choose File…", action: chooseFile)
                    Text(fileName ?? "No file selected")
                        .font(.callout)
                        .foregroundStyle(fileName == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            LabeledField("Alt text") {
                TextField("Describe the image for screen readers", text: $altText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isDecorative)
            }

            Toggle("This image is decorative (no alt text needed)", isOn: $isDecorative)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Insert") {
                    guard let dataURI else { return }
                    let alt = isDecorative ? "" : altText.trimmingCharacters(in: .whitespacesAndNewlines)
                    onInsert("<img src=\"\(dataURI)\" alt=\"\(escapeAttribute(alt))\">")
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canInsert)
            }
        }
        .padding(24)
        .frame(minWidth: 480)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        let mime = mimeType(for: url.pathExtension.lowercased())
        fileName = url.lastPathComponent
        dataURI = "data:\(mime);base64,\(data.base64EncodedString())"
    }

    private func mimeType(for ext: String) -> String {
        switch ext {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "svg": "image/svg+xml"
        case "webp": "image/webp"
        default: "image/png"
        }
    }

    private func escapeAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
    }
}

/// Renders a complete HTML document (used for the formatted preview).
struct FullHTMLPreview: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }
}

/// Modal that previews a formatted version of one question or the full quiz.
struct QuizPreviewSheet: View {
    let quiz: Quiz
    let selectedQuestion: (number: Int, question: QuizQuestion)?
    @Environment(\.dismiss) private var dismiss

    private enum Scope: Hashable { case fullQuiz, question }
    @State private var scope: Scope = .fullQuiz
    @State private var showAnswerKey = true
    private let builder = FormattedDocumentBuilder()

    private var html: String {
        switch scope {
        case .question:
            if let selected = selectedQuestion {
                return builder.document(for: selected.question, number: selected.number, showAnswerKey: showAnswerKey)
            }
            return builder.document(for: quiz, showAnswerKey: showAnswerKey)
        case .fullQuiz:
            return builder.document(for: quiz, showAnswerKey: showAnswerKey)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Preview")
                    .font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            HStack {
                Picker("Scope", selection: $scope) {
                    Text("Full Quiz").tag(Scope.fullQuiz)
                    Text("This Question").tag(Scope.question)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(selectedQuestion == nil)
                .frame(width: 280)

                Spacer()

                Toggle("Show answer key", isOn: $showAnswerKey)
                    .toggleStyle(.switch)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            FullHTMLPreview(html: html)
        }
        .frame(minWidth: 720, minHeight: 640)
    }
}

struct QTIArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(quiz: Quiz, engine: CanvasQuizEngine) throws {
        self.data = try QTIPackageWriter(engine: engine).makeZipData(for: quiz)
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private let sampleImportText = """
Title: Photosynthesis Check

Type: Multiple Choice
Question: Which pigment captures light energy?
* Chlorophyll
- Glucose
- Oxygen
Feedback: Chlorophyll absorbs light during photosynthesis.

Type: Multiple Answer
Question: Select outputs of photosynthesis.
* Oxygen
* Glucose
- Nitrogen
Feedback: Oxygen and glucose are products of photosynthesis.
"""
