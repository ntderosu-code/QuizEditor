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
    /// Personas and frameworks are app-wide libraries, not per-document data, so
    /// they are owned once here. Each document window used to build its own
    /// store, which meant editing a persona in one window left every other
    /// window showing the stale copy — and the Settings scene, which lives
    /// outside `DocumentGroup`, could not see them at all.
    @StateObject private var personaStore = PersonaStore()
    @StateObject private var frameworkStore = FrameworkStore()

    init() {
        // Open straight into a blank untitled document instead of showing the
        // open-file panel on launch.
        UserDefaults.standard.register(
            defaults: ["NSShowAppCentricOpenPanelInsteadOfUntitledFile": false]
        )
    }

    var body: some Scene {
        DocumentGroup(newDocument: QuizDocument()) { file in
            ContentView(quiz: file.$document.quiz)
                .frame(minWidth: 760, minHeight: 480)
                .environmentObject(personaStore)
                .environmentObject(frameworkStore)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 760)
        .commands {
            QuizDocumentCommands()
            QuestionCommands()
        }

        Settings {
            AppSettingsView()
                .environmentObject(personaStore)
                .environmentObject(frameworkStore)
        }

    }
}

/// A reference target the window's UndoManager can register against. ContentView
/// is a value type, so structural quiz edits route their undo through this class.
@MainActor final class UndoCoordinator: ObservableObject {}

/// Parsed questions waiting for the import picker, which is presented only after
/// the marked-text import sheet has fully dismissed (two sheets can't overlap).
struct PendingImport {
    let questions: [QuizQuestion]
    let importedTitle: String?
    let source: String
}

/// Drives the shared import/merge picker sheet.
struct ImportPickerContext: Identifiable {
    let id = UUID()
    let title: String
    let sourceDescription: String
    let candidates: [ImportCandidate]
    let confirmVerb: String
    let importedTitle: String?
    let actionName: String
    let onConfirm: ([QuizQuestion], String?, String) -> Void
}

struct ContentView: View {
    @Binding var quiz: Quiz
    @Environment(\.undoManager) var undoManager
    @StateObject var undoCoordinator = UndoCoordinator()
    @State var selectedQuestionID: UUID?
    @State var isImporterPresented = false
    @State var isQTIImporterPresented = false
    @State var isMergeImporterPresented = false
    @State var importText = ""
    @State var errorMessage: String?
    /// Title for the `errorMessage` alert. Nil means the generic failure title;
    /// a rejected drop sets its own, because "the file type isn't supported" is
    /// not something going wrong.
    @State var errorTitle: String?
    @State var exportDocument = QTIArchiveDocument(data: Data())
    @State var isExporterPresented = false
    @State var correctMarkerSymbol = "*"
    @State var correctMarkerLocation = CorrectAnswerMarker.Location.beginningOfLine
    @State var isAIPanelVisible = true
    @State var importPreservesFormatting = true
    @State var isPreviewPresented = false
    /// When the preview is opened from the question header it starts scoped to the
    /// current question; the toolbar Preview opens the whole quiz.
    @State var previewScopedToQuestion = false
    @State var isQuickSwitchPresented = false
    @State var isPaperExamPresented = false
    @State var isBankPresented = false
    @State var isAuthoringPresented = false
    @State var isLintSheetPresented = false
    @State var importPickerContext: ImportPickerContext?
    @State var pendingImport: PendingImport?
    @State var qtiValidation: QTIValidationContext?
    @State var pendingExportEngine: CanvasQuizEngine?
    @State var isIMSCCImporterPresented = false
    @EnvironmentObject var personaStore: PersonaStore
    @AppStorage("personaID") var appDefaultPersonaID = Persona.generalID
    @State var isPersonaSheetPresented = false
    @EnvironmentObject var frameworkStore: FrameworkStore
    @State var isCoverageSheetPresented = false
    @State var isFrameworkSheetPresented = false

    /// Focuses the sidebar's filter field, so Edit ▸ Filter Questions (⌘F) has
    /// somewhere to land. Declared here rather than in `SidebarView` because the
    /// menu command reaches the document through this view's focused value.
    @FocusState var isFilterFieldFocused: Bool

    /// Cached quiz-wide lint, recomputed only when the quiz or active persona
    /// changes (not on every render — selection, sheet toggles, etc.).
    @State var lintFindings: [UUID: [LintFinding]] = [:]

