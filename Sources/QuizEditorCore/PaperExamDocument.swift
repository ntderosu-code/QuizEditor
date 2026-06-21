import Foundation

/// Options for a printable paper exam.
public struct PaperExamOptions: Sendable, Equatable {
    /// Editable instructions printed above the first question. Empty hides the block.
    public var instructions: String
    /// When true, produces the instructor answer-key copy (correct answers,
    /// sample responses, and feedback). When false, produces the blank student copy.
    public var includeAnswerKey: Bool
    /// Optional version or seat label printed in the footer (e.g. "Version A").
    public var versionLabel: String
    /// Show per-question point values and the total in the score field.
    public var showPoints: Bool

    public init(
        instructions: String = "",
        includeAnswerKey: Bool = false,
        versionLabel: String = "",
        showPoints: Bool = true
    ) {
        self.instructions = instructions
        self.includeAnswerKey = includeAnswerKey
        self.versionLabel = versionLabel
        self.showPoints = showPoints
    }
}

/// Builds a clean, print-ready paper exam (HTML → print / Save as PDF) suitable
/// for a campus testing center. Two outputs come from one quiz: a blank student
/// copy and a separate instructor answer-key copy.
public struct PaperExamBuilder: Sendable {
    private let html = HTMLUtilities()

    public init() {}

    public func document(for quiz: Quiz, options: PaperExamOptions = PaperExamOptions()) -> String {
        let title = quiz.title.isEmpty ? "Untitled Quiz" : quiz.title
        let questionsHTML = quiz.questions.enumerated()
            .map { questionBlock(number: $0.offset + 1, question: $0.element, options: options) }
            .joined(separator: "\n")

        let body = """
        \(headerBlock(quiz: quiz, options: options))
        \(instructionsBlock(options))
        <main>
        \(questionsHTML)
        </main>
        \(footerBlock(title: title, options: options))
        """

        return wrap(title: title, options: options, body: body)
    }

    // MARK: - Header / instructions / footer

    private func headerBlock(quiz: Quiz, options: PaperExamOptions) -> String {
        let title = escape(quiz.title.isEmpty ? "Untitled Quiz" : quiz.title)
        let outOf = options.showPoints ? formatPoints(quiz.totalPoints) : String(quiz.questions.count)
        let keyBadge = options.includeAnswerKey
            ? "<span class=\"keybadge\">ANSWER KEY</span>"
            : ""
        return """
        <header class="exam-header">
          <div class="title-row"><h1>\(title)</h1>\(keyBadge)</div>
          <div class="fields">
            <div class="field grow"><span class="flabel">Name</span><span class="fline"></span></div>
            <div class="field"><span class="flabel">Date</span><span class="fline short"></span></div>
            <div class="field grow"><span class="flabel">Course / Section</span><span class="fline"></span></div>
            <div class="field"><span class="flabel">Score</span><span class="fline tiny"></span><span class="outof"> / \(outOf)</span></div>
          </div>
        </header>
        """
    }

    private func instructionsBlock(_ options: PaperExamOptions) -> String {
        let trimmed = options.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        // Instructions are plain text entered by the instructor; escape and keep line breaks.
        let escaped = escape(trimmed).replacingOccurrences(of: "\n", with: "<br>")
        return "<section class=\"instructions\"><strong>Instructions:</strong> \(escaped)</section>"
    }

    private func footerBlock(title: String, options: PaperExamOptions) -> String {
        let version = options.versionLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let versionPart = version.isEmpty ? "" : " &middot; \(escape(version))"
        return "<footer class=\"exam-footer\">\(escape(title))\(versionPart)</footer>"
    }

    // MARK: - Questions

