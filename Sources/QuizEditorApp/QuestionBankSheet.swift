import SwiftUI
import QuizEditorCore

/// Browse and search questions across every `.quizeditor` file in a folder, then
/// add a selection into the open quiz. Source files are only read, never written.
struct QuestionBankSheet: View {
    let onAdd: ([QuizQuestion]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var folderName: String?
    @State private var bank: [BankQuestion] = []
    @State private var isIndexing = false
    @State private var searchText = ""
    @State private var typeFilter: QuizQuestionType?
    @State private var tagFilter: String?
    @State private var selectedIDs: Set<UUID> = []

    private let indexer = QuizBankIndexer()
    private let html = HTMLUtilities()

    private var query: QuizBankIndexer.Query {
        QuizBankIndexer.Query(searchText: searchText, type: typeFilter, tag: tagFilter)
    }

    private var results: [BankQuestion] {
        indexer.filter(bank, with: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            controls
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 680, minHeight: 600)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Question Bank", systemImage: "books.vertical")
                .font(.title2.bold())
            Text(folderName.map { "Indexed folder: \($0)" } ?? "Choose a folder of .quizeditor files to browse questions across all of them.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                chooseFolder()
            } label: {
                Label(folderName == nil ? "Choose Folder…" : "Change Folder…", systemImage: "folder")
            }

            if isIndexing {
                ProgressView().controlSize(.small)
            }

            Spacer()

            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Search questions", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .accessibilityLabel("Search the question bank")

            Menu {
                Picker("Type", selection: $typeFilter) {
                    Text("All Types").tag(QuizQuestionType?.none)
                    ForEach(QuizQuestionType.allCases) { type in
                        Text(type.displayName).tag(QuizQuestionType?.some(type))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(typeFilter?.displayName ?? "All Types", systemImage: "line.3.horizontal.decrease.circle")
            }
            .fixedSize()

            if !indexer.tags(in: bank).isEmpty {
                Menu {
                    Picker("Tag", selection: $tagFilter) {
                        Text("All Tags").tag(String?.none)
                        ForEach(indexer.tags(in: bank), id: \.self) { tag in
                            Text(tag).tag(String?.some(tag))
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(tagFilter ?? "All Tags", systemImage: "tag")
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if bank.isEmpty {
            ContentUnavailableView {
                Label("No folder selected", systemImage: "books.vertical")
            } description: {
                Text("Choose a folder and Quiz Editor will index every .quizeditor file in it.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(results) { item in
                    bankRow(item)
                }
            }
            .listStyle(.inset)
        }
    }

    private func bankRow(_ item: BankQuestion) -> some View {
        Toggle(isOn: Binding(
            get: { selectedIDs.contains(item.id) },
            set: { isOn in if isOn { selectedIDs.insert(item.id) } else { selectedIDs.remove(item.id) } }
        )) {
            VStack(alignment: .leading, spacing: 3) {
                Text(plainPrompt(item.question))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(item.question.type.displayName)
                    Text("·")
                    Text(item.sourceTitle)
                    if let difficulty = item.question.difficulty {
                        Text("·")
                        Text(difficulty.displayName)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .toggleStyle(.checkbox)
        .accessibilityLabel("\(plainPrompt(item.question)), \(item.question.type.displayName), from \(item.sourceTitle)")
    }

    private var footer: some View {
        HStack {
            Text("\(selectedIDs.count) selected · \(results.count) shown · \(bank.count) total")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Add \(selectedIDs.count) to Quiz") {
                let chosen = bank.filter { selectedIDs.contains($0.id) }.map(\.question)
                onAdd(chosen)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(selectedIDs.isEmpty)
        }
        .padding(20)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Index"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        folderName = url.lastPathComponent
        selectedIDs = []
        isIndexing = true
        let indexer = self.indexer
        Task {
            let items = await Task.detached(priority: .userInitiated) {
                indexer.index(folder: url)
            }.value
            await MainActor.run {
                self.bank = items
                self.isIndexing = false
            }
        }
    }

    private func plainPrompt(_ question: QuizQuestion) -> String {
        let text = html.plainText(fromHTML: question.prompt)
        return text.isEmpty ? "Untitled question" : text
    }
}
