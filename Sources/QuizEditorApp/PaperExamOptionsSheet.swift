import SwiftUI
import QuizEditorCore

/// Collects options for a printable paper exam, then hands them back so the
/// caller can render and save the PDF.
struct PaperExamOptionsSheet: View {
    let totalQuestions: Int
    let onExport: (PaperExamOptions) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var instructions = "Answer every question. Show your work where appropriate. No outside materials are permitted."
    @State private var versionLabel = ""
    @State private var showPoints = true
    @State private var includeAnswerKey = false
    @State private var shuffleQuestions = false
    @State private var questionCount: Int

    init(totalQuestions: Int, onExport: @escaping (PaperExamOptions) -> Void) {
        self.totalQuestions = totalQuestions
        self.onExport = onExport
        _questionCount = State(initialValue: max(totalQuestions, 1))
    }

    private var options: PaperExamOptions {
        PaperExamOptions(
            instructions: instructions,
            includeAnswerKey: includeAnswerKey,
            versionLabel: versionLabel,
            showPoints: showPoints,
            shuffleQuestions: shuffleQuestions,
            questionCount: questionCount
        )
    }

    /// Describes what the Export button is actually about to produce. It has to
    /// name the selection too: "the blank student copy" reads as the whole quiz
    /// in authored order, which stops being true as soon as a subset or a
    /// shuffle is chosen.
    private var exportSummary: String {
        var summary = includeAnswerKey ? "Exports the instructor answer key" : "Exports the blank student copy"
        if questionCount < totalQuestions {
            summary += ", \(questionCount) of \(totalQuestions) questions"
        }
        summary += shuffleQuestions ? ", in random order." : "."
        return summary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader("Export Paper Exam", systemImage: "doc.text")

            Divider()

            Form {
                Section("Instructions") {
                    TextEditor(text: $instructions)
                        .frame(minHeight: 80)
                        .font(.body)
                        .accessibilityLabel("Exam instructions")
                }

                ExamSelectionSection(
                    totalQuestions: totalQuestions,
                    seedNote: """
                    The version label seeds the shuffle: the same label always \
                    produces the same exam, so an answer key exported later \
                    matches the copy students received. A different label \
                    produces a different exam.
                    """,
                    shuffleQuestions: $shuffleQuestions,
                    questionCount: $questionCount,
                    versionLabel: $versionLabel
                )

                Section("Layout") {
                    Toggle("Show point values", isOn: $showPoints)
                    Toggle("Instructor answer key (shows correct answers and feedback)", isOn: $includeAnswerKey)
                }
            }
            .formStyle(.grouped)

            Divider()

            sheetFooter(confirmTitle: "Export…") {
                Label(exportSummary, systemImage: includeAnswerKey ? "key.fill" : "doc.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } onConfirm: {
                onExport(options)
                dismiss()
            } onCancel: { dismiss() }
        }
        // A minimum, not a fixed size, so the sheet grows with its content the
        // way every other sheet here does: the seeding explanation appears when
        // randomizing is switched on, and a fixed height clipped the row below it.
        .frame(minWidth: 540, minHeight: 620)
    }
}