    func recomputeLintFindings() {
        lintFindings = QuestionLinter().findings(for: quiz, persona: activePersona)
    }

    /// The persona in effect for this quiz: its own override, else the app default,
    /// else General. The linter reads it so inline lint, the sidebar status dot,
    /// and Check Quiz all reflect the active discipline.
    var activePersona: Persona {
        personaStore.resolve(quiz.personaID ?? appDefaultPersonaID)
    }

    /// A binding to the currently selected question's element in the quiz, so the
    /// AI panel's item-level tools can read and write it directly. Nil when nothing
    /// is selected or the selection no longer exists.
    var selectedQuestionBinding: Binding<QuizQuestion>? {
        guard let id = selectedQuestionID,
              let index = quiz.questions.firstIndex(where: { $0.id == id }) else { return nil }
        return $quiz.questions[index]
    }

    var selectedQuestionNumber: Int? {
        guard let id = selectedQuestionID,
              let index = quiz.questions.firstIndex(where: { $0.id == id }) else { return nil }
        return index + 1
    }

    /// The editing surface: a floating card on a neutral canvas.
    private var editorCanvas: some View {
        ZStack {
            // Neutral canvas behind the floating editor card. It still bleeds
            // under the Liquid Glass sidebar via backgroundExtensionEffect
            // (WWDC25 session 356), but carries no accent tint so the central
            // editing area stays neutral.
            Color(nsColor: .windowBackgroundColor)
                .backgroundExtensionEffect()

            // The editor floats as a card on top of the canvas.
            editorDetail
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(.rect(cornerRadius: 16))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 2)
                .padding(16)
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                quiz: $quiz,
                selectedQuestionID: $selectedQuestionID,
                lintFindings: lintFindings,
                onAddQuestion: addQuestion,
                onImportMarkedText: { isImporterPresented = true },
                onImportQTI: { keepFormatting in
                    importPreservesFormatting = keepFormatting
                    isQTIImporterPresented = true
                },
                onImportCommonCartridge: { isIMSCCImporterPresented = true },
                onMergeFromFile: { isMergeImporterPresented = true },
                onOpenBank: { isBankPresented = true },
                onDuplicate: duplicateQuestion(id:),
                onDelete: deleteQuestion(id:),
                onMove: moveQuestions(from:to:),
                onNudge: nudgeQuestion(id:by:),
                filterFieldFocus: $isFilterFieldFocused
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            // The AI panel is a sibling of the editor inside the detail column,
            // not a SwiftUI `.inspector`. `.inspector` on a NavigationSplitView
            // put AppKit into a constraint-update loop that killed the window
            // the moment the sidebar divider was dragged (#97).
            HSplitView {
                editorCanvas
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)

                if isAIPanelVisible {
                    AIPanel(
                        quiz: $quiz,
                        quizTitle: quiz.title,
                        selectedQuestion: selectedQuestionBinding,
                        selectedQuestionNumber: selectedQuestionNumber,
                        onAuthorWithAI: { isAuthoringPresented = true },
                        persona: activePersona,
                        frameworks: frameworkStore.frameworks
                    )
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 440, maxHeight: .infinity)
                    // `.inspector` supplied this material for free. As an
                    // ordinary split child the panel would sit on plain white,
                    // reading as more editor rather than as chrome. The material
                    // ignores the safe area so it runs up under the toolbar, the
                    // way the inspector's did; the content stays inset.
                    .background {
                        VisualEffectBackground().ignoresSafeArea()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            // Add Question and Import live on the sidebar's own toolbar bar
            // (over the question list). The clusters here are document/AI tools,
            // and the placements do the grouping.
            //
            // Deliberately NOT .toolbar(id:). Giving every document window the
            // same toolbar identifier makes AppKit re-insert SwiftUI's own
            // sidebar-toggle item into a toolbar that already has it, and
            // File ▸ New then dies on "already contains an item with the
            // identifier com.apple.SwiftUI.navigationSplitView.toggleSidebar".
            // The identifier also never bought us the customization palette:
            // right-clicking the toolbar offered only the display-mode items,
            // with no "Customize Toolbar…" entry.
            ToolbarItem {
                Menu {
                    Section("QTI Package") {
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
                    Button("Paper Exam…") {
                        isPaperExamPresented = true
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .menuIndicator(.hidden)
                .accessibilityLabel("Export")
                .help("Export as a QTI package (for Canvas and other LMSs), a formatted document, or a printable paper exam")
            }

            ToolbarItem {
                Button {
                    previewScopedToQuestion = false
                    isPreviewPresented = true
                } label: {
                    Label("Preview", systemImage: "eye")
                }
                .help("Preview a formatted version of the whole quiz (⇧⌘P)")
            }

            ToolbarItem {
                Button {
                    isAuthoringPresented = true
                } label: {
                    Label("Draft with AI", systemImage: "sparkles")
                }
                .help("Generate new questions from a topic or learning objective")
            }

            ToolbarItem {
                Menu {
                    Button(AppCopy.checkQuiz) {
                        isLintSheetPresented = true
                    }
                    Button("Competency Coverage…") {
                        isCoverageSheetPresented = true
                    }

                    Divider()

                    Section {
                        Picker("Review Profile", selection: $quiz.personaID) {
                            Text("App Default (\(personaStore.resolve(appDefaultPersonaID).displayName))")
                                .tag(String?.none)
                            ForEach(personaStore.personas) { persona in
                                Text(persona.displayName).tag(Optional(persona.id))
                            }
                        }
                        .pickerStyle(.inline)
                    }

                    Divider()

                    Button {
                        isPersonaSheetPresented = true
                    } label: {
                        Label("Manage Review Profiles…", systemImage: "slider.horizontal.3")
                    }
                    Button {
                        isFrameworkSheetPresented = true
                    } label: {
                        Label("Manage Frameworks…", systemImage: "list.bullet.indent")
                    }
                } label: {
                    Label(AppCopy.checkQuiz, systemImage: "checklist")
                } primaryAction: {
                    isLintSheetPresented = true
                }
                .accessibilityLabel(AppCopy.checkQuiz)
                .help("Run offline checks for clarity, answer keys, accessibility, and LMS import readiness")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAIPanelVisible.toggle()
                } label: {
                    Label(AppCopy.aiSuggestions, systemImage: isAIPanelVisible ? "sidebar.trailing" : "sidebar.right")
                }
                .help(isAIPanelVisible ? "Hide the AI Suggestions panel (⌥⌘A)" : "Show the AI Suggestions panel (⌥⌘A)")
            }
        }
        .onAppear {
            if selectedQuestionID == nil {
                selectedQuestionID = quiz.questions.first?.id
            }
            recomputeLintFindings()
        }
        .onChange(of: quiz) { recomputeLintFindings() }
        .onChange(of: appDefaultPersonaID) { recomputeLintFindings() }
        .onChange(of: personaStore.personas) { recomputeLintFindings() }
        .sheet(isPresented: $isImporterPresented, onDismiss: presentPendingImportPicker) {
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
            QuizPreviewSheet(quiz: quiz, selectedQuestion: selectedQuestionForPreview, startScopedToQuestion: previewScopedToQuestion)
        }
        .sheet(isPresented: $isQuickSwitchPresented) {
            QuickSwitchSheet(quiz: quiz) { id in selectedQuestionID = id }
        }
        .sheet(isPresented: $isPaperExamPresented) {
            PaperExamOptionsSheet { options in exportPaperExam(options) }
        }
        .sheet(isPresented: $isBankPresented) {
            QuestionBankSheet { questions in addQuestions(questions, actionName: "Add from Bank") }
        }
        .sheet(isPresented: $isAuthoringPresented) {
            AIAuthoringSheet(quizTitle: quiz.title, persona: activePersona) { questions in addQuestions(questions, actionName: "Add AI Questions") }
        }
        .sheet(isPresented: $isLintSheetPresented) {
            QuizLintSheet(quiz: quiz, persona: activePersona) { id in selectedQuestionID = id }
        }
        .sheet(isPresented: $isPersonaSheetPresented) {
            PersonaManagementSheet(store: personaStore, quizPersonaID: $quiz.personaID)
        }
        .sheet(isPresented: $isCoverageSheetPresented) {
            CoverageReportSheet(quiz: quiz, frameworks: frameworkStore.frameworks)
        }
        .sheet(isPresented: $isFrameworkSheetPresented) {
            FrameworkManagementSheet(store: frameworkStore)
        }
        .sheet(item: $importPickerContext) { context in
            ImportPickerSheet(
                title: context.title,
                sourceDescription: context.sourceDescription,
                candidates: context.candidates,
                confirmVerb: context.confirmVerb
            ) { selected in
                context.onConfirm(selected, context.importedTitle, context.actionName)
            }
        }
        .fileImporter(
            isPresented: $isMergeImporterPresented,
            allowedContentTypes: [.quizEditorDocument, .zip],
            allowsMultipleSelection: true
        ) { result in
            mergeFromFiles(result)
        }
        .fileImporter(
            isPresented: $isIMSCCImporterPresented,
            allowedContentTypes: imsccContentTypes,
            allowsMultipleSelection: false
        ) { result in
            importCommonCartridge(result)
        }
        .sheet(item: $qtiValidation, onDismiss: {
            // Run the export only after the validation sheet has fully dismissed,
            // so the file exporter doesn't fight a still-closing sheet.
            if let engine = pendingExportEngine {
                pendingExportEngine = nil
                finishExport(engine: engine)
            }
        }) { context in
            QTIValidationSheet(engineName: context.engine.displayName, issues: context.issues) {
                pendingExportEngine = context.engine
            }
        }
        // Scene-scoped, not view-scoped: with .focusedValue these go nil the
        // moment no control in the window holds focus, which is exactly what
        // ⌘Home/⌘End leave behind when they rebuild the detail view. The whole
        // Question menu then went dead until the user clicked something.
        .focusedSceneValue(\.quizCommandActions, makeCommandActions())
        .focusedSceneValue(\.quizDocumentActions, makeDocumentActions())
        .dropDestination(for: URL.self) { urls, _ in
            handleDroppedFiles(urls)
        }
        .alert(
            errorTitle ?? "Something Went Wrong",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: {
                    if !$0 {
                        errorMessage = nil
                        errorTitle = nil
                    }
                }
            ),
            presenting: errorMessage
        ) { _ in
            Button("OK", role: .cancel) { }
        } message: { message in
            Text(message)
        }
    }

}

struct ImportSheet: View {
    @Binding var importText: String
    @Binding var correctMarkerSymbol: String
    @Binding var correctMarkerLocation: CorrectAnswerMarker.Location
    let onImport: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Fixed header, scrolling body, fixed footer: expanding the formatting
        // guide grows the body instead of pushing the Import button off the sheet.
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Import Marked Text")
                    .font(.title2.bold())
                Text("Choose the correct-answer marker used in the text. Distractors can still start with `-`; matching pairs use `Term => Match`.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    importFields
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 2)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") { onImport(importText) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 620)
    }

