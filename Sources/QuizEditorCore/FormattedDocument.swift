import Foundation

/// Builds a human-readable, print-friendly HTML document from a quiz — used for
/// both the "Export Formatted Document" command and the in-app preview modal.
/// Question text is already stored as HTML, so it is embedded directly.
public struct FormattedDocumentBuilder: Sendable {
    private let html = HTMLUtilities()

    public init() {}

    /// A complete standalone HTML document for the whole quiz.
    public func document(for quiz: Quiz, showAnswerKey: Bool = true) -> String {
        let questions = quiz.questions.enumerated()
            .map { questionSection(number: $0.offset + 1, question: $0.element, showAnswerKey: showAnswerKey) }
            .joined(separator: "\n")
        let body = "<h1>\(escape(quiz.title.isEmpty ? "Untitled Quiz" : quiz.title))</h1>\n\(questions)"
        return wrap(title: quiz.title.isEmpty ? "Untitled Quiz" : quiz.title, body: body)
    }

    /// A complete standalone HTML document for a single question.
    public func document(for question: QuizQuestion, number: Int, showAnswerKey: Bool = true) -> String {
        wrap(title: "Question \(number)", body: questionSection(number: number, question: question, showAnswerKey: showAnswerKey))
    }

    private func questionSection(number: Int, question: QuizQuestion, showAnswerKey: Bool) -> String {
        var parts = ["<section class=\"question\">"]
        parts.append("<div class=\"qhead\"><span class=\"qnum\">\(number)</span><span class=\"qtype\">\(escape(question.type.displayName))</span></div>")
        parts.append("<div class=\"prompt\">\(question.prompt)</div>")

        switch question.type {
        case .matching:
            parts.append(matchingList(question.matches, showAnswerKey: showAnswerKey))
        case .essay, .shortAnswer, .fillInBlank:
            if showAnswerKey, !question.answers.isEmpty {
                let answers = question.answers.map { "<li>\($0.text)</li>" }.joined()
                parts.append("<div class=\"answerkey\"><span class=\"label\">Sample answer:</span><ul>\(answers)</ul></div>")
            } else {
                parts.append("<div class=\"response-space\"></div>")
            }
        default:
            parts.append(choiceList(question.answers, showAnswerKey: showAnswerKey))
        }

        if showAnswerKey, !question.feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("<div class=\"feedback\"><span class=\"label\">Feedback:</span> <span class=\"fbbody\">\(question.feedback)</span></div>")
        }

        parts.append("</section>")
        return parts.joined(separator: "\n")
    }

    private func choiceList(_ answers: [QuizAnswer], showAnswerKey: Bool) -> String {
        let items = answers.enumerated().map { index, answer -> String in
            let letter = String(UnicodeScalar(UInt8(65 + (index % 26))))
            if showAnswerKey, answer.isCorrect {
                return "<li class=\"correct\"><span class=\"marker\">\u{2713}</span><span class=\"letter\">\(letter).</span> \(answer.text) <span class=\"tag\">(correct)</span></li>"
            }
            return "<li><span class=\"marker\"></span><span class=\"letter\">\(letter).</span> \(answer.text)</li>"
        }.joined()
        return "<ol class=\"choices\">\(items)</ol>"
    }

    private func matchingList(_ matches: [MatchingPair], showAnswerKey: Bool) -> String {
        let rows = matches.map { pair -> String in
            if showAnswerKey {
                return "<tr><td>\(pair.prompt)</td><td class=\"arrow\">\u{2192}</td><td>\(pair.match)</td></tr>"
            }
            return "<tr><td>\(pair.prompt)</td><td class=\"arrow\">\u{2192}</td><td class=\"blank\"></td></tr>"
        }.joined()
        return "<table class=\"matching\">\(rows)</table>"
    }

    private func wrap(title: String, body: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(title))</title>
        <style>
          :root { color-scheme: light dark; }
          body {
            font-family: -apple-system, system-ui, "Helvetica Neue", sans-serif;
            line-height: 1.5; max-width: 720px; margin: 32px auto; padding: 0 20px;
            color: canvastext;
          }
          h1 { font-size: 1.8rem; margin-bottom: 1.5rem; }
          .question { margin: 0 0 1.75rem; padding-bottom: 1.25rem; border-bottom: 1px solid color-mix(in srgb, canvastext 15%, transparent); }
          .qhead { display: flex; align-items: baseline; gap: 8px; margin-bottom: 6px; }
          .qnum { font-weight: 700; font-size: 1.1rem; }
          .qtype { font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.04em; color: color-mix(in srgb, canvastext 55%, transparent); }
          .prompt { margin-bottom: 10px; }
          ol.choices { list-style: none; padding-left: 0; margin: 8px 0; }
          ol.choices li { padding: 3px 0; }
          ol.choices .marker { display: inline-block; width: 1.2em; font-weight: 700; }
          ol.choices .letter { font-weight: 600; }
          ol.choices li.correct { font-weight: 600; }
          ol.choices li.correct .tag { font-weight: 400; font-size: 0.85em; color: color-mix(in srgb, canvastext 55%, transparent); }
          table.matching { border-collapse: collapse; margin: 8px 0; }
          table.matching td { padding: 4px 12px; border: 1px solid color-mix(in srgb, canvastext 20%, transparent); }
          table.matching td.arrow { border: none; }
          table.matching td.blank { min-width: 120px; }
          .response-space { height: 80px; border: 1px dashed color-mix(in srgb, canvastext 25%, transparent); border-radius: 6px; margin: 8px 0; }
          .answerkey .label, .feedback .label { font-weight: 700; }
          .feedback { margin-top: 8px; font-size: 0.95rem; color: color-mix(in srgb, canvastext 75%, transparent); }
          table { border-collapse: collapse; }
          th, td { border: 1px solid color-mix(in srgb, canvastext 30%, transparent); padding: 4px 8px; }
          img { max-width: 100%; height: auto; }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    private func escape(_ value: String) -> String {
        html.escapeForXML(value)
    }
}
