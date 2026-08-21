import SwiftUI
import QuizEditorCore

/// The "Questions" controls shared by the paper exam and formatted document
/// export sheets: how many questions to include, and whether to shuffle them.
///
/// The version label lives here rather than with the other layout controls: it
/// seeds the shuffle, so the explanation of what it does has to sit next to the
/// field it describes.
struct ExamSelectionSection: View {
    let totalQuestions: Int
    /// What reproducing this exact export buys the author. The paper exam has a
    /// separate answer-key copy to match; the formatted document does not.
    let seedNote: String
    @Binding var shuffleQuestions: Bool
    @Binding var questionCount: Int
    @Binding var versionLabel: String

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

            TextField("Version or seat label (optional)", text: $versionLabel)
                .accessibilityLabel("Version or seat label")

            if shuffleQuestions {
                Text(seedNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
