import SwiftUI

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
            Button("First Question") { actions?.selectFirst() }
                .keyboardShortcut(.home, modifiers: [])
                .disabled(!(actions?.hasSelection ?? false))
            Button("Last Question") { actions?.selectLast() }
                .keyboardShortcut(.end, modifiers: [])
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
                .disabled(!(actions?.hasSelection ?? false))
        }
    }
}
