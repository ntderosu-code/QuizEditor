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

    /// Cached quiz-wide lint, recomputed only when the quiz or active persona
    /// changes (not on every render — selection, sheet toggles, etc.).
    @State private var lintFindings: [UUID: [LintFinding]] = [:]

    private func recomputeLintFindings() {
        lintFindings = QuestionLinter().findings(for: quiz, persona: activePersona)
    }

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
