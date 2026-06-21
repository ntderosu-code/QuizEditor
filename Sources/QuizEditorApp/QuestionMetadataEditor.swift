import SwiftUI
import QuizEditorCore

/// Edits a question's organizational metadata: points, difficulty, and tags.
struct QuestionMetadataEditor: View {
    @Binding var question: QuizQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 20) {
                LabeledField("Points") {
                    TextField("Points", value: $question.points, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }

                LabeledField("Difficulty") {
                    Picker("Difficulty", selection: $question.difficulty) {
                        Text("Unspecified").tag(QuizDifficulty?.none)
                        ForEach(QuizDifficulty.allCases) { difficulty in
                            Text(difficulty.displayName).tag(QuizDifficulty?.some(difficulty))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                Spacer()
            }

            LabeledField("Tags") {
                TextField("comma, separated, tags", text: tagsBinding)
                    .textFieldStyle(.roundedBorder)
            }

            if !question.tags.isEmpty {
                // Chips reflow to fit the available width.
                FlowLayout(spacing: 6) {
                    ForEach(question.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(.capsule)
                            .accessibilityLabel("Tag: \(tag)")
                    }
                }
            }
        }
    }

    /// Presents `[String]` tags as a comma-separated text field, normalizing on edit.
    private var tagsBinding: Binding<String> {
        Binding(
            get: { question.tags.joined(separator: ", ") },
            set: { newValue in
                var seenKeys: Set<String> = []
                var tags: [String] = []
                for piece in newValue.split(separator: ",") {
                    let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
                    let key = trimmed.lowercased()
                    if !trimmed.isEmpty, !seenKeys.contains(key) {
                        seenKeys.insert(key)
                        tags.append(trimmed)
                    }
                }
                question.tags = tags
            }
        )
    }
}

/// A simple wrapping (flow) layout, used for tag chips and filter chips so they
/// reflow to the available width instead of clipping.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentRowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let widthWithSpacing = (currentRowWidth == 0 ? size.width : currentRowWidth + spacing + size.width)
            if widthWithSpacing > maxWidth, currentRowWidth > 0 {
                totalHeight += rowHeight + spacing
                currentRowWidth = size.width
                rowHeight = size.height
            } else {
                currentRowWidth = widthWithSpacing
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth == .infinity ? currentRowWidth : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
