import Foundation

/// A discipline persona bakes a field's quiz-authoring best practices into the
/// editor. In this first (foundation) phase a persona is pure, inert data: it
/// exists, can be selected, and persists, but nothing yet consumes its profiles,
/// so behavior is unchanged. Later phases read the linter, AI, item-type, and
/// linking profiles to shape the experience.
///
/// Every field decodes with `decodeIfPresent`/defaults, mirroring
/// `QuizQuestion.init(from:)`, so a persona saved against an older schema keeps
/// loading as the schema grows.
public struct Persona: Codable, Sendable, Identifiable, Equatable {
    /// Reverse-DNS identifier, e.g. `app.quizeditor.persona.general`.
    public var id: String
    public var displayName: String
    /// One of: general, health, science, stem, social-science, humanities.
    public var family: String
    public var version: Int
    public var summary: String
    /// When set, this persona extends another; `PersonaResolver` merges them.
    public var basePersonaID: String?
    public var linterProfile: PersonaLinterProfile
    public var aiProfile: PersonaAIProfile
    public var itemTypeProfile: PersonaItemTypeProfile
    public var terminology: [PersonaTerminologyRule]
    public var exemplars: [String]
    public var linkingPresets: PersonaLinkingPresets
    /// True for personas shipped with the app; user personas are false.
    public var isBuiltIn: Bool

    public init(
        id: String,
        displayName: String,
        family: String = "general",
        version: Int = 1,
        summary: String = "",
        basePersonaID: String? = nil,
        linterProfile: PersonaLinterProfile = .init(),
        aiProfile: PersonaAIProfile = .init(),
        itemTypeProfile: PersonaItemTypeProfile = .init(),
        terminology: [PersonaTerminologyRule] = [],
        exemplars: [String] = [],
        linkingPresets: PersonaLinkingPresets = .init(),
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.family = family
        self.version = version
        self.summary = summary
        self.basePersonaID = basePersonaID
        self.linterProfile = linterProfile
        self.aiProfile = aiProfile
        self.itemTypeProfile = itemTypeProfile
        self.terminology = terminology
        self.exemplars = exemplars
        self.linkingPresets = linkingPresets
        self.isBuiltIn = isBuiltIn
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, family, version, summary, basePersonaID
        case linterProfile, aiProfile, itemTypeProfile, terminology, exemplars, linkingPresets, isBuiltIn
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // id and displayName are required; everything else falls back to a default.
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        family = try container.decodeIfPresent(String.self, forKey: .family) ?? "general"
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        basePersonaID = try container.decodeIfPresent(String.self, forKey: .basePersonaID)
        linterProfile = try container.decodeIfPresent(PersonaLinterProfile.self, forKey: .linterProfile) ?? .init()
        aiProfile = try container.decodeIfPresent(PersonaAIProfile.self, forKey: .aiProfile) ?? .init()
        itemTypeProfile = try container.decodeIfPresent(PersonaItemTypeProfile.self, forKey: .itemTypeProfile) ?? .init()
        terminology = try container.decodeIfPresent([PersonaTerminologyRule].self, forKey: .terminology) ?? []
        exemplars = try container.decodeIfPresent([String].self, forKey: .exemplars) ?? []
        linkingPresets = try container.decodeIfPresent(PersonaLinkingPresets.self, forKey: .linkingPresets) ?? .init()
        isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
    }
}

// MARK: - Profiles

public enum PersonaSeverity: String, Codable, Sendable, Equatable {
    case suggestion
    case warning
}

/// An override of a built-in linter rule: turn it off, or change its severity.
public struct PersonaRuleOverride: Codable, Sendable, Equatable {
    public var enabled: Bool?
    public var severity: PersonaSeverity?

    public init(enabled: Bool? = nil, severity: PersonaSeverity? = nil) {
        self.enabled = enabled
        self.severity = severity
    }
}

