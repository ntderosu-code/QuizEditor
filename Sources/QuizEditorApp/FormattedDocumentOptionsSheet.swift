import SwiftUI
import QuizEditorCore

/// Collects question selection options for the formatted HTML document, then
/// hands them back so the caller can render and save the file.
struct FormattedDocumentOptionsSheet: View {
    let totalQuestions: Int
    let onExport: (ExamSelection) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var shuffleQuestions = false
    @State private var questionCount: Int
    @State private var versionLabel = ""

    init(totalQuestions: Int, onExport: @escaping (ExamSelection) -> Void) {
        self.totalQuestions = totalQuestions
        self.onExport = onExport
        _questionCount = State(initialValue: max(totalQuestions, 1))
    }

    private var selection: ExamSelection {
        ExamSelection(
            shuffleQuestions: shuffleQuestions,
            questionCount: questionCount,
            seedLabel: versionLabel
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader("Export Formatted Document", systemImage: "doc.richtext")

            Divider()

            Form {
                ExamSelectionSection(
                    totalQuestions: totalQuestions,
                    shuffleQuestions: $shuffleQuestions,
                    questionCount: $questionCount,
                    versionLabel: $versionLabel
                )
            }
            .formStyle(.grouped)

            Divider()

            sheetFooter(confirmTitle: "Export…") {
                onExport(selection)
                dismiss()
            } onCancel: { dismiss() }
        }
        // A minimum, not a fixed size: see PaperExamOptionsSheet.
        .frame(minWidth: 540, minHeight: 380)
    }
}
