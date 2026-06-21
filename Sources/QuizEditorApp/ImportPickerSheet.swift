import SwiftUI
import QuizEditorCore

/// One question offered for import, with a stable picker identity and a flag for
/// whether it duplicates a question already in the open quiz.
struct ImportCandidate: Identifiable {
    let id = UUID()
    let question: QuizQuestion
    var isDuplicate: Bool = false
}

/// A reusable picker shown before import or merge: choose exactly which parsed
/// questions to bring in, with select-all/none, live search, and a per-question
/// preview. Duplicates are flagged and unchecked by default.
struct ImportPickerSheet: View {
    let title: String
    let sourceDescription: String
    let candidates: [ImportCandidate]
    let confirmVerb: String
    let onConfirm: ([QuizQuestion]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<UUID>
    @State private var search = ""
    private let html = HTMLUtilities()

    init(
        title: String,
        sourceDescription: String,
        candidates: [ImportCandidate],
        confirmVerb: String = "Import",
        onConfirm: @escaping ([QuizQuestion]) -> Void
    ) {
        self.title = title
        self.sourceDescription = sourceDescription
        self.candidates = candidates
        self.confirmVerb = confirmVerb
        self.onConfirm = onConfirm
        // Pre-check everything that isn't a duplicate.
        _selectedIDs = State(initialValue: Set(candidates.filter { !$0.isDuplicate }.map(\.id)))
    }

    private var filtered: [ImportCandidate] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return candidates }
        return candidates.filter {
            html.plainText(fromHTML: $0.question.prompt).lowercased().contains(needle)
                || $0.question.type.displayName.lowercased().contains(needle)
        }
    }

    private var hasDuplicates: Bool { candidates.contains(where: \.isDuplicate) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.bold())
                Text(sourceDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            Divider()

            HStack(spacing: 12) {
                Button("Select All") { selectedIDs = Set(filtered.map(\.id)) }
                Button("Select None") { selectedIDs.subtract(filtered.map(\.id)) }
                if hasDuplicates {
                    Button("Only New") {
                        selectedIDs = Set(candidates.filter { !$0.isDuplicate }.map(\.id))
                    }
                    .help("Select only questions that aren't already in this quiz")
                }
                Spacer()
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Filter", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .accessibilityLabel("Filter questions")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()

            List {
                ForEach(filtered) { candidate in
                    ImportCandidateRow(
                        candidate: candidate,
                        isSelected: selectedIDs.contains(candidate.id),
                        plainPrompt: plainPrompt(candidate.question)
                    ) { isOn in
                        if isOn { selectedIDs.insert(candidate.id) } else { selectedIDs.remove(candidate.id) }
                    }
                }
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Text("\(selectedIDs.count) of \(candidates.count) selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("\(confirmVerb) \(selectedIDs.count)") {
                    let chosen = candidates.filter { selectedIDs.contains($0.id) }.map(\.question)
                    onConfirm(chosen)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedIDs.isEmpty)
            }
            .padding(20)
        }
        .frame(minWidth: 620, minHeight: 560)
    }

    private func plainPrompt(_ question: QuizQuestion) -> String {
        let text = html.plainText(fromHTML: question.prompt)
        return text.isEmpty ? "Untitled question" : text
    }
}

private struct ImportCandidateRow: View {
    let candidate: ImportCandidate
    let isSelected: Bool
    let plainPrompt: String
    let onToggle: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isSelected }, set: { onToggle($0) })) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(plainPrompt)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text(candidate.question.type.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if candidate.isDuplicate {
                            Text("Already in quiz")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.18))
                                .clipShape(.capsule)
                        }
                    }
                }
                Spacer()
            }
        }
        .toggleStyle(.checkbox)
        .accessibilityLabel("\(plainPrompt), \(candidate.question.type.displayName)\(candidate.isDuplicate ? ", already in quiz" : "")")
    }
}
