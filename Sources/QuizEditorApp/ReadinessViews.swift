import SwiftUI
import QuizEditorCore

/// A compact status pill for a question's deterministic readiness. State is carried
/// by both an icon and text, never color alone.
struct ReadinessBadge: View {
    let status: ReadinessStatus

    var body: some View {
        Label(status.label, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: .capsule)
            .foregroundStyle(tint)
            .accessibilityLabel("Readiness: \(status.label)")
    }

    private var icon: String {
        switch status {
        case .draft: "pencil.circle"
        case .needsWork: "exclamationmark.triangle.fill"
        case .ready: "checkmark.seal.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .draft: .secondary
        case .needsWork: .orange
        case .ready: .green
        }
    }
}

/// A compact readiness panel: the status badge plus the list of unmet checks, so a
/// user can tell what remains before the question is ready without running AI. A
/// fully ready question collapses to just the badge and a confirming line.
struct QuestionReadinessView: View {
    let readiness: QuestionReadiness

    var body: some View {
        let unmet = readiness.unmet
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ReadinessBadge(status: readiness.status)
                Text(unmet.isEmpty
                     ? "All readiness checks pass."
                     : "\(unmet.count) item\(unmet.count == 1 ? "" : "s") to finish before this question is ready.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            if !unmet.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(unmet) { check in
                        Label {
                            Text(check.message)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: icon(for: check.severity))
                                .foregroundStyle(tint(for: check.severity))
                                .accessibilityHidden(true)
                        }
                        .accessibilityLabel("\(check.title), \(severityWord(check.severity)): \(check.message)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.18)))
    }

    private func icon(for severity: ReadinessCheck.Severity) -> String {
        switch severity {
        case .ok: "checkmark.circle.fill"
        case .recommended: "exclamationmark.circle"
        case .required: "xmark.circle.fill"
        }
    }

    private func tint(for severity: ReadinessCheck.Severity) -> Color {
        switch severity {
        case .ok: .green
        case .recommended: .orange
        case .required: .red
        }
    }

    private func severityWord(_ severity: ReadinessCheck.Severity) -> String {
        switch severity {
        case .ok: "done"
        case .recommended: "recommended"
        case .required: "needs attention"
        }
    }
}
