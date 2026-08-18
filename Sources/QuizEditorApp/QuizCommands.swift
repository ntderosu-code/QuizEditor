import SwiftUI
import QuizEditorCore

/// Actions the focused document exposes to menu-bar commands. Selection lives in
/// `ContentView` state, so the Question menu reaches it through a focused value
/// rather than owning it directly.
struct QuizCommandActions {
    var hasSelection: Bool
    var canSelectPrevious: Bool
    var canSelectNext: Bool
    var canMoveUp: Bool
    var canMoveDown: Bool

    var addQuestion: () -> Void
    var selectPrevious: () -> Void
    var selectNext: () -> Void
    var selectFirst: () -> Void
    var selectLast: () -> Void
    var moveUp: () -> Void
    var moveDown: () -> Void
    var duplicate: () -> Void
    var delete: () -> Void
    var showQuickSwitch: () -> Void
}

struct QuizCommandActionsKey: FocusedValueKey {
    typealias Value = QuizCommandActions
}

extension FocusedValues {
    var quizCommandActions: QuizCommandActions? {
        get { self[QuizCommandActionsKey.self] }
        set { self[QuizCommandActionsKey.self] = newValue }
    }
}

/// The "Question" menu: discoverable commands with keyboard shortcuts for
/// navigating, reordering, and duplicating questions.
struct QuestionCommands: Commands {
    @FocusedValue(\.quizCommandActions) private var actions

    var body: some Commands {
        CommandMenu("Question") {
            Button("Add Question") { actions?.addQuestion() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(actions == nil)

            Divider()

            Button("Next Question") { actions?.selectNext() }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(!(actions?.canSelectNext ?? false))
            Button("Previous Question") { actions?.selectPrevious() }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(!(actions?.canSelectPrevious ?? false))
            // ⌘ Home/End, not bare Home/End: a menu key equivalent is matched
            // before the responder chain sees the key, so the unmodified form
            // stole Home/End from every text field in the app.
            Button("First Question") { actions?.selectFirst() }
                .keyboardShortcut(.home, modifiers: .command)
                .disabled(!(actions?.hasSelection ?? false))
            Button("Last Question") { actions?.selectLast() }
                .keyboardShortcut(.end, modifiers: .command)
                .disabled(!(actions?.hasSelection ?? false))
            Button("Go to Question…") { actions?.showQuickSwitch() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(actions == nil)

            Divider()

            Button("Move Question Up") { actions?.moveUp() }
                .keyboardShortcut(.upArrow, modifiers: [.command, .control])
                .disabled(!(actions?.canMoveUp ?? false))
            Button("Move Question Down") { actions?.moveDown() }
                .keyboardShortcut(.downArrow, modifiers: [.command, .control])
                .disabled(!(actions?.canMoveDown ?? false))
            Button("Duplicate Question") { actions?.duplicate() }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(!(actions?.hasSelection ?? false))
            Button("Delete Question") { actions?.delete() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!(actions?.hasSelection ?? false))
        }
    }
}

/// Document-level actions the menu bar needs. These all live in `ContentView`
/// state (sheet flags, importer flags, the inspector toggle), so the menu bar
/// reaches them through a focused value the same way the Question menu does.
struct QuizDocumentActions {
    var isAIPanelVisible: Bool
    var hasQuestions: Bool

    var exportQTIPackage: (CanvasQuizEngine) -> Void
    var exportFormattedDocument: () -> Void
    var exportPaperExam: () -> Void

    var importMarkedText: () -> Void
    /// `true` keeps the source formatting; `false` imports plain text.
    var importQTIPackage: (Bool) -> Void
    var importCommonCartridge: () -> Void
    var mergeFromFile: () -> Void
    var openQuestionBank: () -> Void

    var showPreview: () -> Void
    var checkQuiz: () -> Void
    var showCoverageReport: () -> Void
    var manageFrameworks: () -> Void
    var manageReviewProfiles: () -> Void

    var toggleAIPanel: () -> Void
    var focusFilterField: () -> Void
}

struct QuizDocumentActionsKey: FocusedValueKey {
    typealias Value = QuizDocumentActions
}

extension FocusedValues {
    var quizDocumentActions: QuizDocumentActions? {
        get { self[QuizDocumentActionsKey.self] }
        set { self[QuizDocumentActionsKey.self] = newValue }
    }
}

/// Puts the document's own commands in the menu bar: File ▸ Import/Export, an
/// Edit ▸ Filter entry, View ▸ panel and preview toggles, and a Quiz menu for
/// the review tools. Every one of these is also reachable from the toolbar; the
/// menu bar is where a Mac user looks for them first, and it is the only place
/// that advertises their keyboard shortcuts.
struct QuizDocumentCommands: Commands {
    @FocusedValue(\.quizDocumentActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .importExport) {
            Menu("Import") {
                Button("Marked Text…") { actions?.importMarkedText() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Divider()
                Section("QTI Package (.zip)") {
                    Button("Keep Formatting…") { actions?.importQTIPackage(true) }
                    Button("Plain Text…") { actions?.importQTIPackage(false) }
                }
                Button("Common Cartridge (.imscc)…") { actions?.importCommonCartridge() }
                Divider()
                Button("Merge from File…") { actions?.mergeFromFile() }
                Button("Question Bank…") { actions?.openQuestionBank() }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
            }
            .disabled(actions == nil)

            Menu("Export") {
                Section("QTI Package") {
                    ForEach(CanvasQuizEngine.allCases) { engine in
                        Button(engine.displayName) { actions?.exportQTIPackage(engine) }
                    }
                }
                Divider()
                Button("Formatted Document (HTML)…") { actions?.exportFormattedDocument() }
                Button("Paper Exam (PDF)…") { actions?.exportPaperExam() }
            }
            .disabled(!(actions?.hasQuestions ?? false))
        }

        // Sits with Find rather than in its own menu: filtering the navigator is
        // what "find" means in this app, and ⌘F is where users reach for it.
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Filter Questions") { actions?.focusFilterField() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(actions == nil)
        }

        CommandGroup(after: .toolbar) {
            Button(actions?.isAIPanelVisible == true ? "Hide AI Suggestions" : "Show AI Suggestions") {
                actions?.toggleAIPanel()
            }
            .keyboardShortcut("a", modifiers: [.command, .option])
            .disabled(actions == nil)

            Button("Preview Quiz…") { actions?.showPreview() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!(actions?.hasQuestions ?? false))

            Divider()
        }

        CommandMenu("Quiz") {
            Button("\(AppCopy.checkQuiz)…") { actions?.checkQuiz() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(!(actions?.hasQuestions ?? false))
            Button("Competency Coverage…") { actions?.showCoverageReport() }
                .keyboardShortcut("k", modifiers: [.command, .option])
                .disabled(!(actions?.hasQuestions ?? false))

            Divider()

            Button("Manage Review Profiles…") { actions?.manageReviewProfiles() }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(actions == nil)
            Button("Manage Frameworks…") { actions?.manageFrameworks() }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(actions == nil)
        }
    }
}