/// A discipline-specific linter rule expressed as data. The fields are carried now
/// but not yet evaluated; the declarative engine that consumes them lands in the
/// linter-extensions phase.
public struct PersonaLinterRule: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    /// Where to look: stem, options, or feedback.
    public var scope: String
    /// A token/regex that must be present (nil = no requirement). The rule fires
    /// when this pattern is ABSENT from the scoped text.
    public var requiresPattern: String?
    /// A token/regex that must be absent (nil = no prohibition). The rule fires
    /// when this pattern is PRESENT in the scoped text.
    public var forbidsPattern: String?
    /// Gate: only evaluate for these item types (empty = all types).
    public var itemTypes: [QuizQuestionType]
    /// Gate: only evaluate at these difficulties (empty = any/unspecified).
    public var difficulties: [QuizDifficulty]
    /// Link trigger: fires when the question has NO linked stimulus (issue #23),
    /// e.g. "a clinical-judgment item lacks a vignette."
    public var requiresStimulus: Bool
    /// Link trigger: fires when the question links NO source (issue #23), e.g.
    /// "a source-based item lacks attribution."
    public var requiresSource: Bool
    public var severity: PersonaSeverity
    public var message: String
    public var suggestion: String

    public init(
        id: String,
        scope: String = "stem",
        requiresPattern: String? = nil,
        forbidsPattern: String? = nil,
        itemTypes: [QuizQuestionType] = [],
        difficulties: [QuizDifficulty] = [],
        requiresStimulus: Bool = false,
        requiresSource: Bool = false,
        severity: PersonaSeverity = .suggestion,
        message: String,
        suggestion: String
    ) {
        self.id = id
        self.scope = scope
        self.requiresPattern = requiresPattern
        self.forbidsPattern = forbidsPattern
        self.itemTypes = itemTypes
        self.difficulties = difficulties
        self.requiresStimulus = requiresStimulus
        self.requiresSource = requiresSource
        self.severity = severity
        self.message = message
        self.suggestion = suggestion
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        scope = try c.decodeIfPresent(String.self, forKey: .scope) ?? "stem"
        requiresPattern = try c.decodeIfPresent(String.self, forKey: .requiresPattern)
        forbidsPattern = try c.decodeIfPresent(String.self, forKey: .forbidsPattern)
        itemTypes = try c.decodeIfPresent([QuizQuestionType].self, forKey: .itemTypes) ?? []
        difficulties = try c.decodeIfPresent([QuizDifficulty].self, forKey: .difficulties) ?? []
        requiresStimulus = try c.decodeIfPresent(Bool.self, forKey: .requiresStimulus) ?? false
        requiresSource = try c.decodeIfPresent(Bool.self, forKey: .requiresSource) ?? false
        severity = try c.decodeIfPresent(PersonaSeverity.self, forKey: .severity) ?? .suggestion
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        suggestion = try c.decodeIfPresent(String.self, forKey: .suggestion) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, scope, requiresPattern, forbidsPattern, itemTypes, difficulties
        case requiresStimulus, requiresSource, severity, message, suggestion
    }
}

public struct PersonaLinterProfile: Codable, Sendable, Equatable {
    /// Built-in rule id → override. Built-in ids match `LintFinding.Rule`.
    public var ruleOverrides: [String: PersonaRuleOverride]
    public var declarativeRules: [PersonaLinterRule]
    /// Enables the shared recall-drift primitive (issue #23): flag an item linked
    /// to a higher-order objective whose stem only asks for recall.
    public var checksRecallDrift: Bool
    /// Opt-in gate (#25): flag an item that links no competency/standard.
    public var requiresCompetency: Bool

