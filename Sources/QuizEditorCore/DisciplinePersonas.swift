import Foundation

/// Phase 4 discipline packs (#19). Each pack is a built-in `Persona` — pure data
/// configuring the engine built in Phases 0–3 (declarative linter rules, the
/// terminology lexicon, recall-drift / competency / numeric-unit gates, persona AI
/// prompting, item-type defaults, and linking/framework presets). They ship as
/// value constants (no launch-time disk read or JSON parsing), and stay read-only,
/// forkable, and exportable like any persona.
public extension Persona {
    /// The built-in discipline packs, surfaced alongside General. Phase 2 (#89)
    /// deliberately ships a short, well-verified roster; the wider Phase 4 set
    /// lives in git history and can return one pack at a time as each is vetted.
    static let builtInDisciplines: [Persona] = [
        .nursing, .medicine, .pharmacy, .socialWork, .biology
    ]

    // ISMP/Joint Commission error-prone abbreviations, shared by health packs. The
    // lexicon scanner flags these across stem, options, and feedback.
    private static let bannedAbbreviations: [PersonaTerminologyRule] = [
        PersonaTerminologyRule(preferred: "every day", discouraged: ["QD"], rationale: "“QD” is an ISMP error-prone abbreviation."),
        PersonaTerminologyRule(preferred: "every other day", discouraged: ["QOD"], rationale: "“QOD” is an ISMP error-prone abbreviation."),
        PersonaTerminologyRule(preferred: "units", discouraged: ["U", "IU"], rationale: "“U”/“IU” can be misread as 0 or IV."),
        PersonaTerminologyRule(preferred: "morphine sulfate", discouraged: ["MS", "MSO4"], rationale: "“MS”/“MSO4” are on the Joint Commission Do Not Use list — spell out morphine sulfate."),
        PersonaTerminologyRule(preferred: "magnesium sulfate", discouraged: ["MgSO4"], rationale: "“MgSO4” is on the Joint Commission Do Not Use list and is easily confused with MSO4 — spell out magnesium sulfate."),
        PersonaTerminologyRule(preferred: "mL", discouraged: ["cc"], rationale: "Use mL, not cc.")
    ]

    // MARK: - Nursing

    static let nursing = Persona(
        id: "app.quizeditor.persona.nursing",
        displayName: "Nursing",
        family: "health",
        summary: "NCLEX/NGN clinical-judgment item writing: vignette-anchored priority items, SATA hygiene, safe medication language, and per-option rationale.",
        linterProfile: PersonaLinterProfile(
            declarativeRules: [
                PersonaLinterRule(
                    id: "sataCountCue",
                    scope: "stem",
                    forbidsPattern: "(?i)\\b(select|choose)\\b.{0,14}\\b(two|three|four|2|3|4)\\b|\\bwhich (two|three)\\b",
                    itemTypes: [.multipleAnswer],
                    severity: .warning,
                    message: "The stem cues how many options are correct.",
                    suggestion: "Remove the count; let each option be judged independently."
                ),
                PersonaLinterRule(
                    id: "priorityItemNeedsPlausibleOptions",
                    scope: "stem",
                    forbidsPattern: "(?i)\\b(priority|first|best|most important|initial)\\b",
                    itemTypes: [.multipleChoice, .multipleAnswer],
                    severity: .suggestion,
                    message: "This is a priority item.",
                    suggestion: "Make every option a safe, plausible nursing action so only clinical judgment — not elimination — yields the key."
                )
            ],
            checksRecallDrift: true
        ),
        aiProfile: PersonaAIProfile(
            systemPreamble: "Adopt the perspective of a nurse educator writing NCLEX/NGN items. Apply the NCSBN Clinical Judgment Measurement Model's six cognitive skills — recognize cues, analyze cues, prioritize hypotheses, generate solutions, take action, evaluate outcomes — at the application/analysis level, set inside a patient vignette.",
            reviewGuidelines: [
                "Every option is a safe, plausible nursing action; exactly one is the highest priority.",
                "The item is anchored in a vignette with concrete cues (age, vitals, labs, history).",
                "Feedback gives the keyed rationale and why each distractor is lower priority or unsafe."
            ],
            authoringGuidelines: [
                "Write a vignette stem with relevant cues before the question.",
                "For SATA, keep options independent and never cue how many are correct."
            ],
            feedbackGuidelines: ["Name the priority framework behind the key (ABCs, Maslow, acute vs chronic)."],
            distractorStrategy: "Plausible but lower-priority or contraindicated nursing actions based on common misconceptions.",
            safetyClauses: [
                "Never invent drug doses, lab values, or guideline citations.",
                "Never use error-prone abbreviations (QD, QOD, U, IU, MS, MSO4, MgSO4, cc); spell them out."
            ],
            labelsMisconceptions: true
        ),
        itemTypeProfile: PersonaItemTypeProfile(defaultType: .multipleChoice, preferredTypes: [.multipleChoice, .multipleAnswer, .fillInBlank, .matching]),
        terminology: bannedAbbreviations + [
            PersonaTerminologyRule(preferred: "client with diabetes", discouraged: ["diabetic"], rationale: "Use person-first language.")
        ],
        exemplars: [
            "A 72-year-old client is 6 hours post-op from a total hip arthroplasty. BP 98/60, HR 112, SpO2 92% on room air, reporting new calf pain. Which action is the priority?"
        ],
        linkingPresets: PersonaLinkingPresets(
            competencyFrameworks: ["NCLEX Client Needs", "NCSBN CJMM"],
            suggestObjectiveLink: true, suggestSourceLink: true, suggestCaseLink: true
        ),
        isBuiltIn: true
    )

