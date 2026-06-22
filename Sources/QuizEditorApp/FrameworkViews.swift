import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuizEditorCore

/// The `.qeframework` document type, matched by filename extension.
private var frameworkFileType: UTType { UTType(filenameExtension: "qeframework") ?? .json }

// MARK: - Management

/// Lists frameworks and lets the user create, fork, edit, delete, import, and
/// export them. Built-ins are read-only; Edit forks them to a user copy.
struct FrameworkManagementSheet: View {
    @ObservedObject var store: FrameworkStore
    @Environment(\.dismiss) private var dismiss

    @State private var editingFramework: Framework?
    @State private var notice: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Frameworks", systemImage: "list.bullet.indent")
                    .font(.title2.bold())
                Spacer()
                Button { importFramework() } label: { Label("Import…", systemImage: "square.and.arrow.down") }
                Button { editingFramework = newFramework() } label: { Label("New", systemImage: "plus") }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Competency and standards frameworks your questions can link to, for coverage reporting. Frameworks are author metadata — local only, never exported.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let notice {
                        Label(notice, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(store.frameworks) { framework in
                        FrameworkRow(
                            framework: framework,
                            onEdit: framework.isBuiltIn ? nil : { editingFramework = framework },
                            onDuplicate: { editingFramework = fork(framework) },
                            onExport: { export(framework) },
                            onDelete: framework.isBuiltIn ? nil : { delete(framework) }
                        )
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 560, minHeight: 560)
        .sheet(item: $editingFramework) { framework in
            FrameworkEditorSheet(framework: framework) { saved in
                store.save(saved)
                notice = "Saved “\(saved.name).”"
            }
        }
    }

    private func newFramework() -> Framework {
        Framework(id: "user.\(UUID().uuidString.lowercased())", name: "New Framework")
    }

    private func fork(_ framework: Framework) -> Framework {
        var copy = framework
        copy.id = "user.\(UUID().uuidString.lowercased())"
        copy.isBuiltIn = false
        copy.name = "\(framework.name) (Copy)"
        return copy
    }

    private func delete(_ framework: Framework) {
        store.delete(framework)
        notice = "Deleted “\(framework.name).”"
    }

    private func export(_ framework: Framework) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [frameworkFileType]
        let safe = framework.name.filter { $0.isLetter || $0.isNumber || $0 == " " }.trimmingCharacters(in: .whitespaces)
        panel.nameFieldStringValue = (safe.isEmpty ? "framework" : safe) + ".qeframework"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(framework) {
            try? data.write(to: url)
            notice = "Exported “\(framework.name).”"
        }
    }

    private func importFramework() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [frameworkFileType, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        do {
            let result = try Framework.importResult(fromJSON: data)
            var framework = result.framework
            if framework.isBuiltIn || store.frameworks.contains(where: { $0.isBuiltIn && $0.id == framework.id }) {
                framework.isBuiltIn = false
                framework.id = "user.\(UUID().uuidString.lowercased())"
            }
            store.save(framework)
            let warning = result.warnings.isEmpty ? "" : " " + result.warnings.joined(separator: " ")
            notice = "Imported “\(framework.name).”" + warning
        } catch {
            notice = "Couldn't import that file — it isn't a valid framework."
        }
    }
}

