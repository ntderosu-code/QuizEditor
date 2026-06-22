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
    @Environment(\.undoManager) private var undoManager
    @StateObject private var undoCoordinator = UndoCoordinator()
    @State private var selectedQuestionID: UUID?
    @State private var isImporterPresented = false
    @State private var isQTIImporterPresented = false
    @State private var isMergeImporterPresented = false
    @State private var importText = ""
    @State private var errorMessage: String?
    @State private var exportDocument = QTIArchiveDocument(data: Data())
    @State private var isExporterPresented = false
    @State private var correctMarkerSymbol = "*"
    @State private var correctMarkerLocation = CorrectAnswerMarker.Location.beginningOfLine
    @State private var isAIPanelVisible = true
    @State private var importPreservesFormatting = true
    @State private var isPreviewPresented = false
    @State private var isQuickSwitchPresented = false
    @State private var isPaperExamPresented = false
    @State private var isBankPresented = false
    @State private var isAuthoringPresented = false
    @State private var isLintSheetPresented = false
    @State private var importPickerContext: ImportPickerContext?
    @State private var pendingImport: PendingImport?
    @State private var qtiValidation: QTIValidationContext?
    @State private var pendingExportEngine: CanvasQuizEngine?
    @State private var isIMSCCImporterPresented = false
    @StateObject private var personaStore = PersonaStore()
    @AppStorage("personaID") private var appDefaultPersonaID = Persona.generalID
    @State private var isPersonaSheetPresented = false
    @StateObject private var frameworkStore = FrameworkStore()
    @State private var isCoverageSheetPresented = false
    @State private var isFrameworkSheetPresented = false

    private var lintFindings: [UUID: [LintFinding]] { QuestionLinter().findings(for: quiz, persona: activePersona) }

    /// The persona in effect for this quiz: its own override, else the app default,
    /// else General. The linter reads it so inline lint, the sidebar status dot,
    /// and Quality Check all reflect the active discipline.
    private var activePersona: Persona {
        personaStore.resolve(quiz.personaID ?? appDefaultPersonaID)
    }

    /// A binding to the currently selected question's element in the quiz, so the
    /// AI panel's item-level tools can read and write it directly. Nil when nothing
    /// is selected or the selection no longer exists.
    private var selectedQuestionBinding: Binding<QuizQuestion>? {
        guard let id = selectedQuestionID,
              let index = quiz.questions.firstIndex(where: { $0.id == id }) else { return nil }
        return $quiz.questions[index]
    }

    private var selectedQuestionNumber: Int? {
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
                onDuplicate: duplicateQuestion(id:),
                onDelete: deleteQuestion(id:),
                onMove: moveQuestions(from:to:),
                onNudge: nudgeQuestion(id:by:),
                onOpenBank: { isBankPresented = true },
                onMergeFromFile: { isMergeImporterPresented = true },
                onImportCommonCartridge: { isIMSCCImporterPresented = true }
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
            // Grouped by function so each cluster renders as its own Liquid
            // Glass capsule, separated by ToolbarSpacer (not crammed into one
            // shared glass background).
            ToolbarItem {
                Button {
                    addQuestion()
                } label: {
                    Label("Add Question", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help("Add a new question (⇧⌘N)")
            }

            ToolbarSpacer(.fixed)

            ToolbarItemGroup {
                Button {
                    isImporterPresented = true
                } label: {
                    Label("Import Marked Text", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .help("Import questions from marked plain text (⇧⌘I)")

                Menu {
                    Section("QTI Package (.zip)") {
                        Button("Keep Formatting…") {
                            importPreservesFormatting = true
                            isQTIImporterPresented = true
                        }
                        Button("Plain Text…") {
                            importPreservesFormatting = false
                            isQTIImporterPresented = true
                        }
                    }
                    Divider()
                    Button("Common Cartridge (.imscc)…") {
                        isIMSCCImporterPresented = true
                    }
                } label: {
                    Label("Import Package", systemImage: "doc.zipper")
                } primaryAction: {
                    importPreservesFormatting = true
                    isQTIImporterPresented = true
                }
                .help("Import a QTI .zip or an IMS Common Cartridge (.imscc) — works with packages from Canvas and other LMSs")
            }

            ToolbarSpacer(.fixed)

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
                    isPreviewPresented = true
                } label: {
                    Label("Preview", systemImage: "eye")
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .help("Preview a formatted version of the quiz (⇧⌘P)")
            }

            ToolbarSpacer(.fixed)

            ToolbarItemGroup {
                Button {
                    isBankPresented = true
                } label: {
                    Label("Question Bank", systemImage: "books.vertical")
                }
                .help("Browse and add questions from a folder of saved quizzes")

                Button {
                    isAuthoringPresented = true
                } label: {
                    Label("Author with AI", systemImage: "sparkles")
                }
                .help("Generate new questions from a topic or learning objective")

                Menu {
                    Button {
                        isLintSheetPresented = true
                    } label: {
                        Label("Item-writing check", systemImage: "checklist")
                    }
                    Button {
                        isCoverageSheetPresented = true
                    } label: {
                        Label("Competency coverage…", systemImage: "chart.bar.doc.horizontal")
                    }
                    Divider()
                    Button {
                        isFrameworkSheetPresented = true
                    } label: {
                        Label("Manage frameworks…", systemImage: "list.bullet.indent")
                    }
                } label: {
                    Label("Quality Check", systemImage: "checklist")
                }
                .menuIndicator(.hidden)
                .help("Run the offline item-writing linter, view competency coverage, or manage frameworks")

                Menu {
                    Picker("Persona", selection: $quiz.personaID) {
                        Text("App Default (\(personaStore.resolve(appDefaultPersonaID).displayName))")
                            .tag(String?.none)
                        ForEach(personaStore.personas) { persona in
                            Text(persona.displayName).tag(Optional(persona.id))
                        }
                    }
                    .pickerStyle(.inline)

                    Divider()

                    Button {
                        isPersonaSheetPresented = true
                    } label: {
                        Label("Manage Personas…", systemImage: "slider.horizontal.3")
                    }
                    .keyboardShortcut("p", modifiers: [.command, .option])
                } label: {
                    Label("Persona: \(activePersona.displayName)", systemImage: "person.crop.rectangle")
                }
                .menuIndicator(.hidden)
                .help("Choose the discipline persona for this quiz (⌥⌘P to manage)")
            }

            ToolbarSpacer(.fixed)

            ToolbarItem {
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
            QuizPreviewSheet(quiz: quiz, selectedQuestion: selectedQuestionForPreview)
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
                questionTotal: quiz.questions.count,
                objectives: $quiz.objectives,
                sources: $quiz.sources,
                stimuli: $quiz.stimuli,
                frameworks: frameworkStore.frameworks,
                persona: activePersona
            ) {
                deleteQuestion(id: quiz.questions[selectedIndex].id)
            }
            .id(quiz.questions[selectedIndex].id)
        } else {
            ContentUnavailableView {
                Label("No Question Selected", systemImage: "questionmark.square.dashed")
            } description: {
                Text("Choose a question or add a new one to start writing.")
            } actions: {
                // Stack the actions so they never overflow the (sometimes narrow)
                // editor card. Each stretches to a shared width for a tidy column.
                VStack(spacing: 8) {
                    Button {
                        addQuestion()
                    } label: {
                        Label("Add Question", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("Import Marked Text", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }

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
                        Label("Import QTI Zip", systemImage: "doc.zipper")
                            .frame(maxWidth: .infinity)
                    } primaryAction: {
                        importPreservesFormatting = true
                        isQTIImporterPresented = true
                    }
                }
                .frame(width: 240)
            }
        }
    }

    private var defaultExportFilename: String {
        let safeTitle = quiz.title
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return (safeTitle.isEmpty ? "canvas-quiz" : safeTitle) + ".zip"
    }

    // MARK: - Question mutations (undoable)

    /// Applies a structural change to the quiz and registers it with the window's
    /// UndoManager so Edit ▸ Undo restores the prior state (e.g. before a merge).
    private func mutateQuiz(to newQuiz: Quiz, actionName: String) {
        let previous = quiz
        quiz = newQuiz
        registerUndo(restoring: previous, then: newQuiz, actionName: actionName)
    }

    private func registerUndo(restoring restoreState: Quiz, then redoState: Quiz, actionName: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: undoCoordinator) { _ in
            quiz = restoreState
            fixSelection(in: restoreState)
            registerUndo(restoring: redoState, then: restoreState, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    private func fixSelection(in quizState: Quiz) {
        if let selected = selectedQuestionID, quizState.questions.contains(where: { $0.id == selected }) { return }
        selectedQuestionID = quizState.questions.first?.id
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
        var updated = quiz
        updated.questions.append(question)
        mutateQuiz(to: updated, actionName: "Add Question")
        selectedQuestionID = question.id
    }

    /// Appends questions (with fresh IDs) from the bank or AI authoring.
    private func addQuestions(_ questions: [QuizQuestion], actionName: String) {
        guard !questions.isEmpty else { return }
        let merger = QuizMerger()
        let fresh = questions.map { merger.withFreshIDs($0) }
        var updated = quiz
        updated.questions.append(contentsOf: fresh)
        mutateQuiz(to: updated, actionName: actionName)
        if let first = fresh.first?.id { selectedQuestionID = first }
    }

    private func duplicateQuestion(id: UUID) {
        guard let index = quiz.questions.firstIndex(where: { $0.id == id }) else { return }
        let copy = QuizMerger().withFreshIDs(quiz.questions[index])
        var updated = quiz
        updated.questions.insert(copy, at: index + 1)
        mutateQuiz(to: updated, actionName: "Duplicate Question")
        selectedQuestionID = copy.id
    }

    private func deleteQuestion(id: UUID) {
        guard let index = quiz.questions.firstIndex(where: { $0.id == id }) else { return }
        var updated = quiz
        updated.questions.remove(at: index)
        mutateQuiz(to: updated, actionName: "Delete Question")
        if selectedQuestionID == id {
            let nextIndex = min(index, updated.questions.count - 1)
            selectedQuestionID = updated.questions.indices.contains(nextIndex) ? updated.questions[nextIndex].id : nil
        }
    }

    private func moveQuestions(from offsets: IndexSet, to destination: Int) {
        var updated = quiz
        updated.questions.move(fromOffsets: offsets, toOffset: destination)
        mutateQuiz(to: updated, actionName: "Reorder Questions")
    }

    private func nudgeQuestion(id: UUID, by delta: Int) {
        guard let index = quiz.questions.firstIndex(where: { $0.id == id }) else { return }
        let target = index + delta
        guard quiz.questions.indices.contains(target) else { return }
        var updated = quiz
        updated.questions.swapAt(index, target)
        mutateQuiz(to: updated, actionName: "Move Question")
        selectedQuestionID = id
    }

    // MARK: - Selection / navigation

    private func selectAdjacent(_ delta: Int) {
        guard let current = selectedQuestionID,
              let index = quiz.questions.firstIndex(where: { $0.id == current }) else {
            selectedQuestionID = quiz.questions.first?.id
            return
        }
        let target = index + delta
        guard quiz.questions.indices.contains(target) else { return }
        selectedQuestionID = quiz.questions[target].id
    }

    private func selectEdge(first: Bool) {
        selectedQuestionID = first ? quiz.questions.first?.id : quiz.questions.last?.id
    }

    private func makeCommandActions() -> QuizCommandActions {
        let index = selectedQuestionID.flatMap { id in quiz.questions.firstIndex(where: { $0.id == id }) }
        let lastIndex = quiz.questions.count - 1
        return QuizCommandActions(
            hasSelection: selectedQuestionID != nil,
            canSelectPrevious: (index ?? 0) > 0,
            canSelectNext: index.map { $0 < lastIndex } ?? false,
            canMoveUp: (index ?? 0) > 0,
            canMoveDown: index.map { $0 < lastIndex } ?? false,
            addQuestion: addQuestion,
            selectPrevious: { selectAdjacent(-1) },
            selectNext: { selectAdjacent(1) },
            selectFirst: { selectEdge(first: true) },
            selectLast: { selectEdge(first: false) },
            moveUp: { if let id = selectedQuestionID { nudgeQuestion(id: id, by: -1) } },
            moveDown: { if let id = selectedQuestionID { nudgeQuestion(id: id, by: 1) } },
            duplicate: { if let id = selectedQuestionID { duplicateQuestion(id: id) } },
            delete: { if let id = selectedQuestionID { deleteQuestion(id: id) } },
            showQuickSwitch: { isQuickSwitchPresented = true }
        )
    }

    // MARK: - Import / merge (via the question picker)

    private func importMarkedText(_ text: String) {
        do {
            let marker = CorrectAnswerMarker(symbol: correctMarkerSymbol, location: correctMarkerLocation)
            let parsed = try MarkedTextParser(correctAnswerMarker: marker).parse(text)
            // Defer the picker until the import sheet has fully dismissed.
            pendingImport = PendingImport(questions: parsed.questions, importedTitle: parsed.title, source: "marked text")
            isImporterPresented = false
        } catch {
            // Close the sheet so the error alert (declared under it) can present;
            // pendingImport stays nil so onDismiss won't open the picker.
            pendingImport = nil
            isImporterPresented = false
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func presentPendingImportPicker() {
        guard let pending = pendingImport else { return }
        pendingImport = nil
        presentImportPicker(questions: pending.questions, importedTitle: pending.importedTitle, source: pending.source)
    }

    private func importQTIArchive(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            let imported = try QTIImporter(preserveFormatting: importPreservesFormatting).importQuiz(fromZipAt: url)
            presentImportPicker(questions: imported.questions, importedTitle: imported.title, source: url.lastPathComponent)
        } catch {
            errorMessage = "QTI import failed: \(error.localizedDescription)"
        }
    }

    private func presentImportPicker(questions: [QuizQuestion], importedTitle: String?, source: String) {
        guard !questions.isEmpty else {
            errorMessage = "No questions were found in the \(source)."
            return
        }
        importPickerContext = ImportPickerContext(
            title: "Import Questions",
            sourceDescription: "From \(source) — choose which questions to import.",
            candidates: importCandidates(for: questions),
            confirmVerb: "Import",
            importedTitle: importedTitle,
            actionName: "Import Questions",
            onConfirm: { selected, title, action in commitImport(selected, importedTitle: title, actionName: action) }
        )
    }

    private func mergeFromFiles(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }

            var collected: [QuizQuestion] = []
            var failed: [String] = []
            for url in urls {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                if let questions = try? loadQuestions(from: url) {
                    collected.append(contentsOf: questions)
                } else {
                    failed.append(url.lastPathComponent)
                }
            }

            guard !collected.isEmpty else {
                errorMessage = "No questions could be read from the selected file\(urls.count == 1 ? "" : "s")."
                return
            }

            let names = urls.map(\.lastPathComponent).joined(separator: ", ")
            var description = "From \(names) — duplicates are unchecked. Checking a duplicate keeps both copies."
            if !failed.isEmpty { description += " Couldn't read: \(failed.joined(separator: ", "))." }

            importPickerContext = ImportPickerContext(
                title: "Merge Questions",
                sourceDescription: description,
                candidates: importCandidates(for: collected),
                confirmVerb: "Merge",
                importedTitle: nil,
                actionName: "Merge Questions",
                onConfirm: { selected, title, action in commitImport(selected, importedTitle: title, actionName: action) }
            )
        } catch {
            errorMessage = "Merge failed: \(error.localizedDescription)"
        }
    }

    private func loadQuestions(from url: URL) throws -> [QuizQuestion] {
        if url.pathExtension.lowercased() == "zip" {
            return try QTIImporter().importQuiz(fromZipAt: url).questions
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Quiz.self, from: data).questions
    }

    /// Flags incoming questions that duplicate one already in the quiz (prompt + type).
    private func importCandidates(for questions: [QuizQuestion]) -> [ImportCandidate] {
        let merger = QuizMerger()
        let existingKeys = Set(quiz.questions.map(merger.duplicateKey(for:)))
        return questions.map {
            ImportCandidate(question: $0, isDuplicate: existingKeys.contains(merger.duplicateKey(for: $0)))
        }
    }

    // MARK: - Common Cartridge (.imscc) import

    private var imsccContentTypes: [UTType] {
        if let imscc = UTType(filenameExtension: "imscc") {
            return [imscc, .zip]
        }
        return [.zip]
    }

    private func importCommonCartridge(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

            let sections = try QTIImporter(preserveFormatting: importPreservesFormatting).importSections(fromZipAt: url)
            let candidates = importCandidates(sections: sections)
            guard !candidates.isEmpty else {
                errorMessage = "No quiz questions were found in \(url.lastPathComponent)."
                return
            }

            let quizzes = sections.filter { $0.kind == .assessment }.count
            let banks = sections.filter { $0.kind == .questionBank }.count
            importPickerContext = ImportPickerContext(
                title: "Import from Common Cartridge",
                sourceDescription: "From \(url.lastPathComponent) — \(sectionSummary(quizzes: quizzes, banks: banks)). Choose which questions to import.",
                candidates: candidates,
                confirmVerb: "Import",
                importedTitle: nil,
                actionName: "Import Common Cartridge",
                onConfirm: { selected, title, action in commitImport(selected, importedTitle: title, actionName: action) }
            )
        } catch {
            errorMessage = "Common Cartridge import failed: \(error.localizedDescription)"
        }
    }

    private func importCandidates(sections: [QTISection]) -> [ImportCandidate] {
        let merger = QuizMerger()
        let existingKeys = Set(quiz.questions.map(merger.duplicateKey(for:)))
        return sections.flatMap { section in
            let prefix = section.kind == .questionBank ? "Bank" : "Quiz"
            return section.questions.map { question in
                ImportCandidate(
                    question: question,
                    isDuplicate: existingKeys.contains(merger.duplicateKey(for: question)),
                    sourceLabel: "\(prefix): \(section.title)"
                )
            }
        }
    }

    private func sectionSummary(quizzes: Int, banks: Int) -> String {
        var parts: [String] = []
        if quizzes > 0 { parts.append("\(quizzes) quiz\(quizzes == 1 ? "" : "zes")") }
        if banks > 0 { parts.append("\(banks) item bank\(banks == 1 ? "" : "s")") }
        return parts.isEmpty ? "no sections" : parts.joined(separator: ", ")
    }

    private func commitImport(_ questions: [QuizQuestion], importedTitle: String?, actionName: String) {
        guard !questions.isEmpty else { return }
        let merger = QuizMerger()
        let fresh = questions.map { merger.withFreshIDs($0) }
        var updated = quiz
        if updated.questions.isEmpty, isDefaultTitle(updated.title), let importedTitle, !importedTitle.isEmpty {
            updated.title = importedTitle
        }
        updated.questions.append(contentsOf: fresh)
        mutateQuiz(to: updated, actionName: actionName)
        selectedQuestionID = fresh.first?.id ?? selectedQuestionID
    }

    private func isDefaultTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "Untitled Quiz"
    }

    private func exportPaperExam(_ options: PaperExamOptions) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        let base = (defaultExportFilename as NSString).deletingPathExtension
        panel.nameFieldStringValue = base + (options.includeAnswerKey ? "-answer-key.html" : "-exam.html")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let document = PaperExamBuilder().document(for: quiz, options: options)
            try document.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Paper exam export failed: \(error.localizedDescription)"
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

        // Validate the package (well-formed XML, manifest consistency, and a
        // re-import round-trip). Clean packages export straight away; otherwise the
        // findings are shown first so the user can fix them or proceed anyway.
        let validationIssues = QTIValidator().validateExport(of: quiz, engine: engine)
        if validationIssues.isEmpty {
            finishExport(engine: engine)
        } else {
            qtiValidation = QTIValidationContext(engine: engine, issues: validationIssues)
        }
    }

    private func finishExport(engine: CanvasQuizEngine) {
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
    let lintFindings: [UUID: [LintFinding]]
    let onAddQuestion: () -> Void
    let onImportMarkedText: () -> Void
    let onImportQTI: (Bool) -> Void
    let onDuplicate: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let onMove: (IndexSet, Int) -> Void
    let onNudge: (UUID, Int) -> Void
    let onOpenBank: () -> Void
    let onMergeFromFile: () -> Void
    let onImportCommonCartridge: () -> Void

    @State private var searchText = ""
    @State private var difficultyFilter: QuizDifficulty?
    @State private var tagFilter: String?

    private let html = HTMLUtilities()

    /// Questions matching the active search + filters, keeping their 1-based numbers.
    private var visibleQuestions: [(number: Int, question: QuizQuestion)] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return quiz.questions.enumerated().compactMap { index, question in
            if let difficultyFilter, question.difficulty != difficultyFilter { return nil }
            if let tagFilter, !question.tags.contains(where: { $0.caseInsensitiveCompare(tagFilter) == .orderedSame }) {
                return nil
            }
            if !needle.isEmpty {
                let haystack = (html.plainText(fromHTML: question.prompt) + " "
                    + question.type.displayName + " "
                    + question.tags.joined(separator: " ")).lowercased()
                if !haystack.contains(needle) { return nil }
            }
            return (index + 1, question)
        }
    }

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || difficultyFilter != nil || tagFilter != nil
    }

    private var hasFilterableMetadata: Bool {
        !quiz.allTags.isEmpty || quiz.questions.contains { $0.difficulty != nil }
    }

    var body: some View {
        List(selection: $selectedQuestionID) {
            Section("Quiz Title") {
                TextField("Quiz title", text: $quiz.title)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Quiz title")
            }

            Section("Questions") {
                if visibleQuestions.isEmpty {
                    Text(isFiltering ? "No questions match the filter." : "No questions yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if isFiltering {
                    // Drag reorder is disabled while filtered (row order ≠ quiz order).
                    ForEach(visibleQuestions, id: \.question.id) { entry in
                        questionRow(number: entry.number, question: entry.question)
                    }
                } else {
                    ForEach(visibleQuestions, id: \.question.id) { entry in
                        questionRow(number: entry.number, question: entry.question)
                    }
                    .onMove(perform: onMove)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Quiz")
        .safeAreaInset(edge: .top) { searchBar }
        .safeAreaInset(edge: .bottom) { bottomBar }
    }

    private func questionRow(number: Int, question: QuizQuestion) -> some View {
        SidebarQuestionRow(number: number, question: question, findings: lintFindings[question.id] ?? [])
            .tag(question.id)
            .contextMenu {
                Button("Duplicate Question") { onDuplicate(question.id) }
                Divider()
                Button("Move Up") { onNudge(question.id, -1) }
                    .disabled(number <= 1)
                Button("Move Down") { onNudge(question.id, 1) }
                    .disabled(number >= quiz.questions.count)
                Divider()
                Button("Delete Question", role: .destructive) { onDelete(question.id) }
            }
    }

    private var searchBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Filter questions", text: $searchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Filter questions")
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear filter")
                }
            }
            .padding(6)
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))

            if hasFilterableMetadata {
                HStack(spacing: 8) {
                    filterMenu
                    if isFiltering {
                        Button("Clear") {
                            searchText = ""
                            difficultyFilter = nil
                            tagFilter = nil
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var filterMenu: some View {
        Menu {
            Picker("Difficulty", selection: $difficultyFilter) {
                Text("Any Difficulty").tag(QuizDifficulty?.none)
                ForEach(QuizDifficulty.allCases) { difficulty in
                    Text(difficulty.displayName).tag(QuizDifficulty?.some(difficulty))
                }
            }
            if !quiz.allTags.isEmpty {
                Picker("Tag", selection: $tagFilter) {
                    Text("Any Tag").tag(String?.none)
                    ForEach(quiz.allTags, id: \.self) { tag in
                        Text(tag).tag(String?.some(tag))
                    }
                }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.button)
        .controlSize(.small)
        .fixedSize()
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Button(action: onAddQuestion) {
                Label("Add Question", systemImage: "plus")
            }
            .labelStyle(.iconOnly)
            .help("Add a new question (⇧⌘N)")

            // Icon-only menu with no fixed width so the bar reflows at any sidebar
            // width instead of being clipped.
            Menu {
                Button("Marked Text…", action: onImportMarkedText)
                Button("QTI Zip — Keep Formatting…") { onImportQTI(true) }
                Button("QTI Zip — Plain Text…") { onImportQTI(false) }
                Button("Common Cartridge (.imscc)…", action: onImportCommonCartridge)
                Divider()
                Button("Merge from File…", action: onMergeFromFile)
                Button("Question Bank…", action: onOpenBank)
            } label: {
                Label("Add Content", systemImage: "tray.and.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .labelStyle(.iconOnly)
            .help("Import, merge, or add questions from the bank")

            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct SidebarQuestionRow: View {
    let number: Int
    let question: QuizQuestion
    var findings: [LintFinding] = []

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
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(question.type.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let difficulty = question.difficulty {
                        Text(difficulty.displayName)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(.capsule)
                    }
                }
            }
            Spacer(minLength: 0)
            LintBadge(findings: findings)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var label = "Question \(number), \(question.type.displayName)"
        if let difficulty = question.difficulty { label += ", \(difficulty.displayName)" }
        label += ": \(plainPrompt)"
        if !findings.isEmpty {
            let warnings = findings.filter { $0.severity == .warning }.count
            label += warnings > 0 ? ". \(warnings) warning\(warnings == 1 ? "" : "s")" : ". \(findings.count) suggestion\(findings.count == 1 ? "" : "s")"
        }
        return label
    }
}

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
                    .buttonStyle(.glassProminent)
                    .fixedSize()
                    .help("Review this question for item-writing quality and apply suggested edits")

                    Menu {
                        Button("Generate Distractors") { generateDistractors() }
                            .disabled(!canGenerateDistractors)
                        Button("Generate Feedback") { generateFeedback() }
                    } label: {
                        if isGenerating {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("AI Tools", systemImage: "wand.and.stars")
                        }
                    }
                    .menuIndicator(.hidden)
                    .disabled(isGenerating)
                    .fixedSize()
                    .help("Generate distractors or feedback for this question with AI")

                    Button(role: .destructive, action: onDelete) {
                        Label("Delete Question", systemImage: "trash")
                    }
                    .labelStyle(.iconOnly)
                    .help("Delete this question")
                }

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
        runGeneration(system: service.systemInstruction(persona: persona), user: prompt, temperature: persona.aiProfile.temperatureOverride ?? 0.7) { raw in
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
        runGeneration(system: service.systemInstruction(persona: persona), user: prompt, temperature: persona.aiProfile.temperatureOverride ?? 0.4) { raw in
            guard let feedback = service.parseFeedback(raw) else {
                generationError = "No feedback was returned."
                return
            }
            applyEdit { $0.feedback = feedback }
            isFeedbackExpanded = true
        }
    }

    private func runGeneration(system: String, user: String, temperature: Double, apply: @escaping (String) -> Void) {
        generationError = nil
        guard runner.supportsAutoRun else {
            generationError = "Switch to the API or Apple Foundation Models provider to generate here, or use Author with AI for copy/paste."
            return
        }
        isGenerating = true
        let runner = self.runner
        Task {
            do {
                let raw = try await runner.run(system: system, user: user, temperature: temperature)
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

        Task {
            do {
                let raw = try await runReviewPrompt(systemInstruction: systemInstruction, userPrompt: prompt, temperature: temperature)
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

    private func runReviewPrompt(systemInstruction: String, userPrompt: String, temperature: Double) async throws -> String {
        switch provider {
        case .openAICompatible:
            let endpointURL = URL(string: endpoint) ?? URL(string: "https://api.openai.com/v1/chat/completions")!
            let configuration = AIConfiguration(apiKey: apiKey, endpoint: endpointURL, model: model)
            return try await AIClient().complete(systemInstruction: systemInstruction, userPrompt: userPrompt, configuration: configuration, temperature: temperature)
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
    /// Drives the paginated, applyable whole-quiz review sheet.
    @State private var isQuizReviewPresented = false
    /// A parsed item review, shown in the formatted diff sheet with per-field Apply.
    @State private var reviewPresentation: ReviewPresentation?
    /// The selected question as it was when its review started — the diff "before".
    @State private var reviewOriginal: QuizQuestion?
    @State private var status: PanelStatus?

    private var isRunning: Bool { runningAction != nil }

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
                Label("Results open in a window you can read, copy, or save.", systemImage: "rectangle.portrait.and.arrow.right")
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
        .sheet(isPresented: $isQuizReviewPresented) {
            QuizReviewSheet(quizTitle: quizTitle, questions: $quiz.questions, loadBatch: makeReviewBatchLoader())
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
        // The whole-quiz review uses the paginated, applyable sheet for the
        // auto-run providers; copy-paste still copies a single prompt.
        if feature == .review, provider != .copyPaste {
            if provider == .openAICompatible, URL(string: endpoint) == nil {
                status = PanelStatus(text: "Enter a valid endpoint URL.", isError: true)
                return
            }
            isQuizReviewPresented = true
            return
        }
        switch provider {
        case .openAICompatible: runQuizAPI(feature)
        case .copyPaste: copyQuizPrompt(feature)
        case .foundationModels: runFoundationModelsQuiz(feature)
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
        return { questions in
            let contexts = questions.map { quiz.promptLinkContext(for: $0, frameworks: frameworks) }
            let prompt = service.makeBatchPrompt(questions: questions, quizTitle: quizTitle, persona: persona, contexts: contexts)
            let raw: String
            switch provider {
            case .foundationModels:
                raw = await FoundationModelsRunner.run(prompt: systemInstruction + "\n\n" + prompt)
            default:
                guard let url = URL(string: endpoint) else { throw URLError(.badURL) }
                let configuration = AIConfiguration(apiKey: apiKey, endpoint: url, model: model)
                raw = try await AIClient().complete(
                    systemInstruction: systemInstruction,
                    userPrompt: prompt,
                    configuration: configuration,
                    temperature: temperature
                )
            }
            return service.parseBatch(raw, originals: questions)
        }
    }

    private func runQuizAPI(_ feature: AIFeature) {
        guard let endpointURL = URL(string: endpoint) else {
            status = PanelStatus(text: "Enter a valid endpoint URL.", isError: true)
            return
        }
        runningAction = quizActionID(feature)
        status = nil
        let configuration = AIConfiguration(apiKey: apiKey, endpoint: endpointURL, model: model)
        let instruction = self.instruction
        let quiz = self.quiz
        Task {
            do {
                let result = try await AIClient().run(feature: feature, quiz: quiz, instruction: instruction, configuration: configuration)
                await MainActor.run {
                    runningAction = nil
                    presentResult(result, title: feature.displayName)
                }
            } catch {
                await MainActor.run {
                    runningAction = nil
                    status = PanelStatus(text: "AI request failed: \(error)", isError: true)
                }
            }
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

    /// Runs a quiz-level feature on Apple's on-device model, paging the quiz into
    /// batches that fit the token limit and stitching the replies into one document.
    private func runFoundationModelsQuiz(_ feature: AIFeature) {
        runningAction = quizActionID(feature)
        status = nil
        let batches = quiz.batched(maxCharacters: FoundationModelsRunner.inputCharacterBudget)
        let instruction = self.instruction
        Task {
            var sections: [String] = []
            var startNumber = 1
            for (index, batch) in batches.enumerated() {
                if batches.count > 1 {
                    await MainActor.run {
                        status = PanelStatus(text: "Processing batch \(index + 1) of \(batches.count)\u{2026}", isError: false)
                    }
                }
                let prompt = AIPromptBuilder().makePrompt(feature: feature, quiz: batch, userInstruction: instruction)
                let reply = await FoundationModelsRunner.run(prompt: prompt)
                let endNumber = startNumber + batch.questions.count - 1
                if batches.count > 1 {
                    sections.append("## Questions \(startNumber)\u{2013}\(endNumber)\n\n\(reply)")
                } else {
                    sections.append(reply)
                }
                startNumber = endNumber + 1
            }
            let combined = sections.joined(separator: "\n\n")
            await MainActor.run {
                runningAction = nil
                status = batches.count > 1
                    ? PanelStatus(text: "Combined \(batches.count) batches into one document.", isError: false)
                    : nil
                presentResult(combined, title: feature.displayName)
            }
        }
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
        Task {
            do {
                let raw = try await runner.run(system: system, user: prompt)
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
        runItemGeneration(system: service.systemInstruction(persona: persona), user: prompt, temperature: persona.aiProfile.temperatureOverride ?? 0.7, id: "item-distractors") { raw in
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
        runItemGeneration(system: service.systemInstruction(persona: persona), user: prompt, temperature: persona.aiProfile.temperatureOverride ?? 0.4, id: "item-feedback") { raw in
            guard let feedback = service.parseFeedback(raw) else {
                status = PanelStatus(text: "No feedback was returned.", isError: true)
                return
            }
            binding.wrappedValue.feedback = feedback
            status = PanelStatus(text: "Feedback added to this question.", isError: false)
        }
    }

    private func runItemGeneration(system: String, user: String, temperature: Double, id: String, apply: @escaping (String) -> Void) {
        guard runner.supportsAutoRun else {
            status = PanelStatus(text: "Switch to the API or Apple Foundation Models provider to generate here, or use Author with AI for copy and paste.", isError: true)
            return
        }
        runningAction = id
        status = nil
        let runner = self.runner
        Task {
            do {
                let raw = try await runner.run(system: system, user: user, temperature: temperature)
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


enum FoundationModelsRunner {
    /// Apple Foundation Models cap a request at roughly 4096 tokens shared between
    /// the prompt and the reply. Estimating about four characters per token, this
    /// budget keeps a batch of quiz text near 1000 tokens so there is ample room
    /// left for the model's response. Quiz-level tools page the quiz into batches
    /// of this size; see `Quiz.batched(maxCharacters:)`.
    static let inputCharacterBudget = 4000

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
    /// Optional grey prompt shown only while the field is empty. It is not part of
    /// the text, so it can never be submitted or imported by mistake.
    var placeholder: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
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

                // Drawn on top so it shows over the editor's opaque background;
                // hit testing is disabled so clicks fall through to the editor.
                if let placeholder, text.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
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
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        // Floating Liquid Glass control cluster over the editor content.
        .glassEffect(.regular.interactive(), in: .capsule)
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
