import SwiftUI
import QuizEditorCore

/// Collects options for a printable paper exam, then hands them back so the
/// caller can render and save the HTML.
struct PaperExamOptionsSheet: View {
    let onExport: (PaperExamOptions) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var instructions = "Answer every question. Show your work where appropriate. No outside materials are permitted."
    @State private var versionLabel = ""
    @State private var showPoints = true
    @State private var includeAnswerKey = false

    private var options: PaperExamOptions {
        PaperExamOptions(
            instructions: instructions,
            includeAnswerKey: includeAnswerKey,
            versionLabel: versionLabel,
            showPoints: showPoints
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

                Section("Layout") {
                    TextField("Version or seat label (optional)", text: $versionLabel)
                        .accessibilityLabel("Version or seat label")
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
        .frame(width: 540, height: 480)
    }
}