struct FrameworkRow: View {
    let framework: Framework
    var onEdit: (() -> Void)?
    var onDuplicate: (() -> Void)?
    var onExport: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "list.bullet.indent")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(framework.name).font(.headline)
                    if framework.isBuiltIn {
                        Text("Built-in").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text("\(framework.nodes.count) node\(framework.nodes.count == 1 ? "" : "s")\(framework.source.isEmpty ? "" : " · \(framework.source)")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Menu {
                if let onEdit { Button { onEdit() } label: { Label("Edit", systemImage: "pencil") } }
                if let onDuplicate { Button { onDuplicate() } label: { Label(framework.isBuiltIn ? "Duplicate & Edit" : "Duplicate", systemImage: "doc.on.doc") } }
                if let onExport { Button { onExport() } label: { Label("Export…", systemImage: "square.and.arrow.up") } }
                if let onDelete {
                    Divider()
                    Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Actions for \(framework.name)")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.18)))
    }
}

// MARK: - Editor

struct FrameworkEditorSheet: View {
    @State private var draft: Framework
    let onSave: (Framework) -> Void
    @Environment(\.dismiss) private var dismiss

    init(framework: Framework, onSave: @escaping (Framework) -> Void) {
        _draft = State(initialValue: framework)
        self.onSave = onSave
    }

    private var canSave: Bool { !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader("Edit Framework", systemImage: "list.bullet.indent")
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LabeledField("Name") {
                        TextField("Framework name", text: $draft.name)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack(spacing: 16) {
                        LabeledField("Source") {
                            TextField("e.g. ABET, CSWE EPAS", text: $draft.source)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledField("Version") {
                            TextField("Version", value: $draft.version, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                        }
                    }
                    Divider()
                    FrameworkNodeTreeEditor(nodes: $draft.nodes)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            sheetFooter(canSave: canSave) {
                onSave(draft)
                dismiss()
            } onCancel: { dismiss() }
        }
        .frame(minWidth: 600, minHeight: 600)
    }
}

/// Edits a framework's nodes as an indented tree: add top-level or child nodes,
/// rename code/label, and delete a node with its descendants.
struct FrameworkNodeTreeEditor: View {
    @Binding var nodes: [FrameworkNode]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Nodes").font(.headline)
                Spacer()
                Button { addNode(parentID: nil) } label: { Label("Add top-level node", systemImage: "plus.circle") }
            }
            if nodes.isEmpty {
                Text("No nodes yet. Add a top-level node to start the taxonomy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(ordered(), id: \.node.id) { entry in
                    nodeRow(entry.node, depth: entry.depth)
                }
            }
        }
    }

    @ViewBuilder
    private func nodeRow(_ node: FrameworkNode, depth: Int) -> some View {
        if let index = nodes.firstIndex(where: { $0.id == node.id }) {
            HStack(spacing: 8) {
                Spacer().frame(width: CGFloat(depth) * 18)
                TextField("Code", text: $nodes[index].code)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .accessibilityLabel("Node code")
                TextField("Label", text: $nodes[index].label)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Node label")
                Button { addNode(parentID: node.id) } label: { Image(systemName: "plus.circle") }
                    .buttonStyle(.borderless)
                    .help("Add child node")
                    .accessibilityLabel("Add child of \(node.label)")
                Button(role: .destructive) { remove(node.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete \(node.label) and its children")
            }
        }
    }

    /// Depth-first order with depth tags, so the flat list renders as a tree.
    private func ordered() -> [(node: FrameworkNode, depth: Int)] {
        var result: [(FrameworkNode, Int)] = []
        func visit(parentID: String?, depth: Int) {
            for node in nodes.filter({ $0.parentID == parentID }) {
                result.append((node, depth))
                visit(parentID: node.id, depth: depth + 1)
            }
        }
        visit(parentID: nil, depth: 0)
        return result
    }

    private func addNode(parentID: String?) {
        nodes.append(FrameworkNode(label: "New node", parentID: parentID))
    }

    /// Removes a node and all of its descendants.
    private func remove(_ id: String) {
        var toRemove: Set<String> = [id]
        var changed = true
        while changed {
            changed = false
            for node in nodes where node.parentID.map({ toRemove.contains($0) }) == true && !toRemove.contains(node.id) {
                toRemove.insert(node.id)
                changed = true
            }
        }
        nodes.removeAll { toRemove.contains($0.id) }
    }
}

// MARK: - Competency picker

/// A searchable tree of framework nodes for linking a question to competencies.
struct CompetencyPickerSheet: View {
    let frameworks: [Framework]
    @Binding var competencyIDs: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader("Link Competencies", systemImage: "checklist")
            Divider()
            TextField("Search competencies", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .accessibilityLabel("Search competencies")
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if frameworks.allSatisfy({ $0.nodes.isEmpty }) {
                        Text("No framework nodes yet. Add nodes in Manage Frameworks first.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(frameworks) { framework in
                        let matches = visibleNodes(framework)
                        if !matches.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(framework.name).font(.headline)
                                ForEach(matches, id: \.node.id) { entry in
                                    Toggle(isOn: binding(for: entry.node.id)) {
                                        HStack {
                                            Spacer().frame(width: CGFloat(entry.depth) * 16)
                                            Text(entry.node.displayLabel)
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(minWidth: 520, minHeight: 540)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { competencyIDs.contains(id) },
            set: { isOn in
                if isOn { if !competencyIDs.contains(id) { competencyIDs.append(id) } }
                else { competencyIDs.removeAll { $0 == id } }
            }
        )
    }

    private func visibleNodes(_ framework: Framework) -> [(node: FrameworkNode, depth: Int)] {
        var result: [(node: FrameworkNode, depth: Int)] = []
        func visit(parentID: String?, depth: Int) {
            for node in framework.children(of: parentID) {
                result.append((node: node, depth: depth))
                visit(parentID: node.id, depth: depth + 1)
            }
        }
        visit(parentID: nil, depth: 0)
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return result }
        return result.filter { $0.node.displayLabel.lowercased().contains(query) }
    }
}

// MARK: - Coverage report

/// The quiz-wide coverage/blueprint report: how questions map onto framework
/// nodes, where the gaps are, how many items map to nothing, and the cognitive-
/// level balance. Gaps are conveyed with text and an icon, never color alone.
struct CoverageReportSheet: View {
    let quiz: Quiz
    let frameworks: [Framework]
    @Environment(\.dismiss) private var dismiss

    private var report: CoverageReport { CoverageReport.make(quiz: quiz, frameworks: frameworks) }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader("Competency Coverage", systemImage: "chart.bar.doc.horizontal")
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    let report = report
                    let mapped = report.totalQuestions - report.unmappedQuestionCount
                    Text("\(mapped) of \(report.totalQuestions) question\(report.totalQuestions == 1 ? "" : "s") link a competency. \(report.unmappedQuestionCount) link none.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(frameworks) { framework in
                        let rows = report.nodeCoverage.filter { $0.frameworkID == framework.id }
                        if !rows.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(framework.name).font(.headline)
                                ForEach(rows) { row in
                                    HStack {
                                        if row.questionCount == 0 {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundStyle(.orange)
                                                .accessibilityHidden(true)
                                        } else {
                                            Image(systemName: "checkmark.circle")
                                                .foregroundStyle(.secondary)
                                                .accessibilityHidden(true)
                                        }
                                        Text(row.node.displayLabel)
                                        Spacer()
                                        Text(row.questionCount == 0 ? "Gap — 0 items" : "\(row.questionCount) item\(row.questionCount == 1 ? "" : "s")")
                                            .font(.callout)
                                            .foregroundStyle(row.questionCount == 0 ? .orange : .secondary)
                                    }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel("\(row.node.displayLabel): \(row.questionCount == 0 ? "gap, no items" : "\(row.questionCount) items")")
                                }
                            }
                        }
                    }

                    if !report.cognitiveLevelCounts.isEmpty {
                        Divider()
                        Text("Cognitive level balance").font(.headline)
                        ForEach(CognitiveLevel.allCases) { level in
                            let count = report.cognitiveLevelCounts[level] ?? 0
                            if count > 0 {
                                HStack {
                                    Text(level.displayName)
                                    Spacer()
                                    Text("\(count) item\(count == 1 ? "" : "s")").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(minWidth: 560, minHeight: 560)
    }
}
