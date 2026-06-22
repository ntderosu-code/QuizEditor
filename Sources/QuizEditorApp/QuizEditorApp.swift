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
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 760)
        .commands {
            CommandGroup(after: .help) {
                AcknowledgementsMenuButton()
            }
            QuestionCommands()
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
        Credit(name: "Learning management systems", detail: "QTI 1.2/2.1 and IMS Common Cartridge interchange with Canvas, Brightspace, Blackboard, Moodle, and other LMSs.")
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
    @StateObject var personaStore = PersonaStore()
    @AppStorage("personaID") var appDefaultPersonaID = Persona.generalID
    @State var isPersonaSheetPresented = false
    @StateObject var frameworkStore = FrameworkStore()
    @State var isCoverageSheetPresented = false
    @State var isFrameworkSheetPresented = false

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
                onNudge: nudgeQuestion(id:by:)
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            ZStack {
                // Neutral canvas behind the floating editor card. It still bleeds
                // under the Liquid Glass sidebar and inspector via
                // backgroundExtensionEffect (WWDC25 session 356), but carries no
                // accent tint so the central editing area stays neutral.
                Color(nsColor: .windowBackgroundColor)
                    .backgroundExtensionEffect()

                // The editor floats as a card on top of the canvas.
                editorDetail
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(.rect(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 2)
                    .padding(16)
            }
            // Fill the detail column so the window can grow freely. Without
            // maxWidth/maxHeight the content reports a fixed ideal size and the
            // window gets a hard maximum size.
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .inspector(isPresented: $isAIPanelVisible) {
            AIPanel(
                quiz: $quiz,
                quizTitle: quiz.title,
                selectedQuestion: selectedQuestionBinding,
                selectedQuestionNumber: selectedQuestionNumber,
                onAuthorWithAI: { isAuthoringPresented = true },
                persona: activePersona,
                frameworks: frameworkStore.frameworks
            )
            .inspectorColumnWidth(min: 280, ideal: 320, max: 440)
        }
        .toolbar {
            // Add Question and Import live on the sidebar's own toolbar bar
            // (over the question list). The clusters here are document/AI tools,
            // each its own Liquid Glass capsule separated by flexible spacers.
            ToolbarItemGroup {
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
                .help("Export as a QTI package (for Canvas and other LMSs), a formatted document, or a printable paper exam")

                Button {
                    previewScopedToQuestion = false
                    isPreviewPresented = true
                } label: {
                    Label("Preview", systemImage: "eye")
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .help("Preview a formatted version of the whole quiz (⇧⌘P)")
            }

            ToolbarSpacer(.flexible)

            ToolbarItemGroup {
                Button {
                    isAuthoringPresented = true
                } label: {
                    Label("Draft with AI", systemImage: "sparkles")
                }
                .help("Generate new questions from a topic or learning objective")

                Menu {
                    Button(AppCopy.checkQuiz) {
                        isLintSheetPresented = true
                    }

                    Divider()

                    Section("Review Profile") {
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
                    .keyboardShortcut("p", modifiers: [.command, .option])
                } label: {
                    Label(AppCopy.checkQuiz, systemImage: "checklist")
                } primaryAction: {
                    isLintSheetPresented = true
                }
                .help("Run offline checks for clarity, answer keys, accessibility, and LMS import readiness")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAIPanelVisible.toggle()
                } label: {
                    Label(AppCopy.aiSuggestions, systemImage: isAIPanelVisible ? "sidebar.trailing" : "sidebar.right")
                }
                .keyboardShortcut("a", modifiers: [.command, .option])
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
        .focusedValue(\.quizCommandActions, makeCommandActions())
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

            LabeledTextEditor(
                title: "Marked quiz text",
                text: $importText,
                minHeight: 320,
                placeholder: "Paste or type your questions here. See the formatting guide below for the syntax."
            )

            MarkedTextFormatReference()

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