    private func questionBlock(number: Int, question: QuizQuestion, options: PaperExamOptions) -> String {
        var parts = ["<section class=\"q\">"]

        let pointsTag = options.showPoints
            ? "<span class=\"points\">(\(formatPoints(question.points)) pt\(question.points == 1 ? "" : "s"))</span>"
            : ""
        parts.append("<div class=\"qhead\"><span class=\"qnum\">\(number).</span><div class=\"prompt\">\(question.prompt)</div>\(pointsTag)</div>")

        switch question.type {
        case .multipleChoice, .multipleAnswer, .trueFalse:
            parts.append(choiceBlock(question, options: options))
        case .shortAnswer, .fillInBlank:
            parts.append(writeInBlock(question, options: options, lines: 1))
        case .essay:
            parts.append(essayBlock())
        case .matching:
            parts.append(matchingBlock(question, options: options))
        }

        if options.includeAnswerKey {
            let feedback = question.feedback.trimmingCharacters(in: .whitespacesAndNewlines)
            if !feedback.isEmpty {
                parts.append("<div class=\"key-feedback\"><span class=\"klabel\">Feedback:</span> \(question.feedback)</div>")
            }
        }

        parts.append("</section>")
        return parts.joined(separator: "\n")
    }

    private func choiceBlock(_ question: QuizQuestion, options: PaperExamOptions) -> String {
        let items = question.answers.enumerated().map { index, answer -> String in
            let letter = letter(at: index)
            let bubble = options.includeAnswerKey && answer.isCorrect ? "filled" : "open"
            let tag = options.includeAnswerKey && answer.isCorrect ? " <span class=\"ktag\">(correct)</span>" : ""
            return "<li><span class=\"bubble \(bubble)\"></span><span class=\"letter\">\(letter).</span> \(escape(answer.text))\(tag)</li>"
        }.joined()
        return "<ol class=\"choices\">\(items)</ol>"
    }

    private func writeInBlock(_ question: QuizQuestion, options: PaperExamOptions, lines: Int) -> String {
        if options.includeAnswerKey {
            let accepted = question.answers.map { escape($0.text) }.filter { !$0.isEmpty }
            let answerText = accepted.isEmpty ? "(no accepted answer provided)" : accepted.joined(separator: " / ")
            return "<div class=\"key-answer\"><span class=\"klabel\">Answer:</span> \(answerText)</div>"
        }
        return "<div class=\"writein\"></div>"
    }

    private func essayBlock() -> String {
        "<div class=\"essay-space\" aria-hidden=\"true\"></div>"
    }

    private func matchingBlock(_ question: QuizQuestion, options: PaperExamOptions) -> String {
        // Present the right-hand matches as a lettered bank sorted alphabetically,
        // so the bank order does not give away which term lines up with which match.
        let bank = question.matches
            .map(\.match)
            .enumerated()
            .sorted { $0.element.localizedCaseInsensitiveCompare($1.element) == .orderedAscending }
        let letterForMatch: [String: String] = Dictionary(
            uniqueKeysWithValues: bank.enumerated().map { ($0.element.element, letter(at: $0.offset)) }
        )

        let terms = question.matches.enumerated().map { index, pair -> String in
            let blank = options.includeAnswerKey
                ? "<span class=\"matchblank filled\">\(letterForMatch[pair.match] ?? "")</span>"
                : "<span class=\"matchblank\"></span>"
            return "<li>\(blank)<span class=\"term\">\(escape(pair.prompt))</span></li>"
        }.joined()

        let bankItems = bank.enumerated().map { offset, element in
            "<li><span class=\"letter\">\(letter(at: offset)).</span> \(escape(element.element))</li>"
        }.joined()

        return """
        <div class="matching">
          <ol class="terms">\(terms)</ol>
          <ul class="bank"><li class="bank-label">Choices:</li>\(bankItems)</ul>
        </div>
        """
    }

    // MARK: - Document shell

