import Foundation

/// Phase 4 discipline packs (#19). Each pack is a built-in `Persona` — pure data
/// configuring the engine built in Phases 0–3 (declarative linter rules, the
/// terminology lexicon, recall-drift / competency / numeric-unit gates, persona AI
/// prompting, item-type defaults, and linking/framework presets). They ship as
/// value constants (no launch-time disk read or JSON parsing), and stay read-only,
/// forkable, and exportable like any persona.
public extension Persona {
    /// The built-in discipline packs, surfaced alongside General.
    static let builtInDisciplines: [Persona] = [
        // Health
        .nursing, .medicine, .pharmacy, .publicHealth,
        // Natural sciences
        .biology, .chemistry,
        // STEM / quantitative
        .physics, .computerScience, .engineering, .mathematics, .statistics,
        // Social sciences
        .socialWork, .counseling, .economics, .law, .politicalScience, .psychology, .sociology,
        // Humanities
        .history, .literature, .philosophy
    ]

    // ISMP/Joint Commission error-prone abbreviations, shared by health packs. The
    // lexicon scanner flags these across stem, options, and feedback.
    private static let bannedAbbreviations: [PersonaTerminologyRule] = [
        PersonaTerminologyRule(preferred: "every day", discouraged: ["QD"], rationale: "“QD” is an ISMP error-prone abbreviation."),
        PersonaTerminologyRule(preferred: "every other day", discouraged: ["QOD"], rationale: "“QOD” is an ISMP error-prone abbreviation."),
        PersonaTerminologyRule(preferred: "units", discouraged: ["U", "IU"], rationale: "“U”/“IU” can be misread as 0 or IV."),
        PersonaTerminologyRule(preferred: "morphine", discouraged: ["MS", "MSO4"], rationale: "“MS”/“MSO4” are ambiguous — spell out the drug."),
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
            systemPreamble: "Adopt the perspective of a nurse educator writing NCLEX/NGN items. Apply the NCSBN Clinical Judgment Measurement Model — recognize and analyze cues, prioritize hypotheses, take and evaluate action — at the application/analysis level, set inside a patient vignette.",
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
                "Never use error-prone abbreviations (QD, QOD, U, IU, MS, MSO4, cc); spell them out."
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

    // MARK: - Public Health

    static let publicHealth = Persona(
        id: "app.quizeditor.persona.public-health",
        displayName: "Public Health",
        family: "health",
        summary: "Epidemiology/biostatistics, scenario-based: distinguishes association from causation and names the study design and measure.",
        linterProfile: PersonaLinterProfile(),
        aiProfile: PersonaAIProfile(
            systemPreamble: "Adopt the perspective of a public health educator. Write scenario-based epidemiology and biostatistics items; distinguish association from causation and name the study design.",
            reviewGuidelines: [
                "Do not imply causation from observational data.",
                "State the study design and the measure (rate, ratio, risk) the item tests."
            ],
            safetyClauses: ["Do not state or imply causation where only association is supported."]
        ),
        itemTypeProfile: PersonaItemTypeProfile(defaultType: .multipleChoice, preferredTypes: [.multipleChoice, .numeric]),
        terminology: [
            PersonaTerminologyRule(preferred: "associated with", discouraged: ["causes", "proves"], rationale: "Observational data show association, not proven causation.")
        ],
        linkingPresets: PersonaLinkingPresets(suggestObjectiveLink: true, suggestSourceLink: true),
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

    // MARK: - Natural sciences

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

    static let chemistry = Persona(
        id: "app.quizeditor.persona.chemistry",
        displayName: "Chemistry",
        family: "science",
        summary: "Quantitative, notation-aware items: units on every quantity, significant figures, and balanced equations.",
        linterProfile: PersonaLinterProfile(requiresNumericUnit: true),
        aiProfile: PersonaAIProfile(
            systemPreamble: "Adopt the perspective of a chemistry educator. Emphasize correct units, significant figures, and balanced equations; numeric answers always carry a unit.",
            reviewGuidelines: ["Every numeric quantity has an explicit unit.", "Significant figures and equation balancing are correct."],
            distractorStrategy: "Common errors: unit slips, sig-fig mistakes, unbalanced equations, decimal shifts.",
            labelsMisconceptions: true
        ),
        itemTypeProfile: PersonaItemTypeProfile(defaultType: .numeric, preferredTypes: [.numeric, .multipleChoice, .fillInBlank]),
        linkingPresets: PersonaLinkingPresets(suggestSourceLink: true),
        isBuiltIn: true
    )

    // MARK: - STEM / quantitative

    static let physics = Persona(
        id: "app.quizeditor.persona.physics",
        displayName: "Physics",
        family: "stem",
        summary: "Misconception-mapped, unit-aware items: distractors target well-known physics misconceptions and quantities carry units.",
        linterProfile: PersonaLinterProfile(requiresNumericUnit: true),
        aiProfile: PersonaAIProfile(
            systemPreamble: "Adopt the perspective of a physics educator. Build distractors from documented physics misconceptions (e.g. force implies motion, heavier falls faster); numeric answers carry units and respect vector vs scalar quantities.",
            reviewGuidelines: ["Each distractor maps to a specific misconception.", "Units and vector/scalar distinctions are correct."],
            distractorStrategy: "Documented physics misconceptions and sign/unit errors.",
            labelsMisconceptions: true
        ),
        itemTypeProfile: PersonaItemTypeProfile(defaultType: .numeric, preferredTypes: [.numeric, .multipleChoice]),
        isBuiltIn: true
    )

    static let computerScience = Persona(
        id: "app.quizeditor.persona.computer-science",
        displayName: "Computer Science",
        family: "stem",
        summary: "Code-tracing and output-prediction items: exact program output, complexity analysis, and debugging.",
        aiProfile: PersonaAIProfile(
            systemPreamble: "Adopt the perspective of a computer science educator. Favor code-tracing, exact-output-prediction, complexity-analysis, and debugging items; include the precise code and ask for the exact output or Big-O.",
            reviewGuidelines: ["Code is complete and unambiguous; the expected output is exact.", "Complexity items state the cost model."],
            distractorStrategy: "Off-by-one errors, wrong complexity class, and common tracing mistakes.",
            labelsMisconceptions: true
        ),
        itemTypeProfile: PersonaItemTypeProfile(defaultType: .multipleChoice, preferredTypes: [.multipleChoice, .shortAnswer, .fillInBlank]),
        isBuiltIn: true
    )

    static let engineering = Persona(
        id: "app.quizeditor.persona.engineering",
        displayName: "Engineering",
        family: "stem",
        summary: "Applied problem-solving items: units and significant figures throughout, and design trade-off reasoning.",
        linterProfile: PersonaLinterProfile(requiresNumericUnit: true),
        aiProfile: PersonaAIProfile(
            systemPreamble: "Adopt the perspective of an engineering educator. Favor applied problem-solving and design-trade-off items; carry units and significant figures through every calculation.",
            reviewGuidelines: ["Units and significant figures are consistent end to end.", "Trade-off items name the competing constraints."],
            distractorStrategy: "Unit-conversion errors, sig-fig mistakes, and ignoring a binding constraint.",
            labelsMisconceptions: true
        ),
        itemTypeProfile: PersonaItemTypeProfile(defaultType: .numeric, preferredTypes: [.numeric, .multipleChoice]),
        linkingPresets: PersonaLinkingPresets(competencyFrameworks: ["ABET"], suggestObjectiveLink: true),
        isBuiltIn: true
    )

    static let mathematics = Persona(
        id: "app.quizeditor.persona.mathematics",
        displayName: "Mathematics",
        family: "stem",
        summary: "Misconception-aware items with notation rigor: distractors are specific errors, and equivalent forms are accepted.",
        aiProfile: PersonaAIProfile(
            systemPreamble: "Adopt the perspective of a mathematics educator. Use rigorous notation; build distractors from specific, common procedural errors; accept mathematically equivalent forms of the answer.",
            reviewGuidelines: ["Notation is unambiguous.", "Each distractor reflects a specific error, not a random number.", "Equivalent forms of the key are acceptable."],
            distractorStrategy: "Specific procedural errors: sign slips, distribution mistakes, off-by-one, dropped terms.",
            labelsMisconceptions: true
        ),
        itemTypeProfile: PersonaItemTypeProfile(defaultType: .multipleChoice, preferredTypes: [.multipleChoice, .numeric, .fillInBlank]),
        isBuiltIn: true
    )

    static let statistics = Persona(
        id: "app.quizeditor.persona.statistics",
        displayName: "Statistics",
        family: "stem",
        summary: "Data-literate items: distinguishes association from causation, names the test and study design, and reads intervals correctly.",
        aiProfile: PersonaAIProfile(
            systemPreamble: "Adopt the perspective of a statistics educator. Distinguish association from causation, name the appropriate test and study design, and interpret confidence intervals and p-values correctly.",
            reviewGuidelines: ["Do not imply causation from observational data.", "The item names the test/measure it assesses."],
            safetyClauses: ["Do not state causation where only association is supported."],
            labelsMisconceptions: true
        ),
        itemTypeProfile: PersonaItemTypeProfile(defaultType: .multipleChoice, preferredTypes: [.multipleChoice, .numeric]),
        terminology: [
            PersonaTerminologyRule(preferred: "associated with", discouraged: ["causes", "proves"], rationale: "Statistics describes association unless the design supports causation.")
        ],
        isBuiltIn: true
    )

    // MARK: - Social sciences

    static let counseling = Persona(
        id: "app.quizeditor.persona.counseling",
        displayName: "Counseling",
        family: "social-science",
        summary: "Clinical-judgment, ethics-anchored items in person-first language, mapped to CACREP and the ACA ethics.",
        linterProfile: PersonaLinterProfile(requiresCompetency: true),
        aiProfile: PersonaAIProfile(
            systemPreamble: "Adopt the perspective of a counselor educator. Write practice-scenario items exercising clinical judgment and ethical decision-making, grounded in the CACREP standards and the ACA Code of Ethics, in person-first language.",
            reviewGuidelines: ["Use person-first, non-stigmatizing language.", "Anchor the item in a client scenario and map it to a CACREP area."],
            safetyClauses: ["Never stereotype or pathologize a client population."]
        ),
        itemTypeProfile: PersonaItemTypeProfile(defaultType: .multipleChoice, preferredTypes: [.multipleChoice, .essay]),
        terminology: [
            PersonaTerminologyRule(preferred: "person with a substance use disorder", discouraged: ["addict", "substance abuser"], rationale: "Use person-first language."),
            PersonaTerminologyRule(preferred: "person with mental illness", discouraged: ["the mentally ill", "crazy"], rationale: "Use person-first, non-stigmatizing language.")
        ],
        linkingPresets: PersonaLinkingPresets(competencyFrameworks: ["CACREP"], suggestObjectiveLink: true),
        isBuiltIn: true
    )

    static let economics = Persona(
        id: "app.quizeditor.persona.economics",
        displayName: "Economics",
        family: "social-science",
        summary: "Concept-application items: marginal and ceteris-paribus reasoning, graph and model interpretation.",
        aiProfile: PersonaAIProfile(
            systemPreamble: "Adopt the perspective of an economics educator. Favor concept-application items using marginal analysis and ceteris-paribus reasoning; interpret graphs and models rather than recall definitions.",
            reviewGuidelines: ["State the assumptions held constant (ceteris paribus).", "Apply a concept to a scenario rather than asking for a definition."],
            distractorStrategy: "Common errors: confusing movement along vs shift of a curve, ignoring opportunity cost, sunk-cost reasoning.",
            labelsMisconceptions: true
        ),
        itemTypeProfile: PersonaItemTypeProfile(defaultType: .multipleChoice, preferredTypes: [.multipleChoice, .numeric]),
        isBuiltIn: true
    )

    static let law = Persona(
        id: "app.quizeditor.persona.law",
        displayName: "Law",
        family: "social-science",
        summary: "Fact-pattern, single-best-answer items with IRAC reasoning and emphasized negative lead-ins.",
        linterProfile: PersonaLinterProfile(
            ruleOverrides: ["unemphasizedNegativeStem": PersonaRuleOverride(severity: .warning)]
        ),
        aiProfile: PersonaAIProfile(
            systemPreamble: "Adopt the perspective of a law educator. Write fact-pattern, single-best-answer items; the candidate applies a rule to facts (IRAC). Exactly one option is the most defensible answer.",
            reviewGuidelines: ["The fact pattern contains the legally relevant facts and no more.", "Distractors are plausible misapplications of the rule."],
            distractorStrategy: "Plausible misapplications: wrong rule, right rule misapplied, or a distractor that ignores a dispositive fact.",
            labelsMisconceptions: true
        ),
        itemTypeProfile: PersonaItemTypeProfile(defaultType: .multipleChoice, preferredTypes: [.multipleChoice, .essay]),
        linkingPresets: PersonaLinkingPresets(suggestSourceLink: true, suggestCaseLink: true),
        isBuiltIn: true
    )

    static let politicalScience = Persona(
        id: "app.quizeditor.persona.political-science",
        displayName: "Political Science",
        family: "social-science",
        summary: "Concept-application, source-interpretation, and comparative-reasoning items grounded in evidence.",
        aiProfile: PersonaAIProfile(
            systemPreamble: "Adopt the perspective of a political science educator. Favor concept-application, source-interpretation, and comparative-reasoning items; tie claims to evidence and avoid partisan framing.",
            reviewGuidelines: ["Interpret a source or compare cases rather than recall facts.", "Keep framing non-partisan and evidence-based."]
        ),
        itemTypeProfile: PersonaItemTypeProfile(defaultType: .multipleChoice, preferredTypes: [.multipleChoice, .essay]),
        linkingPresets: PersonaLinkingPresets(suggestSourceLink: true, suggestCaseLink: true),
        isBuiltIn: true
    )

    static let psychology = Persona(
        id: "app.quizeditor.persona.psychology",
        displayName: "Psychology",
        family: "social-science",
        summary: "Scenario-based, research-literate items: applies findings to scenarios and keeps correlation distinct from causation.",
        aiProfile: PersonaAIProfile(
            systemPreamble: "Adopt the perspective of a psychology educator. Favor scenario-based, research-literate items; apply findings to situations and keep correlation distinct from causation. Avoid pop-psychology framing.",
            reviewGuidelines: ["Apply a concept or finding to a scenario.", "Do not imply causation from correlational studies."],
            distractorStrategy: "Common misconceptions and pop-psychology myths.",
            labelsMisconceptions: true
        ),
        itemTypeProfile: PersonaItemTypeProfile(defaultType: .multipleChoice, preferredTypes: [.multipleChoice]),
        terminology: [
            PersonaTerminologyRule(preferred: "associated with", discouraged: ["causes"], rationale: "Most psychology findings are correlational."),
            PersonaTerminologyRule(preferred: "people who", discouraged: ["left-brained", "right-brained"], rationale: "A persistent pop-psychology myth.")
        ],
        isBuiltIn: true
    )

    static let sociology = Persona(
        id: "app.quizeditor.persona.sociology",
        displayName: "Sociology",
        family: "social-science",
        summary: "Structural-reasoning items in person-first, non-stigmatizing language that distinguish individual from structural explanations.",
        aiProfile: PersonaAIProfile(
            systemPreamble: "Adopt the perspective of a sociology educator. Favor items that distinguish individual from structural explanations, using person-first, non-stigmatizing language.",
            reviewGuidelines: ["Use person-first, non-stigmatizing language.", "Distinguish structural from individual-level explanations."],
            safetyClauses: ["Do not stereotype groups or treat a group as a monolith."]
        ),
        itemTypeProfile: PersonaItemTypeProfile(defaultType: .multipleChoice, preferredTypes: [.multipleChoice, .essay]),
        terminology: [
            PersonaTerminologyRule(preferred: "person experiencing poverty", discouraged: ["the poor"], rationale: "Use person-first language."),
            PersonaTerminologyRule(preferred: "person who is incarcerated", discouraged: ["convict", "felon"], rationale: "Use person-first, non-stigmatizing language.")
        ],
        isBuiltIn: true
    )

    // MARK: - Humanities

    static let history = Persona(
        id: "app.quizeditor.persona.history",
        displayName: "History",
        family: "humanities",
        summary: "Historical-thinking items built on a source/stimulus: periodization, contextualization, and argumentation without presentism.",
        aiProfile: PersonaAIProfile(
            systemPreamble: "Adopt the perspective of a history educator. Build items on a source or stimulus and exercise historical thinking — contextualization, periodization, causation, and argumentation — without presentism.",
            reviewGuidelines: ["Anchor the item in a source/stimulus.", "Judge actors by their context, not present-day standards."],
            distractorStrategy: "Anachronisms, presentist readings, and common chronology errors."
        ),
        itemTypeProfile: PersonaItemTypeProfile(defaultType: .multipleChoice, preferredTypes: [.multipleChoice, .essay]),
        terminology: [
            PersonaTerminologyRule(preferred: "associated with", discouraged: ["proves"], rationale: "Sources support historical claims; they rarely prove them.")
        ],
        linkingPresets: PersonaLinkingPresets(suggestSourceLink: true, suggestCaseLink: true),
        isBuiltIn: true
    )

    static let literature = Persona(
        id: "app.quizeditor.persona.literature",
        displayName: "Literature",
        family: "humanities",
        summary: "Evidence-supported close-reading items anchored to an attached passage, not recall about the work.",
        aiProfile: PersonaAIProfile(
            systemPreamble: "Adopt the perspective of a literature educator. Build close-reading items on an attached passage; the answer is the best evidence-supported reading of the text, not recall about the author or plot.",
            reviewGuidelines: ["Attach the passage the item depends on.", "The key is the best textually-supported reading; distractors are plausible misreadings."],
            distractorStrategy: "Plausible misreadings: over-literal, ignores tone/figurative language, or imports outside assumptions."
        ),
        itemTypeProfile: PersonaItemTypeProfile(defaultType: .multipleChoice, preferredTypes: [.multipleChoice, .essay]),
        linkingPresets: PersonaLinkingPresets(suggestSourceLink: true, suggestCaseLink: true),
        isBuiltIn: true
    )

    static let philosophy = Persona(
        id: "app.quizeditor.persona.philosophy",
        displayName: "Philosophy",
        family: "humanities",
        summary: "Argument-analysis items: identify premises and conclusions and distinguish validity from soundness and truth.",
        aiProfile: PersonaAIProfile(
            systemPreamble: "Adopt the perspective of a philosophy educator. Favor argument-analysis items: identify premises and conclusions, evaluate inferences, and keep validity, soundness, and truth distinct.",
            reviewGuidelines: ["Distinguish a valid argument from a sound one and from a true conclusion.", "Distractors are common informal fallacies or conflations."],
            distractorStrategy: "Common fallacies and the validity/soundness/truth conflation.",
            labelsMisconceptions: true
        ),
        itemTypeProfile: PersonaItemTypeProfile(defaultType: .multipleChoice, preferredTypes: [.multipleChoice, .essay]),
        terminology: [
            PersonaTerminologyRule(preferred: "valid (vs. sound)", discouraged: ["proves the conclusion is true"], rationale: "Validity concerns form; soundness adds true premises.")
        ],
        isBuiltIn: true
    )
}
