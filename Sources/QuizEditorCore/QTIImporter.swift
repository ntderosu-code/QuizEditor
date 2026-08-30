import Foundation

/// A group of questions discovered inside a package — a quiz (assessment) or an
/// item bank (objectbank). Used when importing IMS Common Cartridge files, which
/// can bundle several of each.
public struct QTISection: Equatable, Sendable {
    public enum Kind: Sendable, Equatable {
        case assessment
        case questionBank
    }

    public let title: String
    public let kind: Kind
    public let questions: [QuizQuestion]

    public init(title: String, kind: Kind, questions: [QuizQuestion]) {
        self.title = title
        self.kind = kind
        self.questions = questions
    }
}

public struct QTIImporter: Sendable {
    public enum ImportError: UserFacingError, Equatable {
        case missingUnzipExecutable
        case unzipFailed(status: Int32)
        case manifestNotFound
        case noQuestionsFound

        public var description: String {
            switch self {
            case .missingUnzipExecutable: "The system unzip command is unavailable."
            case .unzipFailed(let status): "The QTI archive could not be expanded. unzip exited with status \(status)."
            case .manifestNotFound: "The archive does not contain an imsmanifest.xml file."
            case .noQuestionsFound: "No supported quiz questions were found in the QTI archive."
            }
        }
    }

    /// When true, question text keeps its HTML formatting (bold, tables, images).
    /// When false, content is reduced to plain text — useful for messy sources.
    private let preserveFormatting: Bool
    private let html = HTMLUtilities()

    public init(preserveFormatting: Bool = true) {
        self.preserveFormatting = preserveFormatting
    }

    /// Applies to every captured content field: decode entities, then optionally strip formatting.
    private func renderField(_ raw: String) -> String {
        let decoded = xmlUnescape(raw)
        return preserveFormatting ? decoded : html.plainText(fromHTML: decoded)
    }

    public func importQuiz(fromZipAt archiveURL: URL) throws -> Quiz {
        let workingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        try unzip(archiveURL, into: workingDirectory)
        return try importQuiz(fromDirectory: workingDirectory)
    }

    public func importQuiz(fromDirectory directoryURL: URL) throws -> Quiz {
        let manifestURL = directoryURL.appendingPathComponent("imsmanifest.xml")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { throw ImportError.manifestNotFound }

        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        let assessmentPath = firstHref(containing: "assessment", in: manifest) ?? "assessment.xml"
        let assessmentURL = directoryURL.appendingPathComponent(assessmentPath)
        let assessment = (try? String(contentsOf: assessmentURL, encoding: .utf8)) ?? ""
        let itemPaths = itemHrefs(in: manifest, assessment: assessment)
        let title = xmlUnescape(attribute("title", in: assessment) ?? "Imported Quiz")

        var itemXML = itemPaths.compactMap { path -> String? in
            let itemURL = directoryURL.appendingPathComponent(path)
            return try? String(contentsOf: itemURL, encoding: .utf8)
        }

        // Many QTI packages (e.g. Canvas classic exports) embed every <item>
        // inline in a single assessment file instead of one file per question.
        // When no separate item files were referenced, parse the inline items.
        var questions = itemXML.compactMap { parseItem($0) }
        if questions.isEmpty {
            itemXML = inlineItems(in: assessment)
            questions = itemXML.compactMap { parseItem($0) }
        }

        guard !questions.isEmpty else { throw ImportError.noQuestionsFound }
        let scoringXML = ([assessment] + itemXML).joined(separator: "\n")
        let kind = detectSurvey(in: scoringXML, questions: questions) ? QuizKind.survey : .graded
        return Quiz(title: title.isEmpty ? "Imported Quiz" : title, questions: questions, kind: kind)
    }

    /// A QTI 1.2 package is a survey when nothing in it scores anything: no
    /// `points_possible` on any item, and no `<resprocessing>` block anywhere.
    /// The caller passes the assessment XML concatenated with every item file,
    /// since one-item-per-file packages keep both signals in the item files.
    /// New Quizzes packages use the same heuristic — surveys export with empty
    /// per-item response processing.
    ///
    /// The check operates on the raw XML, not the parsed model, so the
    /// per-question default `points: 1` doesn't make every quiz look graded.
    /// An item's `points_possible` qtimetadata field is the authoritative
    /// Canvas signal.
    private func detectSurvey(in packageXML: String, questions: [QuizQuestion]) -> Bool {
        let hasPoints = packageXML.contains("points_possible")
        let hasScoring = packageXML.contains("<resprocessing>")
            || packageXML.contains("respcondition")
        return !hasPoints && !hasScoring && !questions.isEmpty
    }