    public init(
        ruleOverrides: [String: PersonaRuleOverride] = [:],
        declarativeRules: [PersonaLinterRule] = [],
        checksRecallDrift: Bool = false,
        requiresCompetency: Bool = false
    ) {
        self.ruleOverrides = ruleOverrides
        self.declarativeRules = declarativeRules
        self.checksRecallDrift = checksRecallDrift
        self.requiresCompetency = requiresCompetency
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ruleOverrides = try c.decodeIfPresent([String: PersonaRuleOverride].self, forKey: .ruleOverrides) ?? [:]
        declarativeRules = try c.decodeIfPresent([PersonaLinterRule].self, forKey: .declarativeRules) ?? []
        checksRecallDrift = try c.decodeIfPresent(Bool.self, forKey: .checksRecallDrift) ?? false
        requiresCompetency = try c.decodeIfPresent(Bool.self, forKey: .requiresCompetency) ?? false
    }

    private enum CodingKeys: String, CodingKey { case ruleOverrides, declarativeRules, checksRecallDrift, requiresCompetency }
}

/// Guidance the AI features will fold into their prompts. Inert until the
/// AI-prompting phase reads it.
public struct PersonaAIProfile: Codable, Sendable, Equatable {
    public var systemPreamble: String
    public var reviewGuidelines: [String]
    public var authoringGuidelines: [String]
    public var feedbackGuidelines: [String]
    public var distractorStrategy: String?
    public var tone: String?
    public var safetyClauses: [String]
    public var temperatureOverride: Double?

    public init(
        systemPreamble: String = "",
        reviewGuidelines: [String] = [],
        authoringGuidelines: [String] = [],
        feedbackGuidelines: [String] = [],
        distractorStrategy: String? = nil,
        tone: String? = nil,
        safetyClauses: [String] = [],
        temperatureOverride: Double? = nil
    ) {
        self.systemPreamble = systemPreamble
        self.reviewGuidelines = reviewGuidelines
        self.authoringGuidelines = authoringGuidelines
        self.feedbackGuidelines = feedbackGuidelines
        self.distractorStrategy = distractorStrategy
        self.tone = tone
        self.safetyClauses = safetyClauses
        self.temperatureOverride = temperatureOverride
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        systemPreamble = try c.decodeIfPresent(String.self, forKey: .systemPreamble) ?? ""
        reviewGuidelines = try c.decodeIfPresent([String].self, forKey: .reviewGuidelines) ?? []
        authoringGuidelines = try c.decodeIfPresent([String].self, forKey: .authoringGuidelines) ?? []
        feedbackGuidelines = try c.decodeIfPresent([String].self, forKey: .feedbackGuidelines) ?? []
        distractorStrategy = try c.decodeIfPresent(String.self, forKey: .distractorStrategy)
        tone = try c.decodeIfPresent(String.self, forKey: .tone)
        safetyClauses = try c.decodeIfPresent([String].self, forKey: .safetyClauses) ?? []
        temperatureOverride = try c.decodeIfPresent(Double.self, forKey: .temperatureOverride)
    }

    private enum CodingKeys: String, CodingKey {
        case systemPreamble, reviewGuidelines, authoringGuidelines, feedbackGuidelines
        case distractorStrategy, tone, safetyClauses, temperatureOverride
    }
}

public struct PersonaItemTypeProfile: Codable, Sendable, Equatable {
    public var defaultType: QuizQuestionType?
    public var preferredTypes: [QuizQuestionType]

    public init(defaultType: QuizQuestionType? = nil, preferredTypes: [QuizQuestionType] = []) {
        self.defaultType = defaultType
        self.preferredTypes = preferredTypes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultType = try c.decodeIfPresent(QuizQuestionType.self, forKey: .defaultType)
        preferredTypes = try c.decodeIfPresent([QuizQuestionType].self, forKey: .preferredTypes) ?? []
    }

    private enum CodingKeys: String, CodingKey { case defaultType, preferredTypes }
}

/// A preferred-term / discouraged-terms pairing (e.g. prefer "associated with"
/// over "causes"). Consumed later by a lexicon-based linter check.
public struct PersonaTerminologyRule: Codable, Sendable, Equatable {
    public var preferred: String
    public var discouraged: [String]
    public var rationale: String?

