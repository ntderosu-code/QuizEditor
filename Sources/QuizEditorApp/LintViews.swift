import SwiftUI
import QuizEditorCore

/// A compact badge for a sidebar row showing whether the offline linter found
/// anything. Shape *and* color (and a VoiceOver label) convey the severity, so
/// color is never the sole signal.
struct LintBadge: View {
    let findings: [LintFinding]

    private var hasWarning: Bool { findings.contains { $0.severity == .warning } }

    var body: some View {
        if !findings.isEmpty {
            Image(systemName: hasWarning ? "exclamationmark.triangle.fill" : "lightbulb.fill")
                .font(.caption)
                .foregroundStyle(hasWarning ? .orange : .yellow)
                .help(summary)
                .accessibilityLabel(accessibilityText)
        }
    }

    private var summary: String {
        findings.map(\.message).joined(separator: "\n")
    }

    private var accessibilityText: String {
        let noun = hasWarning ? "warning" : "suggestion"
        return "\(findings.count) item-writing \(noun)\(findings.count == 1 ? "" : "s")"
    }
}

/// Inline, non-blocking list of lint findings shown inside the question editor.
struct LintFindingsSection: View {
    let findings: [LintFinding]

    var body: some View {
        if !findings.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(findings) { finding in
                        LintFindingRow(finding: finding)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Item-writing checks", systemImage: "checklist")
            }
        }
    }
}

struct LintFindingRow: View {
    let finding: LintFinding

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: finding.severity == .warning ? "exclamationmark.triangle.fill" : "lightbulb.fill")
                .foregroundStyle(finding.severity == .warning ? .orange : .yellow)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Text(finding.suggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(finding.severity == .warning ? "Warning" : "Suggestion"): \(finding.message). \(finding.suggestion)")
    }
}

/// A quiz-wide summary listing every flagged question. Selecting one jumps to it.
struct QuizLintSheet: View {
    let quiz: Quiz
    let onSelect: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    private var flagged: [(number: Int, question: QuizQuestion, findings: [LintFinding])] {
        let byID = QuestionLinter().findings(for: quiz)
        return quiz.questions.enumerated().compactMap { index, question in
            guard let findings = byID[question.id] else { return nil }
            return (index + 1, question, findings)
        }
    }

    private var html = HTMLUtilities()

    init(quiz: Quiz, onSelect: @escaping (UUID) -> Void) {
        self.quiz = quiz
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Quality Check", systemImage: "checklist")
                    .font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            if flagged.isEmpty {
                ContentUnavailableView {
                    Label("No issues found", systemImage: "checkmark.seal")
                } description: {
                    Text("The offline linter didn't flag any item-writing problems.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(flagged.count) of \(quiz.questions.count) question\(quiz.questions.count == 1 ? "" : "s") have suggestions. These never block saving or export.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        ForEach(flagged, id: \.question.id) { entry in
                            Button {
                                onSelect(entry.question.id)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(entry.number). \(plainPrompt(entry.question))")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    ForEach(entry.findings) { finding in
                                        LintFindingRow(finding: finding)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(.rect(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .help("Jump to question \(entry.number)")
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 520)
    }

    private func plainPrompt(_ question: QuizQuestion) -> String {
        let text = html.plainText(fromHTML: question.prompt)
        return text.isEmpty ? "Untitled question" : text
    }
}