    /// Imports every quiz and item bank from an IMS Common Cartridge (`.imscc`)
    /// or QTI archive, grouped into sections so the caller can show which quiz or
    /// bank each question came from.
    public func importSections(fromZipAt archiveURL: URL) throws -> [QTISection] {
        let workingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        try unzip(archiveURL, into: workingDirectory)
        return try importSections(fromDirectory: workingDirectory)
    }

    public func importSections(fromDirectory directoryURL: URL) throws -> [QTISection] {
        let manifestURL = directoryURL.appendingPathComponent("imsmanifest.xml")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { throw ImportError.manifestNotFound }
        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)

        // Scan every QTI file the manifest references; keep the ones that actually
        // contain questions (assessments and objectbanks), skipping pages/settings.
        // Canvas stores question banks only in `non_cc_assessments/<id>.xml.qti`
        // files, so accept the `.qti` extension as well as `.xml`.
        let xmlHrefs = uniquePreservingOrder(hrefs(in: manifest).filter { $0.hasSuffix(".xml") || $0.hasSuffix(".qti") })
        var sections: [QTISection] = []
        for href in xmlHrefs {
            let fileURL = directoryURL.appendingPathComponent(href)
            guard let xml = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let isObjectBank = xml.contains("<objectbank")

            // Canvas's `.qti` files duplicate every assessment that already exists
            // in CC-standard form (the `<id>/assessment_qti.xml` files). Mine the
            // `.qti` copies for objectbanks only, so direct items are not imported
            // twice.
            if href.hasSuffix(".qti") && !isObjectBank { continue }

            let questions = extractItems(from: xml).compactMap { parseItem($0) }
            guard !questions.isEmpty else { continue }
            let kind: QTISection.Kind = isObjectBank ? .questionBank : .assessment
            // Canvas auto-generated banks often have no title; show a readable
            // label rather than the bank's GUID filename.
            let fallback = isObjectBank ? "Question Bank" : (href as NSString).lastPathComponent
            sections.append(QTISection(title: sectionTitle(in: xml, fallback: fallback), kind: kind, questions: questions))
        }

        // Keep quizzes in their cartridge order, then list the question banks
        // (the "folders" an author sees) alphabetically by name so they're easy to
        // scan and select in the import picker.
        let assessments = sections.filter { $0.kind == .assessment }
        let banks = sections.filter { $0.kind == .questionBank }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        sections = assessments + banks

        // Fall back to the single-assessment importer for plain QTI packages.
        if sections.isEmpty {
            let quiz = try importQuiz(fromDirectory: directoryURL)
            sections.append(QTISection(title: quiz.title, kind: .assessment, questions: quiz.questions))
        }

