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
            Text("Export Formatted Document")
                .font(.title2.bold())
                .padding(20)

            Divider()

            Form {
                ExamSelectionSection(
                    totalQuestions: totalQuestions,
                    shuffleQuestions: $shuffleQuestions,
                    questionCount: $questionCount
                )

                Section("Version") {
                    TextField("Version or seat label (optional)", text: $versionLabel)
                        .accessibilityLabel("Version or seat label")
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") {
                    onExport(selection)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 540, height: 420)
    }
}
