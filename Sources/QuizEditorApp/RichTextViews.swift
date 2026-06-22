import SwiftUI
import UniformTypeIdentifiers
import AppKit
import WebKit
import QuizEditorCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Bridges SwiftUI toolbar actions to the contentEditable web view.
@MainActor
final class RichTextController: ObservableObject {
    weak var webView: WKWebView?

    func exec(_ command: String, value: String? = nil) {
        let arg = value.map { "'\($0.replacingOccurrences(of: "'", with: "\\'"))'" } ?? "null"
        webView?.evaluateJavaScript("editorExec('\(command)', \(arg));")
    }

    func insertHTML(_ html: String) {
        let escaped = html
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        webView?.evaluateJavaScript("editorInsert(`\(escaped)`);")
    }
}

/// A true WYSIWYG editor: a styled contentEditable web view that round-trips HTML.
struct RichTextEditor: NSViewRepresentable {
    @Binding var html: String
    let controller: RichTextController

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "changed")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        controller.webView = webView
        webView.loadHTMLString(Self.template, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Only push when the value changed externally (e.g. AI apply), not while typing.
        guard context.coordinator.isLoaded, html != context.coordinator.lastReportedHTML else { return }
        context.coordinator.setContent(html)
    }

    func makeCoordinator() -> Coordinator { Coordinator(html: $html) }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let html: Binding<String>
        weak var webView: WKWebView?
        var isLoaded = false
        var lastReportedHTML: String

        init(html: Binding<String>) {
            self.html = html
            self.lastReportedHTML = html.wrappedValue
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            setContent(html.wrappedValue)
        }

        func setContent(_ content: String) {
            lastReportedHTML = content
            let escaped = content
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
            webView?.evaluateJavaScript("editorSetContent(`\(escaped)`);")
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? String else { return }
            lastReportedHTML = body
            html.wrappedValue = body
        }
    }

    private static let template = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      :root { color-scheme: light dark; }
      html, body { margin: 0; height: 100%; }
      #editor {
        font: -apple-system-body;
        font-family: -apple-system, system-ui, sans-serif;
        padding: 10px; min-height: 100%; outline: none; line-height: 1.4;
        color: canvastext;
      }
      #editor:empty::before { content: "Start typing…"; color: gray; }
      table { border-collapse: collapse; margin: 8px 0; }
      th, td { border: 1px solid color-mix(in srgb, canvastext 35%, transparent); padding: 4px 8px; }
      img { max-width: 100%; height: auto; }
    </style>
    </head>
    <body>
    <div id="editor" contenteditable="true"></div>
    <script>
      const editor = document.getElementById('editor');
      function report() { window.webkit.messageHandlers.changed.postMessage(editor.innerHTML); }
      function editorSetContent(html) { editor.innerHTML = html; }
      function editorExec(cmd, val) { editor.focus(); document.execCommand(cmd, false, val); report(); }
      function editorInsert(html) { editor.focus(); document.execCommand('insertHTML', false, html); report(); }
      editor.addEventListener('input', report);
      editor.addEventListener('blur', report);
    </script>
    </body>
    </html>
    """
}

/// WYSIWYG rich text field with a formatting toolbar and enforced image alt text.
struct RichTextField: View {
    let title: String
    @Binding var text: String
    var minHeight: CGFloat = 160
    var showsTitle: Bool = true

    @StateObject private var controller = RichTextController()
    @State private var isImageSheetPresented = false
    private let html = HTMLUtilities()

    private var imagesMissingAlt: Int { html.imagesMissingAlt(in: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if showsTitle {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                formattingToolbar
            }

            if imagesMissingAlt > 0 {
                Label("\(imagesMissingAlt) image\(imagesMissingAlt == 1 ? "" : "s") missing alt text — add it before exporting.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            RichTextEditor(html: $text, controller: controller)
                .frame(minHeight: minHeight)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(.rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                .accessibilityLabel(title)
        }
        .sheet(isPresented: $isImageSheetPresented) {
            ImageInsertSheet { markup in
                controller.insertHTML(markup)
            }
        }
    }

    private var formattingToolbar: some View {
        HStack(spacing: 6) {
            toolbarButton("Bold", systemImage: "bold") { controller.exec("bold") }
            toolbarButton("Italic", systemImage: "italic") { controller.exec("italic") }
            toolbarButton("Underline", systemImage: "underline") { controller.exec("underline") }

            toolbarDivider

            toolbarButton("Bulleted list", systemImage: "list.bullet") { controller.exec("insertUnorderedList") }
            toolbarButton("Numbered list", systemImage: "list.number") { controller.exec("insertOrderedList") }

            toolbarDivider

            toolbarButton("Link", systemImage: "link") {
                controller.insertHTML("<a href=\"https://\">link text</a>")
            }
            toolbarButton("Table", systemImage: "tablecells") {
                controller.insertHTML("<table><tr><th>Header 1</th><th>Header 2</th></tr><tr><td>Cell</td><td>Cell</td></tr></table>")
            }
            toolbarButton("Insert image", systemImage: "photo") { isImageSheetPresented = true }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        // Floating Liquid Glass control cluster over the editor content.
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var toolbarDivider: some View {
        Divider().frame(height: 16)
    }

    private func toolbarButton(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .imageScale(.large)
                .frame(minWidth: 26, minHeight: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Picks an image file, embeds it, and requires alt text (or an explicit decorative choice).
struct ImageInsertSheet: View {
    let onInsert: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var fileName: String?
    @State private var dataURI: String?
    @State private var altText = ""
    @State private var isDecorative = false

    private var canInsert: Bool {
        dataURI != nil && (isDecorative || !altText.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Insert Image")
                .font(.title2.bold())
            Text("Choose an image file. Images need alt text describing their content, or mark the image decorative if it adds no information.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LabeledField("Image file") {
                HStack {
                    Button("Choose File…", action: chooseFile)
                    Text(fileName ?? "No file selected")
                        .font(.callout)
                        .foregroundStyle(fileName == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            LabeledField("Alt text") {
                TextField("Describe the image for screen readers", text: $altText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isDecorative)
            }

            Toggle("This image is decorative (no alt text needed)", isOn: $isDecorative)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Insert") {
                    guard let dataURI else { return }
                    let alt = isDecorative ? "" : altText.trimmingCharacters(in: .whitespacesAndNewlines)
                    onInsert("<img src=\"\(dataURI)\" alt=\"\(escapeAttribute(alt))\">")
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canInsert)
            }
        }
        .padding(24)
        .frame(minWidth: 480)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        let mime = mimeType(for: url.pathExtension.lowercased())
        fileName = url.lastPathComponent
        dataURI = "data:\(mime);base64,\(data.base64EncodedString())"
    }

    private func mimeType(for ext: String) -> String {
        switch ext {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "svg": "image/svg+xml"
        case "webp": "image/webp"
        default: "image/png"
        }
    }

    private func escapeAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
    }
}

/// Renders a complete HTML document (used for the formatted preview).
struct FullHTMLPreview: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }
}

/// Modal that previews a formatted version of one question or the full quiz.
