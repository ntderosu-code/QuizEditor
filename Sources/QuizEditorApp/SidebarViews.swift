import SwiftUI
import UniformTypeIdentifiers
import AppKit
import WebKit
import QuizEditorCore
#if canImport(FoundationModels)
import FoundationModels
#endif

struct SidebarView: View {
    @Binding var quiz: Quiz
    @Binding var selectedQuestionID: UUID?
    let lintFindings: [UUID: [LintFinding]]
    let onAddQuestion: () -> Void
    let onImportMarkedText: () -> Void
    let onImportQTI: (Bool) -> Void
    let onImportCommonCartridge: () -> Void
    let onMergeFromFile: () -> Void
    let onOpenBank: () -> Void
    let onDuplicate: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let onMove: (IndexSet, Int) -> Void
    let onNudge: (UUID, Int) -> Void

    @State private var searchText = ""
    @State private var difficultyFilter: QuizDifficulty?
    @State private var tagFilter: String?
    @State private var readinessFilter: ReadinessFilter = .all

    private let html = HTMLUtilities()

    /// Deterministic readiness filter for the navigator: everything, only questions
    /// that still need work (draft or needs-work), or only the ready ones.
    enum ReadinessFilter: String, CaseIterable, Identifiable {
        case all, needsWork, ready
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: "All"
            case .needsWork: "Needs work"
            case .ready: "Ready"
            }
        }
    }

    /// Questions matching the active search + filters, keeping their 1-based numbers.
    private var visibleQuestions: [(number: Int, question: QuizQuestion)] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return quiz.questions.enumerated().compactMap { index, question in
            if let difficultyFilter, question.difficulty != difficultyFilter { return nil }
            if let tagFilter, !question.tags.contains(where: { $0.caseInsensitiveCompare(tagFilter) == .orderedSame }) {
                return nil
            }
            switch readinessFilter {
            case .all: break
            case .needsWork: if QuestionReadiness(question: question).status == .ready { return nil }
            case .ready: if QuestionReadiness(question: question).status != .ready { return nil }
            }
            if !needle.isEmpty {
                let haystack = (html.plainText(fromHTML: question.prompt) + " "
                    + question.type.displayName + " "
                    + question.tags.joined(separator: " ")).lowercased()
                if !haystack.contains(needle) { return nil }
            }
            return (index + 1, question)
        }
    }

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || difficultyFilter != nil || tagFilter != nil || readinessFilter != .all
    }

    private var hasFilterableMetadata: Bool {
        !quiz.allTags.isEmpty || quiz.questions.contains { $0.difficulty != nil }
    }

    var body: some View {
        List(selection: $selectedQuestionID) {
            Section("Quiz Title") {
                TextField("Quiz title", text: $quiz.title)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Quiz title")
            }

            Section("Questions") {
                if visibleQuestions.isEmpty {
                    Text(isFiltering ? "No questions match the filter." : "No questions yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if isFiltering {
                    // Drag reorder is disabled while filtered (row order ≠ quiz order).
                    ForEach(visibleQuestions, id: \.question.id) { entry in
                        questionRow(number: entry.number, question: entry.question)
                    }
                } else {
                    ForEach(visibleQuestions, id: \.question.id) { entry in
                        questionRow(number: entry.number, question: entry.question)
                    }
                    .onMove(perform: onMove)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Quiz")
        .safeAreaInset(edge: .top) { searchBar }
        // The sidebar's own controls sit on the toolbar bar above it (Liquid
        // Glass), not in a custom footer.
        .toolbar {
            ToolbarItemGroup {
                Button(action: onAddQuestion) {
                    Label("Add Question", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help("Add a new question (⇧⌘N)")

                Menu {
                    Button("Marked Text…") { onImportMarkedText() }
                        .keyboardShortcut("i", modifiers: [.command, .shift])
                    Divider()
                    Section("QTI Package (.zip)") {
                        Button("Keep Formatting…") { onImportQTI(true) }
                        Button("Plain Text…") { onImportQTI(false) }
                    }
                    Button("Common Cartridge (.imscc)…") { onImportCommonCartridge() }
                    Divider()
                    Button("Merge from File…") { onMergeFromFile() }
                    Button("Question Bank…") { onOpenBank() }
                } label: {
                    Label("Add", systemImage: "square.and.arrow.down")
                }
                .menuIndicator(.hidden)
                .help("Import or add questions: marked text, a QTI .zip, Common Cartridge, a merge, or the question bank")
            }
        }
    }

    private func questionRow(number: Int, question: QuizQuestion) -> some View {
        SidebarQuestionRow(number: number, question: question, findings: lintFindings[question.id] ?? [])
            .tag(question.id)
            .contextMenu {
                Button("Duplicate Question") { onDuplicate(question.id) }
                Divider()
                Button("Move Up") { onNudge(question.id, -1) }
                    .disabled(number <= 1)
                Button("Move Down") { onNudge(question.id, 1) }
                    .disabled(number >= quiz.questions.count)
                Divider()
                Button("Delete Question", role: .destructive) { onDelete(question.id) }
            }
    }

    private var searchBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Filter questions", text: $searchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Filter questions")
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear filter")
                }
            }
            .padding(6)
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))

            HStack(spacing: 8) {
                Picker("Readiness", selection: $readinessFilter) {
                    ForEach(ReadinessFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .accessibilityLabel("Filter by readiness")

                if hasFilterableMetadata {
                    filterMenu
                }

                if isFiltering {
                    Button("Clear") {
                        searchText = ""
                        difficultyFilter = nil
                        tagFilter = nil
                        readinessFilter = .all
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var filterMenu: some View {
        Menu {
            Picker("Difficulty", selection: $difficultyFilter) {
                Text("Any Difficulty").tag(QuizDifficulty?.none)
                ForEach(QuizDifficulty.allCases) { difficulty in
                    Text(difficulty.displayName).tag(QuizDifficulty?.some(difficulty))
                }
            }
            if !quiz.allTags.isEmpty {
                Picker("Tag", selection: $tagFilter) {
                    Text("Any Tag").tag(String?.none)
                    ForEach(quiz.allTags, id: \.self) { tag in
                        Text(tag).tag(String?.some(tag))
                    }
                }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.button)
        .controlSize(.small)
        .fixedSize()
    }
}

struct SidebarQuestionRow: View {
    let number: Int
    let question: QuizQuestion
    var findings: [LintFinding] = []

    private var plainPrompt: String {
        let text = HTMLUtilities().plainText(fromHTML: question.prompt)
        return text.isEmpty ? "Untitled question" : text
    }

    private var status: ReadinessStatus {
        QuestionReadiness(question: question).status
    }

    var body: some View {
        // No manual selection coloring: the enclosing List inverts foreground colors
        // for the selected row automatically, which also adapts to Increase Contrast.
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(plainPrompt)
                    .font(.body)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(question.type.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let difficulty = question.difficulty {
                        Text(difficulty.displayName)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(.capsule)
                    }
                }
            }
            Spacer(minLength: 0)
            // A single readiness dot: filled when the question is ready, hollow when
            // it still needs work. The status is also in the row's accessibility label.
            Image(systemName: status == .ready ? "circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(status == .ready ? Color.accentColor : Color.secondary.opacity(0.5))
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var label = "Question \(number), \(question.type.displayName)"
        if let difficulty = question.difficulty { label += ", \(difficulty.displayName)" }
        label += ", \(status.label)"
        label += ": \(plainPrompt)"
        if !findings.isEmpty {
            let warnings = findings.filter { $0.severity == .warning }.count
            label += warnings > 0 ? ". \(warnings) warning\(warnings == 1 ? "" : "s")" : ". \(findings.count) suggestion\(findings.count == 1 ? "" : "s")"
        }
        return label
    }
}