    // MARK: - Medicine

    static let medicine = Persona(
        id: "app.quizeditor.persona.medicine",
        displayName: "Medicine",
        family: "health",
        summary: "Board-style single-best-answer items: clinical vignettes, one most-defensible key, emphasized negative lead-ins, and guideline-anchored facts.",
        linterProfile: PersonaLinterProfile(
            ruleOverrides: ["unemphasizedNegativeStem": PersonaRuleOverride(severity: .warning)],
            checksRecallDrift: true
        ),
        aiProfile: PersonaAIProfile(
            systemPreamble: "Adopt the perspective of a physician educator writing board-style single-best-answer items. Use a clinical vignette; exactly one option is the most defensible answer.",
            reviewGuidelines: [
                "The stem is a vignette with the data needed to reason to one best answer.",
                "Distractors are look-alike conditions or common diagnostic confusions, all plausible."
            ],
            distractorStrategy: "Common diagnostic confusions and look-alike conditions for the vignette.",
            safetyClauses: ["Never invent doses, statistics, or guideline citations; defer to the linked source."],
            labelsMisconceptions: true
        ),
        itemTypeProfile: PersonaItemTypeProfile(defaultType: .multipleChoice, preferredTypes: [.multipleChoice]),
        terminology: [
            PersonaTerminologyRule(preferred: "associated with", discouraged: ["causes"], rationale: "Most board items describe association, not proven causation."),
            PersonaTerminologyRule(preferred: "acetaminophen", discouraged: ["Tylenol"], rationale: "Use the generic (nonproprietary) drug name."),
            PersonaTerminologyRule(preferred: "ibuprofen", discouraged: ["Advil", "Motrin"], rationale: "Use the generic (nonproprietary) drug name.")
        ],
        linkingPresets: PersonaLinkingPresets(suggestObjectiveLink: true, suggestSourceLink: true),
        isBuiltIn: true
    )

    // MARK: - Pharmacy