    public init(preferred: String, discouraged: [String] = [], rationale: String? = nil) {
        self.preferred = preferred
        self.discouraged = discouraged
        self.rationale = rationale
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preferred = try c.decodeIfPresent(String.self, forKey: .preferred) ?? ""
        discouraged = try c.decodeIfPresent([String].self, forKey: .discouraged) ?? []
        rationale = try c.decodeIfPresent(String.self, forKey: .rationale)
    }

    private enum CodingKeys: String, CodingKey { case preferred, discouraged, rationale }
}

/// Which kinds of links a discipline tends to want suggested. Inert until the
/// linking phase reads it.
public struct PersonaLinkingPresets: Codable, Sendable, Equatable {
    public var competencyFrameworks: [String]
    public var suggestObjectiveLink: Bool
    public var suggestSourceLink: Bool
    public var suggestCaseLink: Bool

    public init(
        competencyFrameworks: [String] = [],
        suggestObjectiveLink: Bool = false,
        suggestSourceLink: Bool = false,
        suggestCaseLink: Bool = false
    ) {
        self.competencyFrameworks = competencyFrameworks
        self.suggestObjectiveLink = suggestObjectiveLink
        self.suggestSourceLink = suggestSourceLink
        self.suggestCaseLink = suggestCaseLink
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        competencyFrameworks = try c.decodeIfPresent([String].self, forKey: .competencyFrameworks) ?? []
        suggestObjectiveLink = try c.decodeIfPresent(Bool.self, forKey: .suggestObjectiveLink) ?? false
        suggestSourceLink = try c.decodeIfPresent(Bool.self, forKey: .suggestSourceLink) ?? false
        suggestCaseLink = try c.decodeIfPresent(Bool.self, forKey: .suggestCaseLink) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case competencyFrameworks, suggestObjectiveLink, suggestSourceLink, suggestCaseLink
    }
}

// MARK: - Built-in "General"

public extension Persona {
    /// The default persona. Its profiles are intentionally empty, so resolving to
    /// General reproduces today's behavior exactly: no extra rules, no prompt
    /// changes, no defaults. It always exists, even if no other persona loads.
    static let generalID = "app.quizeditor.persona.general"

    static let general = Persona(
        id: generalID,
        displayName: "General",
        family: "general",
        version: 1,
        summary: "QuizEditor's standard item-writing guidance. A good fit for any subject, and the starting point for every discipline persona.",
        isBuiltIn: true
    )
}

// MARK: - Resolution and merging

/// Resolves a persona id (from a quiz override, the app default, or nothing) into
/// a concrete persona, merging a persona onto its `basePersonaID` parent and
/// always falling back to the built-in General so an active persona always exists.
public struct PersonaResolver: Sendable {
    private let personasByID: [String: Persona]

    public init(personas: [Persona]) {
        var map: [String: Persona] = [:]
        for persona in personas { map[persona.id] = persona }
        // General must always be resolvable, even if it was not supplied.
        if map[Persona.generalID] == nil { map[Persona.generalID] = .general }
        self.personasByID = map
    }

    /// Returns the fully merged persona for `id`, or General if `id` is nil or
    /// unknown. Resolution order is the caller's job (quiz → app default → nil).
    public func resolve(_ id: String?) -> Persona {
        guard let id, let persona = personasByID[id] else { return .general }
        return merged(persona, visiting: [])
    }

    private func merged(_ persona: Persona, visiting: Set<String>) -> Persona {
        guard
            let baseID = persona.basePersonaID,
            baseID != persona.id,
            !visiting.contains(persona.id),
            let base = personasByID[baseID]
        else {
            return persona
        }
        let resolvedBase = merged(base, visiting: visiting.union([persona.id]))
        return persona.merging(onto: resolvedBase)
    }
}

