import Foundation

/// Helpers for moving question text between plain text, stored HTML, and the
/// XHTML that QTI 2.1 requires. Question fields are stored as HTML fragments;
/// plain-text content is simply an HTML fragment with no tags.
public struct HTMLUtilities: Sendable {
    public init() {}

    /// Strips tags and decodes entities to produce readable plain text.
    /// Used for plain-text import and for previews/labels that can't render HTML.
    public func plainText(fromHTML html: String) -> String {
        var text = html

        // Turn common block/line boundaries into newlines before removing tags.
        let lineBreakers = ["<br>", "<br/>", "<br />", "</p>", "</div>", "</li>", "</tr>", "</h1>", "</h2>", "</h3>"]
        for token in lineBreakers {
            text = text.replacingOccurrences(of: token, with: "\n", options: [.caseInsensitive])
        }

        // Remove all remaining tags.
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: [.regularExpression])

        text = decodeEntities(text)

        // Collapse runs of blank lines and trim trailing whitespace per line.
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: [.regularExpression])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns true when the fragment contains no HTML tags (it is already plain text).
    public func isPlainText(_ fragment: String) -> Bool {
        fragment.range(of: "<[a-zA-Z/][^>]*>", options: [.regularExpression]) == nil
    }

    /// The number of `<img>` tags that lack a non-empty `alt` attribute.
    /// Decorative images should use `alt=""`, which counts as present.
    public func imagesMissingAlt(in html: String) -> Int {
        let imgTags = matches(of: "<img\\b[^>]*>", in: html)
        return imgTags.reduce(into: 0) { count, tag in
            if !hasAltAttribute(in: tag) { count += 1 }
        }
    }

    public func containsImages(_ html: String) -> Bool {
        html.range(of: "<img\\b", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Converts an HTML fragment into a well-formed XHTML fragment for QTI 2.1,
    /// closing void elements and escaping stray entities. Returns nil if the
    /// content cannot be parsed.
    public func xhtmlFragment(from html: String) -> String? {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        guard let data = "<body>\(trimmed)</body>".data(using: .utf8) else { return nil }
        let options: XMLNode.Options = [.documentTidyHTML, .nodePreserveWhitespace]
        guard let document = try? XMLDocument(data: data, options: options),
              let body = (try? document.nodes(forXPath: "//body"))?.first as? XMLElement else {
            return nil
        }

        let serialized = (body.children ?? []).map { $0.xmlString }.joined()
        return serialized.isEmpty ? nil : serialized
    }

    /// Escapes a plain string so it is safe to place as text inside XML/HTML.
    public func escapeForXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func hasAltAttribute(in imgTag: String) -> Bool {
        // Matches alt="..." or alt='...'; an empty value (alt="") is intentional and allowed.
        imgTag.range(of: "\\balt\\s*=\\s*(\"[^\"]*\"|'[^']*')", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func decodeEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }
}

/// Reports accessibility problems that must be fixed before a quiz can be exported.
public struct QuizAccessibilityValidator: Sendable {
    private let html = HTMLUtilities()

    public init() {}

    /// Returns a human-readable issue for each question whose content includes an
    /// image without alt text. An empty result means the quiz passes.
    public func imagesMissingAltText(in quiz: Quiz) -> [String] {
        quiz.questions.enumerated().compactMap { index, question in
            let fields = [question.prompt, question.feedback]
                + question.answers.map(\.text)
                + question.matches.flatMap { [$0.prompt, $0.match] }
            let missing = fields.reduce(0) { $0 + html.imagesMissingAlt(in: $1) }
            guard missing > 0 else { return nil }
            let title = html.plainText(fromHTML: question.prompt).prefix(50)
            let label = title.isEmpty ? "Question \(index + 1)" : "Question \(index + 1) (\(title)…)"
            return "\(label): \(missing) image\(missing == 1 ? "" : "s") missing alt text"
        }
    }
}