        guard sections.contains(where: { !$0.questions.isEmpty }) else { throw ImportError.noQuestionsFound }
        return sections
    }

    /// Returns the `<item>…</item>` blocks in a QTI 1.2 file (assessment or
    /// objectbank); for a QTI 2.1 file the whole document is a single item.
    private func extractItems(from xml: String) -> [String] {
        if xml.range(of: "<item\\b", options: .regularExpression) != nil {
            return inlineItems(in: xml)
        }
        if xml.contains("assessmentItem") {
            return [xml]
        }
        return []
    }

    private func sectionTitle(in xml: String, fallback: String) -> String {
        if let title = matches(pattern: #"<(?:assessment|objectbank)\b[^>]*\btitle="([^"]*)""#, in: xml).first, !title.isEmpty {
            return xmlUnescape(title)
        }
        // Canvas names a question bank with a `bank_title` qtimetadata field rather
        // than a title attribute; each bank carries its own, so this keeps banks
        // (the "folders" an author sees) as distinct, named sections.
        if let bankTitle = firstFieldEntry(afterFieldLabel: "bank_title", in: xml), !bankTitle.isEmpty {
            return xmlUnescape(bankTitle)
        }
        return (fallback as NSString).lastPathComponent
    }

    private func unzip(_ archiveURL: URL, into directoryURL: URL) throws {
        guard FileManager.default.fileExists(atPath: "/usr/bin/unzip") else {
            throw ImportError.missingUnzipExecutable
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq", archiveURL.path, "-d", directoryURL.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ImportError.unzipFailed(status: process.terminationStatus)
        }
    }

    private func itemHrefs(in manifest: String, assessment: String) -> [String] {
        var paths = hrefs(in: assessment).filter { $0.hasSuffix(".xml") && $0.contains("question") }
        if paths.isEmpty {
            paths = hrefs(in: manifest).filter { $0.hasSuffix(".xml") && $0.contains("question") }
        }
        return uniquePreservingOrder(paths)
    }

    private func inlineItems(in assessment: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"<item\b[\s\S]*?</item>"#, options: [.dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(assessment.startIndex..<assessment.endIndex, in: assessment)
        return regex.matches(in: assessment, range: range).compactMap { match in
            guard let range = Range(match.range, in: assessment) else { return nil }
            return String(assessment[range])
        }
    }

    private func firstHref(containing needle: String, in xml: String) -> String? {
        hrefs(in: xml).first { $0.localizedCaseInsensitiveContains(needle) }
    }

    private func hrefs(in xml: String) -> [String] {
        matches(pattern: #"href\s*=\s*\"([^\"]+)\""#, in: xml)
    }

    private func parseItem(_ xml: String) -> QuizQuestion? {
        if xml.contains("assessmentItem") || xml.contains("choiceInteraction") || xml.contains("matchInteraction") {
            return parseQTI21Item(xml)
        }
        return parseQTI12Item(xml)
    }

    private func parseQTI12Item(_ xml: String) -> QuizQuestion? {
        let canvasType = firstFieldEntry(afterFieldLabel: "question_type", in: xml)
        let type = questionType(canvasType: canvasType)
        let prompt = renderField(matches(pattern: #"<presentation>[\s\S]*?<mattext[^>]*>([\s\S]*?)</mattext>"#, in: xml).first ?? "")
        guard !prompt.isEmpty else { return nil }

        if type == .matching {
            return QuizQuestion(type: .matching, prompt: prompt, matches: classicMatchingPairs(in: xml), feedback: classicFeedback(in: xml))
        }

        if type == .numeric {
            return QuizQuestion(type: .numeric, prompt: prompt, feedback: classicFeedback(in: xml), numeric: parseClassicNumeric(in: xml))
        }

        if type == .formula {
            return QuizQuestion(type: .formula, prompt: prompt, feedback: classicFeedback(in: xml), formula: parseClassicFormula(in: xml))
        }

        if type == .fileUpload {
            return QuizQuestion(
                type: .fileUpload,
                prompt: prompt,
                feedback: classicFeedback(in: xml),
                allowedFileTypes: parseClassicFileUploadMimes(in: xml)
            )
        }

        let correctIDs = Set(matches(pattern: #"<varequal[^>]*>([^<]+)</varequal>"#, in: xml))
        let answers = matches(pattern: #"<response_label\s+ident=\"([^\"]+)\"[^>]*>[\s\S]*?<mattext[^>]*>([\s\S]*?)</mattext>"#, in: xml, groupCount: 2)
            .map { QuizAnswer(text: renderField($0[1]), isCorrect: correctIDs.contains($0[0])) }

        return QuizQuestion(type: type, prompt: prompt, answers: answers, feedback: classicFeedback(in: xml))
    }

    private func parseQTI21Item(_ xml: String) -> QuizQuestion? {
        let promptText = matches(pattern: #"<prompt>([\s\S]*?)</prompt>"#, in: xml).first
            ?? matches(pattern: #"<div>([\s\S]*?)</div>"#, in: xml).first
            ?? matches(pattern: #"<p>([\s\S]*?)</p>"#, in: xml).first
            ?? ""
        let prompt = renderField(promptText)
        guard !prompt.isEmpty else { return nil }

        if xml.contains("matchInteraction") {
            let sources = matches(pattern: #"<simpleAssociableChoice\s+identifier=\"source_[^\"]+\"[^>]*>([\s\S]*?)</simpleAssociableChoice>"#, in: xml).map(renderField)
            let targets = matches(pattern: #"<simpleAssociableChoice\s+identifier=\"target_[^\"]+\"[^>]*>([\s\S]*?)</simpleAssociableChoice>"#, in: xml).map(renderField)
            let pairs = zip(sources, targets).map { MatchingPair(prompt: $0.0, match: $0.1) }
            return QuizQuestion(type: .matching, prompt: prompt, matches: pairs, feedback: qti21Feedback(in: xml))
        }

        if xml.contains("uploadInteraction") {
            let mimes = matches(pattern: #"expectedMimeTypes=\"([^\"]+)\""#, in: xml)
                .first?
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty } ?? []
            return QuizQuestion(type: .fileUpload, prompt: prompt, feedback: qti21Feedback(in: xml), allowedFileTypes: Array(mimes))
        }

        // Numeric items in QTI 2.1: a text entry graded against a float. Formula
        // items are written the same way (same interaction, same base type, same
        // inline responseProcessing), because 2.1 has no canonical place to store
        // an expression — so a formula deliberately comes back as a numeric
        // carrying the same answer key. The expression is lost, which is
        // acceptable since most authors re-author formula questions rather than
        // re-import them. The float base type is what keeps fill-in-blank and
        // short answer, which also use textEntryInteraction, out of this branch.
        if xml.contains("textEntryInteraction"), isFloatResponse(in: xml) {
            return QuizQuestion(
                type: .numeric,
                prompt: prompt,
                feedback: qti21Feedback(in: xml),
                numeric: parseQTI21Numeric(in: xml)
            )
        }

        let correctResponse = matches(pattern: #"<correctResponse>([\s\S]*?)</correctResponse>"#, in: xml).first ?? ""
        let correctIDs = Set(matches(pattern: #"<value>([^<]+)</value>"#, in: correctResponse))
        let choices = matches(pattern: #"<simpleChoice\s+identifier=\"([^\"]+)\"[^>]*>([\s\S]*?)</simpleChoice>"#, in: xml, groupCount: 2)
        let answers = choices.map { QuizAnswer(text: renderField($0[1]), isCorrect: correctIDs.contains($0[0])) }
        let cardinality = attribute("cardinality", in: xml)
        let type: QuizQuestionType = cardinality == "multiple" ? .multipleAnswer : .multipleChoice
        return QuizQuestion(type: answers.isEmpty ? .essay : type, prompt: prompt, answers: answers, feedback: qti21Feedback(in: xml))
    }

    /// True when the RESPONSE declaration is graded as a float — the marker that
    /// separates a numeric/formula text entry from a string-graded one.
    private func isFloatResponse(in xml: String) -> Bool {
        guard let declaration = firstMatch(
            pattern: #"<responseDeclaration\s+identifier=\"RESPONSE\"[^>]*>"#,
            in: xml
        ) else { return false }
        return declaration.contains("baseType=\"float\"")
    }

    /// Recovers the grading spec from a QTI 2.1 numeric item's response
    /// processing. A `gte`/`lte` pair is an accepted interval; an `equal` test is
    /// an exact value. Both come back as `.exact` with a margin, since `.exact`
    /// with a margin and `.range` produce identical XML and the mode itself
    /// cannot be recovered. `correctResponse` supplies the centre when present so
    /// the author's stated answer survives rather than a computed midpoint.
    private func parseQTI21Numeric(in xml: String) -> NumericAnswer {
        let correctResponse = matches(pattern: #"<correctResponse>[\s\S]*?<value>([^<]+)</value>"#, in: xml)
            .first
            .flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }

        // Scope the bounds to responseProcessing so no stray value elsewhere wins.
        let processing = matches(pattern: #"<responseProcessing>([\s\S]*?)</responseProcessing>"#, in: xml).first ?? ""
        let lowerBound = matches(pattern: #"<gte>[\s\S]*?<baseValue[^>]*>([^<]+)</baseValue>"#, in: processing)
            .first
            .flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        let upperBound = matches(pattern: #"<lte>[\s\S]*?<baseValue[^>]*>([^<]+)</baseValue>"#, in: processing)
            .first
            .flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }

        if let low = lowerBound, let high = upperBound {
            let midpoint = (low + high) / 2
            return NumericAnswer(mode: .exact, value: correctResponse ?? midpoint, margin: (high - low) / 2)
        }

        let exactValue = matches(pattern: #"<equal[^>]*>[\s\S]*?<baseValue[^>]*>([^<]+)</baseValue>"#, in: processing)
            .first
            .flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }

        // No gradeable condition at all: an unconfigured numeric, not an essay.
        guard let value = exactValue ?? correctResponse else { return NumericAnswer(mode: .exact) }
        return NumericAnswer(mode: .exact, value: value, margin: 0)
    }

    private func questionType(canvasType: String?) -> QuizQuestionType {
        switch canvasType {
        case "multiple_answers_question": return .multipleAnswer
        case "true_false_question": return .trueFalse
        case "fill_in_the_blank_question": return .fillInBlank
        case "short_answer_question": return .shortAnswer
        case "essay_question": return .essay
        case "matching_question": return .matching
        case "numerical_question": return .numeric
        case "file_upload_question": return .fileUpload
        case "calculated_question", "formula_question": return .formula
        default: return .multipleChoice
        }
    }

    /// Recovers a numeric answer from QTI 1.2 response processing: a vargte/varlte
    /// pair becomes a range; a lone varequal becomes an exact value.
    private func parseClassicNumeric(in xml: String) -> NumericAnswer {
        if let low = matches(pattern: #"<vargte[^>]*>([^<]+)</vargte>"#, in: xml).first.flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) }),
           let high = matches(pattern: #"<varlte[^>]*>([^<]+)</varlte>"#, in: xml).first.flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) }) {
            return NumericAnswer(mode: .range, rangeMin: low, rangeMax: high)
        }
        if let value = matches(pattern: #"<varequal[^>]*>([^<]+)</varequal>"#, in: xml).first.flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) }) {
            return NumericAnswer(mode: .exact, value: value)
        }
        return NumericAnswer()
    }

    /// Recovers a formula spec from the `formula_question` qtimetadata field
    /// emitted by the exporter. The expression and variable list are carried in
    /// an embedded `<formula>` element.
    private func parseClassicFormula(in xml: String) -> FormulaAnswer? {
        let entry = firstFieldEntry(afterFieldLabel: "formula_question", in: xml) ?? ""
        guard !entry.isEmpty else { return nil }
        let expression = matches(pattern: #"<formula>([\s\S]*?)<variables>"#, in: entry).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let variables = matches(pattern: #"<variable\s+name=\"([^\"]+)\">([^<]+)</variable>"#, in: entry, groupCount: 2)
            .compactMap { pair -> FormulaVariable? in
                guard let value = Double(pair[1].trimmingCharacters(in: .whitespaces)) else { return nil }
                return FormulaVariable(name: pair[0], value: value)
            }
        guard !expression.isEmpty || !variables.isEmpty else { return nil }
        return FormulaAnswer(variables: variables, expression: expression)
    }

    private func parseClassicFileUploadMimes(in xml: String) -> [String] {
        let raw = matches(pattern: #"mimetype=\"([^\"]*)\""#, in: xml).first ?? ""
        return raw
            .split(separator: " ")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func firstFieldEntry(afterFieldLabel label: String, in xml: String) -> String? {
        // Most field entries are plain text; the formula_question entry carries
        // embedded XML (`<formula>…<variables>…</variables></formula>`), so we
        // match lazily up to the next `</fieldentry>` rather than the first `<`.
        let pattern = #"<fieldlabel>\#(label)</fieldlabel>\s*<fieldentry>([\s\S]*?)</fieldentry>"#
        return matches(pattern: pattern, in: xml).first
    }

    private func classicFeedback(in xml: String) -> String {
        renderField(matches(pattern: #"<itemfeedback[\s\S]*?<mattext[^>]*>([\s\S]*?)</mattext>"#, in: xml).first ?? "")
    }

    private func qti21Feedback(in xml: String) -> String {
        renderField(matches(pattern: #"<modalFeedback[^>]*>([\s\S]*?)</modalFeedback>"#, in: xml).first ?? "")
    }

    private func attribute(_ name: String, in xml: String) -> String? {
        matches(pattern: #"\#(name)\s*=\s*\"([^\"]*)\""#, in: xml).first
    }

    /// Returns the first full match (group 0) of a regex against the given XML,
    /// or `nil` if there is no match. Used to detect optional elements like
    /// formula response templates where a single substring test isn't enough.
    private func firstMatch(pattern: String, in xml: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard let match = regex.firstMatch(in: xml, range: range),
              let range = Range(match.range, in: xml) else { return nil }
        return String(xml[range])
    }

    /// Rebuilds a classic matching item's prompt/match pairs. Canvas lists every
    /// right-side option inside each prompt's render_choice and keeps the answer
    /// key in resprocessing, so the correct option has to come from the varequal
    /// for that response_lid. Survey exports omit resprocessing entirely (nothing
    /// is scored); pair each prompt with the option at its own position so the
    /// author still gets a full, editable set of pairs.
    private func classicMatchingPairs(in xml: String) -> [MatchingPair] {
        let answerKey = Dictionary(
            matches(pattern: #"<varequal[^>]*respident\s*=\s*\"([^\"]+)\"[^>]*>([^<]+)</varequal>"#, in: xml, groupCount: 2)
                .map { ($0[0], $0[1].trimmingCharacters(in: .whitespacesAndNewlines)) },
            uniquingKeysWith: { first, _ in first }
        )

        let lidBlocks = matches(pattern: #"<response_lid\s+ident=\"([^\"]+)\"[^>]*>([\s\S]*?)</response_lid>"#, in: xml, groupCount: 2)
        return lidBlocks.enumerated().compactMap { index, block in
            let (lidIdent, body) = (block[0], block[1])
            guard let promptText = matches(pattern: #"<material><mattext[^>]*>([\s\S]*?)</mattext>"#, in: body).first else { return nil }

            let options = matches(pattern: #"<response_label\s+ident=\"([^\"]+)\"[^>]*>\s*<material><mattext[^>]*>([\s\S]*?)</mattext>"#, in: body, groupCount: 2)
            let keyed = answerKey[lidIdent].flatMap { correctID in options.first { $0[0] == correctID } }
            let positional = index < options.count ? options[index] : options.first
            let match = keyed ?? positional

            return MatchingPair(prompt: renderField(promptText), match: renderField(match?[1] ?? ""))
        }
    }

    private func matches(pattern: String, in text: String) -> [String] {
        matches(pattern: pattern, in: text, groupCount: 1).map { $0[0] }
    }

    private func matches(pattern: String, in text: String, groupCount: Int) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > groupCount else { return nil }
            return (1...groupCount).compactMap { index in
                guard let range = Range(match.range(at: index), in: text) else { return nil }
                return String(text[range])
            }
        }
    }

    private func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seenValues: Set<String> = []
        var uniqueValues: [String] = []

        for value in values where !seenValues.contains(value) {
            seenValues.insert(value)
            uniqueValues.append(value)
        }

        return uniqueValues
    }
}

func xmlUnescape(_ value: String) -> String {
    // Numeric references decode first so that an escaped ampersand sequence like
    // "&amp;#x27;" survives as the literal text "&#x27;" rather than collapsing
    // into an apostrophe. For the same reason "&amp;" is replaced last.
    decodeNumericCharacterReferences(in: value)
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&apos;", with: "'")
        .replacingOccurrences(of: "&amp;", with: "&")
}

/// Decodes `&#39;` and `&#x27;` style references, which Canvas uses for
/// apostrophes and smart quotes instead of the named entities. Anything that
/// isn't a well-formed reference to a valid scalar is left exactly as written.
private func decodeNumericCharacterReferences(in value: String) -> String {
    guard value.contains("&#") else { return value }

    var result = ""
    var remainder = Substring(value)

    while let start = remainder.range(of: "&#") {
        result.append(contentsOf: remainder[remainder.startIndex..<start.lowerBound])
        let afterMarker = start.upperBound

        guard let end = remainder[afterMarker...].firstIndex(of: ";") else {
            // No terminator left in the string, so nothing further can decode.
            result.append(contentsOf: remainder[start.lowerBound...])
            return result
        }

        var digits = remainder[afterMarker..<end]
        var radix = 10
        if let first = digits.first, first == "x" || first == "X" {
            radix = 16
            digits = digits.dropFirst()
        }

        if !digits.isEmpty,
           let code = UInt32(digits, radix: radix),
           let scalar = Unicode.Scalar(code) {
            result.append(Character(scalar))
        } else {
            result.append(contentsOf: remainder[start.lowerBound...end])
        }

        remainder = remainder[remainder.index(after: end)...]
    }

    result.append(contentsOf: remainder)
    return result
}