public extension Persona {
    /// Produces a persona that keeps this persona's identity but layers its profiles
    /// on top of `base`: rule overrides win per key, guideline bullets and rules
    /// append, terminology and exemplars merge, scalars prefer this persona's value.
    func merging(onto base: Persona) -> Persona {
        var result = self

        // Linter: child overrides win per rule id; declarative rules append (child wins on id).
        var overrides = base.linterProfile.ruleOverrides
        for (key, value) in linterProfile.ruleOverrides { overrides[key] = value }
        result.linterProfile = PersonaLinterProfile(
            ruleOverrides: overrides,
            declarativeRules: Persona.mergedByID(base.linterProfile.declarativeRules, linterProfile.declarativeRules),
            checksRecallDrift: base.linterProfile.checksRecallDrift || linterProfile.checksRecallDrift,
            requiresCompetency: base.linterProfile.requiresCompetency || linterProfile.requiresCompetency
        )

        // AI: scalars prefer the child when set; lists append base-then-child.
        result.aiProfile = PersonaAIProfile(
            systemPreamble: aiProfile.systemPreamble.isEmpty ? base.aiProfile.systemPreamble : aiProfile.systemPreamble,
            reviewGuidelines: base.aiProfile.reviewGuidelines + aiProfile.reviewGuidelines,
            authoringGuidelines: base.aiProfile.authoringGuidelines + aiProfile.authoringGuidelines,
            feedbackGuidelines: base.aiProfile.feedbackGuidelines + aiProfile.feedbackGuidelines,
            distractorStrategy: aiProfile.distractorStrategy ?? base.aiProfile.distractorStrategy,
            tone: aiProfile.tone ?? base.aiProfile.tone,
            safetyClauses: base.aiProfile.safetyClauses + aiProfile.safetyClauses,
            temperatureOverride: aiProfile.temperatureOverride ?? base.aiProfile.temperatureOverride
        )

        // Item types: child wins when it expresses a preference.
        result.itemTypeProfile = PersonaItemTypeProfile(
            defaultType: itemTypeProfile.defaultType ?? base.itemTypeProfile.defaultType,
            preferredTypes: itemTypeProfile.preferredTypes.isEmpty ? base.itemTypeProfile.preferredTypes : itemTypeProfile.preferredTypes
        )

        // Terminology merges by preferred term (child wins); exemplars append.
        result.terminology = Persona.mergedTerminology(base.terminology, terminology)
        result.exemplars = base.exemplars + exemplars

        // Linking: booleans OR together; frameworks union (base order first).
        var frameworks = base.linkingPresets.competencyFrameworks
        for framework in linkingPresets.competencyFrameworks where !frameworks.contains(framework) {
            frameworks.append(framework)
        }
        result.linkingPresets = PersonaLinkingPresets(
            competencyFrameworks: frameworks,
            suggestObjectiveLink: base.linkingPresets.suggestObjectiveLink || linkingPresets.suggestObjectiveLink,
            suggestSourceLink: base.linkingPresets.suggestSourceLink || linkingPresets.suggestSourceLink,
            suggestCaseLink: base.linkingPresets.suggestCaseLink || linkingPresets.suggestCaseLink
        )

        return result
    }

    private static func mergedByID(_ base: [PersonaLinterRule], _ child: [PersonaLinterRule]) -> [PersonaLinterRule] {
        var result = base
        for rule in child {
            if let index = result.firstIndex(where: { $0.id == rule.id }) {
                result[index] = rule
            } else {
                result.append(rule)
            }
        }
        return result
    }

    private static func mergedTerminology(_ base: [PersonaTerminologyRule], _ child: [PersonaTerminologyRule]) -> [PersonaTerminologyRule] {
        var result = base
        for rule in child {
            if let index = result.firstIndex(where: { $0.preferred == rule.preferred }) {
                result[index] = rule
            } else {
                result.append(rule)
            }
        }
        return result
    }
}
