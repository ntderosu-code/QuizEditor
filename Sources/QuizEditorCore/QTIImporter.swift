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
    public enum ImportError: Error, Equatable, CustomStringConvertible {
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

        var questions = itemPaths.compactMap { path -> QuizQuestion? in
            let itemURL = directoryURL.appendingPathComponent(path)
            guard let xml = try? String(contentsOf: itemURL, encoding: .utf8) else { return nil }
            return parseItem(xml)
        }

        // Many QTI packages (e.g. Canvas classic exports) embed every <item>
        // inline in a single assessment file instead of one file per question.
        // When no separate item files were referenced, parse the inline items.
        if questions.isEmpty {
            questions = inlineItems(in: assessment).compactMap { parseItem($0) }
        }

        guard !questions.isEmpty else { throw ImportError.noQuestionsFound }
        return Quiz(title: title.isEmpty ? "Imported Quiz" : title, questions: questions)
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

        // Scan every XML file the manifest references; keep the ones that actually
        // contain questions (assessments and objectbanks), skipping pages/settings.
        let xmlHrefs = uniquePreservingOrder(hrefs(in: manifest).filter { $0.hasSuffix(".xml") })
        var sections: [QTISection] = []
        for href in xmlHrefs {
            let fileURL = directoryURL.appendingPathComponent(href)
            guard let xml = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let questions = extractItems(from: xml).compactMap { parseItem($0) }
            guard !questions.isEmpty else { continue }
            let kind: QTISection.Kind = xml.contains("<objectbank") ? .questionBank : .assessment
            sections.append(QTISection(title: sectionTitle(in: xml, fallback: href), kind: kind, questions: questions))
        }

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
            let pairs = matches(pattern: #"<response_lid[^>]*>\s*<material><mattext[^>]*>([\s\S]*?)</mattext></material>[\s\S]*?<response_label[^>]*>\s*<material><mattext[^>]*>([\s\S]*?)</mattext>"#, in: xml, groupCount: 2)
                .map { MatchingPair(prompt: renderField($0[0]), match: renderField($0[1])) }
            return QuizQuestion(type: .matching, prompt: prompt, matches: pairs, feedback: classicFeedback(in: xml))
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

        let correctResponse = matches(pattern: #"<correctResponse>([\s\S]*?)</correctResponse>"#, in: xml).first ?? ""
        let correctIDs = Set(matches(pattern: #"<value>([^<]+)</value>"#, in: correctResponse))
        let choices = matches(pattern: #"<simpleChoice\s+identifier=\"([^\"]+)\"[^>]*>([\s\S]*?)</simpleChoice>"#, in: xml, groupCount: 2)
        let answers = choices.map { QuizAnswer(text: renderField($0[1]), isCorrect: correctIDs.contains($0[0])) }
        let cardinality = attribute("cardinality", in: xml)
        let type: QuizQuestionType = cardinality == "multiple" ? .multipleAnswer : .multipleChoice
        return QuizQuestion(type: answers.isEmpty ? .essay : type, prompt: prompt, answers: answers, feedback: qti21Feedback(in: xml))
    }

    private func questionType(canvasType: String?) -> QuizQuestionType {
        switch canvasType {
        case "multiple_answers_question": return .multipleAnswer
        case "true_false_question": return .trueFalse
        case "fill_in_the_blank_question": return .fillInBlank
        case "short_answer_question": return .shortAnswer
        case "essay_question": return .essay
        case "matching_question": return .matching
        default: return .multipleChoice
        }
    }

    private func firstFieldEntry(afterFieldLabel label: String, in xml: String) -> String? {
        let pattern = #"<fieldlabel>\#(label)</fieldlabel>\s*<fieldentry>([^<]+)</fieldentry>"#
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
    value
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&apos;", with: "'")
        .replacingOccurrences(of: "&amp;", with: "&")
}
