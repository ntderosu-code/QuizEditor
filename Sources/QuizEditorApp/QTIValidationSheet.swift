import SwiftUI
import QuizEditorCore

/// Drives the QTI validation sheet shown before an export when issues are found.
struct QTIValidationContext: Identifiable {
    let id = UUID()
    let engine: CanvasQuizEngine
    let issues: [QTIValidationIssue]
}

/// Reports QTI validation findings before exporting. The user can fix the quiz
/// and re-export, or proceed anyway (the findings are advisory).
struct QTIValidationSheet: View {
    let engineName: String
    let issues: [QTIValidationIssue]
    let onExportAnyway: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var hasErrors: Bool { issues.contains { $0.severity == .error } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: hasErrors ? "exclamationmark.triangle.fill" : "checkmark.seal")
                    .font(.title2)
                    .foregroundStyle(hasErrors ? .orange : .green)
                    .accessibilityHidden(true)
                Text("QTI Validation")
                    .font(.title2.bold())
                Spacer()
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(issues) { issue in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(issue.severity == .error ? .red : .orange)
                                .accessibilityHidden(true)
                            Text(issue.message)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(issue.severity == .error ? "Error" : "Warning"): \(issue.message)")
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export Anyway") {
                    onExportAnyway()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    private var summary: String {
        if hasErrors {
            return "The \(engineName) package has problems that may keep it from importing cleanly into Canvas or another LMS. Review them below — you can export anyway, but fixing them first is recommended."
        }
        return "The \(engineName) package re-imported cleanly. These notes are informational."
    }
}