    private func wrap(title: String, options: PaperExamOptions, body: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(title))\(options.includeAnswerKey ? " — Answer Key" : "")</title>
        <style>
          :root { color-scheme: light; }
          * { box-sizing: border-box; }
          body {
            font-family: "Times New Roman", Georgia, serif;
            font-size: 12pt; line-height: 1.45; color: #000; background: #fff;
            max-width: 720px; margin: 24px auto; padding: 0 24px;
          }
          h1 { font-size: 1.5rem; margin: 0; }
          .exam-header { border-bottom: 2px solid #000; padding-bottom: 10px; margin-bottom: 14px; }
          .title-row { display: flex; align-items: baseline; gap: 12px; justify-content: space-between; }
          .keybadge { font-family: -apple-system, system-ui, sans-serif; font-size: 0.7rem; font-weight: 700;
            letter-spacing: 0.08em; border: 1.5px solid #000; padding: 2px 6px; border-radius: 4px; }
          .fields { display: flex; flex-wrap: wrap; gap: 8px 18px; margin-top: 12px; }
          .field { display: flex; align-items: baseline; gap: 6px; }
          .field.grow { flex: 1 1 240px; }
          .flabel { font-weight: 700; white-space: nowrap; }
          .fline { border-bottom: 1px solid #000; flex: 1; min-width: 120px; height: 1.1em; }
          .fline.short { min-width: 90px; } .fline.tiny { min-width: 48px; flex: 0 0 48px; }
          .outof { font-weight: 700; }
          .instructions { font-family: -apple-system, system-ui, sans-serif; font-size: 0.95rem;
            border: 1px solid #888; border-radius: 6px; padding: 8px 12px; margin-bottom: 16px; background: #f6f6f6; }
          .q { margin: 0 0 18px; padding: 2px 0; break-inside: avoid; page-break-inside: avoid; }
          .qhead { display: flex; gap: 8px; align-items: baseline; }
          .qnum { font-weight: 700; }
          .prompt { flex: 1; }
          .prompt p { margin: 0 0 6px; }
          .points { font-family: -apple-system, system-ui, sans-serif; font-size: 0.8rem; color: #333; white-space: nowrap; }
          ol.choices { list-style: none; padding-left: 28px; margin: 6px 0 0; }
          ol.choices li { padding: 3px 0; display: flex; align-items: baseline; gap: 6px; }
          .bubble { display: inline-block; width: 13px; height: 13px; border: 1.4px solid #000; border-radius: 50%; flex: 0 0 auto; }
          .bubble.filled { background: #000; }
          .letter { font-weight: 600; }
          .writein { border-bottom: 1px solid #000; height: 2.2em; margin: 6px 0 0 28px; }
          .essay-space { border: 1px solid #aaa; border-radius: 4px; height: 150px; margin: 8px 0 0;
            background-image: repeating-linear-gradient(#fff, #fff 26px, #ddd 27px); }
          .matching { display: flex; flex-wrap: wrap; gap: 12px 32px; margin: 6px 0 0 28px; }
          .matching .terms { list-style: none; padding: 0; margin: 0; flex: 1 1 260px; }
          .matching .terms li { display: flex; align-items: baseline; gap: 8px; padding: 2px 0; }
          .matchblank { display: inline-block; min-width: 28px; border-bottom: 1px solid #000; text-align: center; font-weight: 700; }
          .matching .bank { list-style: none; padding: 8px 12px; margin: 0; border: 1px solid #888; border-radius: 6px; flex: 0 1 220px; }
          .matching .bank-label { font-weight: 700; }
          .key-answer, .key-feedback { font-family: -apple-system, system-ui, sans-serif; font-size: 0.9rem;
            margin: 6px 0 0 28px; color: #144d14; }
          .ktag, .klabel { font-weight: 700; }
          .exam-footer { margin-top: 24px; padding-top: 8px; border-top: 1px solid #000;
            font-family: -apple-system, system-ui, sans-serif; font-size: 0.8rem; color: #444; text-align: center; }
          @media print {
            body { margin: 0; max-width: none; }
            .exam-footer { position: fixed; bottom: 0; left: 0; right: 0; border: none; }
            @page { margin: 18mm 16mm 22mm; }
          }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    // MARK: - Helpers

    private func letter(at index: Int) -> String {
        String(UnicodeScalar(UInt8(65 + (index % 26))))
    }

    private func formatPoints(_ points: Double) -> String {
        points.rounded() == points ? String(Int(points)) : String(points)
    }

    private func escape(_ value: String) -> String {
        html.escapeForXML(value)
    }
}