    @ViewBuilder
    private var importFields: some View {
        Group {
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

            LabeledTextEditor(
                title: "Marked quiz text",
                text: $importText,
                minHeight: 320,
                placeholder: "Paste or type your questions here. See the formatting guide below for the syntax."
            )

            MarkedTextFormatReference()
        }
    }
}

/// A collapsible guide to the marked-text syntax, with a worked example. Shown in
/// the import sheet so the field itself can start empty instead of pre-filled with
/// sample text that could be imported by accident.
struct MarkedTextFormatReference: View {
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    rule("`Title:` names the quiz (optional, once at the top).")
                    rule("`Type:` starts a question, e.g. Multiple Choice, True/False, Short Answer.")
                    rule("`Question:` the prompt text.")
                    rule("`*` marks a correct answer; `-` marks a distractor.")
                    rule("`Term => Match` pairs an item for matching questions.")
                    rule("`Feedback:` optional explanation shown after answering.")
                }

                Text("Example")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(sampleImportText)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
            }
            .padding(.top, 8)
        } label: {
            Label("Formatting guide", systemImage: "text.book.closed")
                .font(.subheadline.weight(.semibold))
        }
    }

    /// Renders one syntax rule from a Markdown string; inline `code` spans render
    /// monospaced, which avoids the deprecated `Text` + `Text` concatenation.
    private func rule(_ markdown: LocalizedStringKey) -> some View {
        Text(markdown)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct QuizPreviewSheet: View {
    let quiz: Quiz
    let selectedQuestion: (number: Int, question: QuizQuestion)?
    /// Opened from the question header → start on this question; from the toolbar → whole quiz.
    var startScopedToQuestion: Bool = false
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
        .onAppear {
            if startScopedToQuestion, selectedQuestion != nil {
                scope = .question
            }
        }
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
