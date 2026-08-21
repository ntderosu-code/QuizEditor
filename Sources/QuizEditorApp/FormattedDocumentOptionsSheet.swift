import SwiftUI
import QuizEditorCore

/// Collects question selection options for the formatted HTML document, then
/// hands them back so the caller can render and save the file.
struct FormattedDocumentOptionsSheet: View {
    let totalQuestions: Int
    let onExport: (FormattedDocumentOptions) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var shuffleQuestions = false
    @State private var questionCount: Int
    @State private var versionLabel = ""

    @State private var includeAnswers = true

    init(totalQuestions: Int, onExport: @escaping (FormattedDocumentOptions) -> Void) {
        self.totalQuestions = totalQuestions
        self.onExport = onExport
        _questionCount = State(initialValue: max(totalQuestions, 1))
    }

    private var options: FormattedDocumentOptions {
        FormattedDocumentOptions(
            includeAnswers: includeAnswers,
            selection: ExamSelection(
                shuffleQuestions: shuffleQuestions,
                questionCount: questionCount,
                seedLabel: versionLabel
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader("Export Formatted Document", systemImage: "doc.richtext")

            Divider()

            Form {
                ExamSelectionSection(
                    totalQuestions: totalQuestions,
                    // No mention of an answer key here: the formatted document
                    // always includes the answers, so there is no separate key
                    // copy to line up with.
                    seedNote: """
                    The version label seeds the shuffle: the same label always \
                    produces the same questions in the same order, so you can \
                    reproduce this exact document later. A different label \
                    produces a different one.
                    """,
                    shuffleQuestions: $shuffleQuestions,
                    questionCount: $questionCount,
                    versionLabel: $versionLabel
                )

                Section("Answers") {
                    Toggle("Include correct answers and feedback", isOn: $includeAnswers)
                }
            }
            .formStyle(.grouped)

            Divider()

            sheetFooter(confirmTitle: "Export…") {
                Label(
                    includeAnswers
                        ? "Exports the instructor copy, with the answers."
                        : "Exports a student copy, with no answers.",
                    systemImage: includeAnswers ? "key.fill" : "doc.text"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } onConfirm: {
                onExport(options)
                dismiss()
            } onCancel: { dismiss() }
        }
        // A minimum, not a fixed size: see PaperExamOptionsSheet.
        .frame(minWidth: 540, minHeight: 380)
    }
}