    static let pharmacy = Persona(
        id: "app.quizeditor.persona.pharmacy",
        displayName: "Pharmacy",
        family: "health",
        summary: "Calculation-safe, therapeutics-focused items: units on every quantity, generic drug names, and safe medication language.",
        linterProfile: PersonaLinterProfile(
            checksRecallDrift: true,
            requiresNumericUnit: true
        ),
        aiProfile: PersonaAIProfile(
            systemPreamble: "Adopt the perspective of a pharmacist educator. Emphasize calculation safety and therapeutics; show units on every quantity.",
            reviewGuidelines: ["Every numeric quantity carries an explicit unit.", "Calculation items state the available concentration and the order clearly."],
            distractorStrategy: "Common calculation errors — decimal shifts, unit-conversion slips, and using the wrong concentration.",
            safetyClauses: ["Never invent doses or concentrations.", "Never use error-prone abbreviations; spell them out."],
            labelsMisconceptions: true
        ),
        itemTypeProfile: PersonaItemTypeProfile(defaultType: .numeric, preferredTypes: [.numeric, .multipleChoice, .fillInBlank]),
        terminology: bannedAbbreviations,
        linkingPresets: PersonaLinkingPresets(suggestSourceLink: true),
        isBuiltIn: true
    )

    // MARK: - Social Work

    static let socialWork = Persona(
        id: "app.quizeditor.persona.social-work",
        displayName: "Social Work",
        family: "social-science",
        summary: "Scenario-based professional-judgment items anchored to CSWE EPAS competencies and the NASW ethics, in person-first, anti-oppressive language.",
        linterProfile: PersonaLinterProfile(requiresCompetency: true),
        aiProfile: PersonaAIProfile(
            systemPreamble: "Adopt the perspective of a social work educator. Write practice-scenario items that exercise professional judgment, grounded in the CSWE EPAS competencies and the NASW Code of Ethics, using person-first, anti-oppressive language.",
            reviewGuidelines: [
                "Use person-first, non-stigmatizing language throughout.",
                "Anchor the item in a practice scenario and map it to an EPAS competency.",
                "Do not pathologize or stereotype the populations described."
            ],
            safetyClauses: ["Never stereotype or pathologize a client population."]
        ),
        itemTypeProfile: PersonaItemTypeProfile(defaultType: .multipleChoice, preferredTypes: [.multipleChoice, .essay]),
        terminology: [
            PersonaTerminologyRule(preferred: "person with a substance use disorder", discouraged: ["addict", "substance abuser", "junkie"], rationale: "Use person-first language."),
            PersonaTerminologyRule(preferred: "person experiencing homelessness", discouraged: ["the homeless", "homeless person"], rationale: "Use person-first language."),
            PersonaTerminologyRule(preferred: "person with a disability", discouraged: ["the disabled", "handicapped"], rationale: "Use person-first language."),
            PersonaTerminologyRule(preferred: "person with mental illness", discouraged: ["the mentally ill", "crazy"], rationale: "Use person-first, non-stigmatizing language.")
        ],
        linkingPresets: PersonaLinkingPresets(
            competencyFrameworks: ["CSWE EPAS"],
            suggestObjectiveLink: true, suggestSourceLink: true
        ),
        isBuiltIn: true
    )

    // MARK: - Biology

    static let biology = Persona(
        id: "app.quizeditor.persona.biology",
        displayName: "Biology",
        family: "science",
        summary: "Experimental-reasoning and data-interpretation items: evidence supports rather than proves, and claims are tied to data.",
        aiProfile: PersonaAIProfile(
            systemPreamble: "Adopt the perspective of a biology educator. Favor experimental-reasoning and data-interpretation items: present data or an experiment and ask the candidate to draw an evidence-supported conclusion.",
            reviewGuidelines: ["Tie every claim to the presented data.", "Say evidence supports a conclusion; avoid saying it proves one."],
            distractorStrategy: "Common reasoning errors: over-generalizing from data, confusing correlation with causation, ignoring controls.",
            labelsMisconceptions: true
        ),
        itemTypeProfile: PersonaItemTypeProfile(defaultType: .multipleChoice, preferredTypes: [.multipleChoice, .multipleAnswer]),
        terminology: [
            PersonaTerminologyRule(preferred: "the data support", discouraged: ["proves", "proven"], rationale: "Empirical evidence supports conclusions; it rarely proves them.")
        ],
        linkingPresets: PersonaLinkingPresets(suggestSourceLink: true, suggestCaseLink: true),
        isBuiltIn: true
    )
}
