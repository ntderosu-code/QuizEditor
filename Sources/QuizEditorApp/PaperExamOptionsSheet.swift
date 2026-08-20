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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Export Paper Exam")
                .font(.title2.bold())
                .padding(20)

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

            HStack {
                Label(
                    includeAnswerKey ? "Exports the instructor answer key." : "Exports the blank student copy.",
                    systemImage: includeAnswerKey ? "key.fill" : "doc.text"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") {
                    onExport(options)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 540, height: 620)
    }
}
