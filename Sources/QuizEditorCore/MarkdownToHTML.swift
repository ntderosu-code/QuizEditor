import Foundation

/// Converts a common subset of Markdown to HTML for display in a web view.
/// Built in-house (no third-party dependencies) and covers what AI responses
/// typically use: headings, bold/italic, inline code, fenced code blocks,
/// bulleted and numbered lists, block quotes, horizontal rules, and links.
public struct MarkdownToHTML: Sendable {
    private let html = HTMLUtilities()

    public init() {}

    /// A complete, styled standalone HTML document (light/dark aware).
    public func document(from markdown: String) -> String {
        wrap(body: bodyHTML(from: markdown))
    }

    /// Just the HTML body fragment — exposed for testing and embedding.
    public func bodyHTML(from markdown: String) -> String {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        var out: [String] = []
        var openListTag: String?
        var inCodeBlock = false
        var codeBuffer: [String] = []

        func closeList() {
            if let tag = openListTag {
                out.append("</\(tag)>")
                openListTag = nil
            }
        }
        func openList(_ tag: String) {
            if openListTag != tag {
                closeList()
                out.append("<\(tag)>")
                openListTag = tag
            }
        }

        for line in lines {
            if inCodeBlock {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    out.append("<pre><code>\(codeBuffer.map(escape).joined(separator: "\n"))</code></pre>")
                    codeBuffer.removeAll()
                    inCodeBlock = false
                } else {
                    codeBuffer.append(line)
                }
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                closeList()
                inCodeBlock = true
                continue
            }
            if trimmed.isEmpty {
                closeList()
                continue
            }
            if let (level, text) = heading(trimmed) {
                closeList()
                out.append("<h\(level)>\(inline(text))</h\(level)>")
                continue
            }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                closeList()
                out.append("<hr>")
                continue
            }
            if trimmed == ">" || trimmed.hasPrefix("> ") {
                closeList()
                let quote = trimmed == ">" ? "" : String(trimmed.dropFirst(2))
                out.append("<blockquote>\(inline(quote))</blockquote>")
                continue
            }
            if let item = unorderedItem(trimmed) {
                openList("ul")
                out.append("<li>\(inline(item))</li>")
                continue
            }
            if let item = orderedItem(trimmed) {
                openList("ol")
                out.append("<li>\(inline(item))</li>")
                continue
            }
            closeList()
            out.append("<p>\(inline(trimmed))</p>")
        }

        if inCodeBlock {
            out.append("<pre><code>\(codeBuffer.map(escape).joined(separator: "\n"))</code></pre>")
        }
        closeList()
        return out.joined(separator: "\n")
    }

    // MARK: - Block helpers

    private func heading(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        var index = line.startIndex
        while index < line.endIndex, line[index] == "#", level < 6 {
            level += 1
            index = line.index(after: index)
        }
        guard level > 0, index < line.endIndex, line[index] == " " else { return nil }
        return (level, String(line[line.index(after: index)...]))
    }

    private func unorderedItem(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private func orderedItem(_ line: String) -> String? {
        // e.g. "1. text" or "12) text"
        guard let match = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) else { return nil }
        return String(line[match.upperBound...])
    }

    // MARK: - Inline formatting

    private func inline(_ raw: String) -> String {
        // Escape first so any HTML in the source is inert, then layer Markdown.
        var text = escape(raw)
        text = replace(text, #"\[([^\]]+)\]\(([^)\s]+)\)"#, "<a href=\"$2\">$1</a>")
        text = replace(text, "`([^`]+)`", "<code>$1</code>")
        text = replace(text, #"\*\*([^*]+)\*\*"#, "<strong>$1</strong>")
        text = replace(text, #"(?<![*\w])\*([^*\n]+)\*(?![*\w])"#, "<em>$1</em>")
        text = replace(text, #"(?<!\w)_([^_\n]+)_(?!\w)"#, "<em>$1</em>")
        return text
    }

    private func replace(_ text: String, _ pattern: String, _ template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private func escape(_ value: String) -> String {
        html.escapeForXML(value)
    }

    private func wrap(body: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root { color-scheme: light dark; }
          body {
            font-family: -apple-system, system-ui, "Helvetica Neue", sans-serif;
            line-height: 1.5; margin: 20px; color: canvastext;
            font-size: 14px;
          }
          h1 { font-size: 1.5rem; } h2 { font-size: 1.25rem; } h3 { font-size: 1.1rem; }
          h1, h2, h3, h4, h5, h6 { margin: 1.1em 0 0.4em; line-height: 1.25; }
          p { margin: 0.5em 0; }
          ul, ol { margin: 0.5em 0; padding-left: 1.5em; }
          li { margin: 0.2em 0; }
          code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.9em;
            background: color-mix(in srgb, canvastext 10%, transparent); padding: 1px 4px; border-radius: 4px; }
          pre { background: color-mix(in srgb, canvastext 8%, transparent); padding: 10px 12px;
            border-radius: 8px; overflow-x: auto; }
          pre code { background: none; padding: 0; }
          blockquote { margin: 0.6em 0; padding: 2px 12px; border-left: 3px solid color-mix(in srgb, canvastext 30%, transparent);
            color: color-mix(in srgb, canvastext 75%, transparent); }
          hr { border: none; border-top: 1px solid color-mix(in srgb, canvastext 20%, transparent); margin: 1em 0; }
          a { color: -apple-system-blue; }
          table { border-collapse: collapse; }
          th, td { border: 1px solid color-mix(in srgb, canvastext 30%, transparent); padding: 4px 8px; }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
}
