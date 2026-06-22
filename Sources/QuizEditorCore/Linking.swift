import Foundation

/// The linking model (issue #23). Questions gain first-class links to learning
/// objectives, competencies/standards, a reusable case scenario/stimulus, and
/// source materials — authored once on the quiz, referenced by many items, and
/// consumed by both the linter and (later) the AI. Every type decodes tolerantly,
/// mirroring `QuizQuestion`, so quizzes saved against an older schema keep loading.
///
/// All of this is author metadata: it persists through save/open but is never
/// written into QTI/Common Cartridge exports.

/// Bloom's cognitive level for a learning objective. Drives the recall-drift
/// linter check (an apply/analyze+ objective whose item only asks for recall).
public enum CognitiveLevel: String, CaseIterable, Codable, Identifiable, Sendable {
    case remember
    case understand
    case apply
    case analyze
    case evaluate
    case create

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .remember: "Remember"
        case .understand: "Understand"
        case .apply: "Apply"
        case .analyze: "Analyze"
        case .evaluate: "Evaluate"
        case .create: "Create"
        }
    }

    /// Levels that expect more than recall, so a recall-only stem is a mismatch.
    public var isHigherOrder: Bool {
        switch self {
        case .remember, .understand: false
        case .apply, .analyze, .evaluate, .create: true
        }
    }
}

public struct LearningObjective: Equatable, Codable, Identifiable, Sendable {
    public var id: String
    public var text: String
    public var cognitiveLevel: CognitiveLevel?

    public init(id: String = UUID().uuidString, text: String = "", cognitiveLevel: CognitiveLevel? = nil) {
        self.id = id
        self.text = text
        self.cognitiveLevel = cognitiveLevel
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        cognitiveLevel = try c.decodeIfPresent(CognitiveLevel.self, forKey: .cognitiveLevel)
    }

    private enum CodingKeys: String, CodingKey { case id, text, cognitiveLevel }
}

/// The kind of a reusable stimulus: one stimulus, many questions (the NGN
/// unfolding case, a DBQ document cluster, a multi-part physics problem, a
/// code-reuse set).
public enum StimulusKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case caseStudy = "case"
    case vignette
    case dataset
    case code
    case passage
    case figure

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .caseStudy: "Case"
        case .vignette: "Vignette"
        case .dataset: "Dataset"
        case .code: "Code"
        case .passage: "Passage"
        case .figure: "Figure"
        }
    }
}

/// A reusable case/vignette/passage/figure authored once and attached to many
/// items; its alt text and data table live in one place. A figure's alt text is
/// required (enforced in the UI) so accessibility never depends on the author
/// remembering it per question.
public struct Stimulus: Equatable, Codable, Identifiable, Sendable {
    public var id: String
    public var kind: StimulusKind
    public var body: String
    /// A base64 data URI for an attached figure, or nil. Stored inline so the
    /// document stays a single self-contained file.
    public var figureImage: String?
    public var altText: String?
    public var dataTable: String?

    public init(
        id: String = UUID().uuidString,
        kind: StimulusKind = .vignette,
        body: String = "",
        figureImage: String? = nil,
        altText: String? = nil,
        dataTable: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.body = body
        self.figureImage = figureImage
        self.altText = altText
        self.dataTable = dataTable
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        kind = try c.decodeIfPresent(StimulusKind.self, forKey: .kind) ?? .vignette
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        figureImage = try c.decodeIfPresent(String.self, forKey: .figureImage)
        altText = try c.decodeIfPresent(String.self, forKey: .altText)
        dataTable = try c.decodeIfPresent(String.self, forKey: .dataTable)
    }

    private enum CodingKeys: String, CodingKey { case id, kind, body, figureImage, altText, dataTable }

    /// A figure with no alt text is the one accessibility gap the linker should
    /// surface; convenient for both UI validation and a future platform rule.
    public var figureNeedsAltText: Bool {
        figureImage != nil && (altText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum SourceType: String, CaseIterable, Codable, Identifiable, Sendable {
    case primary
    case secondary
    case guideline
    case labeling

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .primary: "Primary"
        case .secondary: "Secondary"
        case .guideline: "Guideline"
        case .labeling: "Labeling"
        }
    }
}

/// A source material an item can cite. Drives attribution linters and (later) the
/// AI "defer to the linked source" clause.
public struct Source: Equatable, Codable, Identifiable, Sendable {
    public var id: String
    public var author: String
    public var date: String
    public var place: String
    public var type: SourceType?
    public var citation: String

    public init(
        id: String = UUID().uuidString,
        author: String = "",
        date: String = "",
        place: String = "",
        type: SourceType? = nil,
        citation: String = ""
    ) {
        self.id = id
        self.author = author
        self.date = date
        self.place = place
        self.type = type
        self.citation = citation
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        place = try c.decodeIfPresent(String.self, forKey: .place) ?? ""
        type = try c.decodeIfPresent(SourceType.self, forKey: .type)
        citation = try c.decodeIfPresent(String.self, forKey: .citation) ?? ""
    }

    private enum CodingKeys: String, CodingKey { case id, author, date, place, type, citation }

    /// A short label for chips and pickers.
    public var shortLabel: String {
        let trimmedCitation = citation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCitation.isEmpty { return trimmedCitation }
        let parts = [author, date].filter { !$0.isEmpty }
        return parts.isEmpty ? "Untitled source" : parts.joined(separator: ", ")
    }
}
