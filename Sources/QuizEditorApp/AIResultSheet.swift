import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuizEditorCore

/// An AI result ready to show in the result modal.
struct AIResultContext: Identifiable {
    let id = UUID()
    let title: String
    let markdown: String
}

/// Status line shown inline in the AI panel (hint or error).
struct PanelStatus {
    let text: String
    let isError: Bool
}

/// Presents an AI result as formatted (rendered Markdown), with the option to
/// view the raw Markdown, copy it, or save it to a file.
struct AIResultSheet: View {
    let result: AIResultContext
    @Environment(\.dismiss) private var dismiss
    @State private var showRawMarkdown = false

    private var renderedHTML: String { MarkdownToHTML().document(from: result.markdown) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(result.title, systemImage: "sparkles")
                    .font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            if showRawMarkdown {
                ScrollView {
                    Text(result.markdown)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
                .accessibilityLabel("Raw Markdown result")
            } else {
                FullHTMLPreview(html: renderedHTML)
                    .accessibilityLabel("Formatted result")
            }

            Divider()

            HStack {
                Toggle("Raw Markdown", isOn: $showRawMarkdown)
                    .toggleStyle(.switch)
                    .help("Switch between the formatted result and the raw Markdown")
                Spacer()
                Button {
                    copyToClipboard()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                Button {
                    save()
                } label: {
                    Label("Save…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(minWidth: 640, minHeight: 560)
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.markdown, forType: .string)
    }

    private func save() {
        let panel = NSSavePanel()
        let markdownType = UTType(filenameExtension: "md") ?? .plainText
        panel.allowedContentTypes = [markdownType, .html]
        panel.nameFieldStringValue = filenameBase + ".md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Honor the chosen extension: .html saves the rendered document, otherwise Markdown.
        let isHTML = ["html", "htm"].contains(url.pathExtension.lowercased())
        let contents = isHTML ? renderedHTML : result.markdown
        try? contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private var filenameBase: String {
        let safe = result.title
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return safe.isEmpty ? "ai-result" : safe.lowercased()
    }
}
