import SwiftUI
import QuizEditorCore

/// One question offered for import, with a stable picker identity and a flag for
/// whether it duplicates a question already in the open quiz.
struct ImportCandidate: Identifiable {
    let id = UUID()
    let question: QuizQuestion
    var isDuplicate: Bool = false
    /// Where this question came from (e.g. "Quiz: Midterm" or "Bank: Cells"),
    /// shown when importing from a multi-section source like a Common Cartridge.
    var sourceLabel: String? = nil
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

    /// A run of candidates sharing one source (a quiz or a bank), in the order
    /// they first appeared. Used to offer per-source select-all.
    private struct CandidateGroup: Identifiable {
        let id: String
        let label: String?
        let candidates: [ImportCandidate]
    }

    /// Show grouped sections only when the import spans more than one source
    /// (e.g. a Common Cartridge with several quizzes/banks). Single-source
    /// imports keep the simpler flat list.
    private var isGrouped: Bool {
        Set(candidates.compactMap(\.sourceLabel)).count > 1
    }

    private var groups: [CandidateGroup] {
        var order: [String] = []
        var buckets: [String: [ImportCandidate]] = [:]
        var labels: [String: String?] = [:]
        for candidate in filtered {
            let key = candidate.sourceLabel ?? "\u{0}ungrouped"
            if buckets[key] == nil {
                order.append(key)
                labels[key] = candidate.sourceLabel
            }
            buckets[key, default: []].append(candidate)
        }
        return order.map { key in
            CandidateGroup(id: key, label: labels[key] ?? nil, candidates: buckets[key] ?? [])
        }
    }

    private func selectedCount(in group: CandidateGroup) -> Int {
        group.candidates.reduce(0) { $0 + (selectedIDs.contains($1.id) ? 1 : 0) }
    }

    private func toggleGroup(_ group: CandidateGroup) {
        let ids = group.candidates.map(\.id)
        if selectedCount(in: group) == ids.count {
            selectedIDs.subtract(ids)
        } else {
            selectedIDs.formUnion(ids)
        }
    }

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
                if isGrouped {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.candidates) { candidate in row(candidate) }
                        } header: {
                            groupHeader(group)
                        }
                    }
                } else {
                    ForEach(filtered) { candidate in row(candidate) }
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

    @ViewBuilder
    private func row(_ candidate: ImportCandidate) -> some View {
        ImportCandidateRow(
            candidate: candidate,
            isSelected: selectedIDs.contains(candidate.id),
            plainPrompt: plainPrompt(candidate.question),
            // Source is already shown in the group header when grouped.
            showsSource: !isGrouped
        ) { isOn in
            if isOn { selectedIDs.insert(candidate.id) } else { selectedIDs.remove(candidate.id) }
        }
    }

    /// A tappable section header that selects or deselects every question from one
    /// quiz or bank, with a tri-state checkbox reflecting the group's state.
    private func groupHeader(_ group: CandidateGroup) -> some View {
        let total = group.candidates.count
        let selected = selectedCount(in: group)
        let symbol = selected == 0 ? "square" : (selected == total ? "checkmark.square.fill" : "minus.square.fill")
        let label = group.label ?? "Other questions"
        return Button {
            toggleGroup(group)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(selected == 0 ? Color.secondary : Color.accentColor)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.headline)
                Spacer()
                Text("\(selected)/\(total)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(selected) of \(total) selected")
        .accessibilityHint(selected == total ? "Deselect all questions in this group" : "Select all questions in this group")
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
    var showsSource: Bool = true
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
                        if showsSource, let source = candidate.sourceLabel {
                            Text("·").font(.caption).foregroundStyle(.secondary)
                            Text(source)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
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
        .accessibilityLabel("\(plainPrompt), \(candidate.question.type.displayName)\(candidate.sourceLabel.map { ", from \($0)" } ?? "")\(candidate.isDuplicate ? ", already in quiz" : "")")
    }
}
