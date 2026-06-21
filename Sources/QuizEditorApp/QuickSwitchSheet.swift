import SwiftUI
import QuizEditorCore

/// A quick-open palette: type to filter questions, press Return to jump to the
/// top match, or click any result.
struct QuickSwitchSheet: View {
    let quiz: Quiz
    let onSelect: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @FocusState private var searchFocused: Bool
    private let html = HTMLUtilities()

    private var matches: [(number: Int, question: QuizQuestion)] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return quiz.questions.enumerated().compactMap { index, question in
            guard !needle.isEmpty else { return (index + 1, question) }
            let prompt = html.plainText(fromHTML: question.prompt).lowercased()
            let matchesText = prompt.contains(needle)
                || question.type.displayName.lowercased().contains(needle)
                || question.tags.contains { $0.lowercased().contains(needle) }
            return matchesText ? (index + 1, question) : nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Jump to question…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                    .onSubmit(selectFirstMatch)
                    .accessibilityLabel("Jump to question")
            }
            .padding(16)

            Divider()

            if matches.isEmpty {
                Text("No matching questions")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(matches, id: \.question.id) { entry in
                            Button {
                                onSelect(entry.question.id)
                                dismiss()
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(entry.number).")
                                        .font(.body.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(plainPrompt(entry.question))
                                            .lineLimit(1)
                                        Text(entry.question.type.displayName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 460)
        .onAppear { searchFocused = true }
    }

    private func selectFirstMatch() {
        guard let first = matches.first else { return }
        onSelect(first.question.id)
        dismiss()
    }

    private func plainPrompt(_ question: QuizQuestion) -> String {
        let text = html.plainText(fromHTML: question.prompt)
        return text.isEmpty ? "Untitled question" : text
    }
}
