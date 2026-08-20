import SwiftUI
import QuizEditorCore

/// The "Questions" controls shared by the paper exam and formatted document
/// export sheets: how many questions to include, and whether to shuffle them.
///
/// The seed label lives in the parent sheet, because the paper exam already has
/// a version label that doubles as the seed while the HTML export needs its own
/// field.
struct ExamSelectionSection: View {
    let totalQuestions: Int
    @Binding var shuffleQuestions: Bool
    @Binding var questionCount: Int

    private var countDescription: String {
        "\(questionCount) of \(totalQuestions) question\(totalQuestions == 1 ? "" : "s")"
    }

    var body: some View {
        Section("Questions") {
            Stepper(value: $questionCount, in: 1...max(totalQuestions, 1)) {
                HStack {
                    Text("Include")
                    Spacer()
                    Text(countDescription)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .accessibilityLabel("Number of questions to include")
            .accessibilityValue(countDescription)

            Toggle("Randomize question order", isOn: $shuffleQuestions)

            if shuffleQuestions {
                Text("The version label seeds the shuffle: the same label always produces the same exam, so an answer key exported later matches the copy students received. A different label produces a different exam.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
