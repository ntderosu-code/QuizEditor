import XCTest
@testable import QuizEditorCore

/// Phase 2 (#21): the active persona reshapes AI prompts by prepending a system
/// preamble and appending discipline guidelines, safety clauses, linked context,
/// and exemplars — all append-only, so General is byte-equivalent to today and the
/// JSON contract and accessibility bullets are never removed.
final class PersonaAIPromptTests: XCTestCase {
    private let review = QuestionReviewService()
    private let authoring = QuestionAuthoringService()

    private func sampleQuestion() -> QuizQuestion {
        QuizQuestion(
            type: .multipleChoice,
            prompt: "Which organelle makes ATP?",
            answers: [QuizAnswer(text: "Mitochondrion", isCorrect: true), QuizAnswer(text: "Ribosome", isCorrect: false)],
            feedback: "The mitochondrion."
        )
    }

    private func nursingPersona() -> Persona {
        Persona(
            id: "test.nursing",
            displayName: "Nursing",
            aiProfile: PersonaAIProfile(
                systemPreamble: "Adopt the perspective of a nurse educator writing NCLEX-style items.",
                reviewGuidelines: ["Flag any item that rewards an unsafe action."],
                authoringGuidelines: ["Prefer single-best-action clinical-judgment stems."],
                distractorStrategy: "Each distractor is a plausible-but-unsafe action.",
                safetyClauses: ["Never invent drug doses or guideline citations."]
            ),
            exemplars: ["A vignette with one safest action and plausible-but-unsafe distractors."]
        )
    }

    // MARK: - Review system instruction

    func testGeneralReviewSystemInstructionHasNoPreamble() {
        let general = review.systemInstruction(persona: .general)
        XCTAssertEqual(general, review.systemInstruction())
        XCTAssertFalse(general.contains("nurse educator"))
        // The accessibility-minded reviewer role is preserved.
        XCTAssertTrue(general.contains("instructional designer"))
    }

    func testPersonaReviewSystemInstructionPrependsPreamble() {
        let instruction = review.systemInstruction(persona: nursingPersona())
        XCTAssertTrue(instruction.contains("nurse educator"))
        XCTAssertTrue(instruction.contains("instructional designer"))
        // Preamble comes before the base role.
        let preambleRange = instruction.range(of: "nurse educator")
        let baseRange = instruction.range(of: "instructional designer")
        XCTAssertTrue(preambleRange!.lowerBound < baseRange!.lowerBound)
    }

    // MARK: - Review prompt

    func testGeneralReviewPromptAddsNoPersonaSections() {
        let prompt = review.makePrompt(question: sampleQuestion(), quizTitle: "Bio", persona: .general)
        XCTAssertFalse(prompt.contains("discipline-specific"))
        XCTAssertFalse(prompt.contains("Safety constraints"))
        XCTAssertFalse(prompt.contains("Linked context"))
        // Critical contract and accessibility guidance remain.
        XCTAssertTrue(prompt.contains("Do NOT add, remove, or reorder"))
        XCTAssertTrue(prompt.contains("accessible language"))
    }

    func testPersonaReviewPromptAppendsGuidelinesAndSafety() {
        let prompt = review.makePrompt(question: sampleQuestion(), quizTitle: "Bio", persona: nursingPersona())
        XCTAssertTrue(prompt.contains("Flag any item that rewards an unsafe action."))
        XCTAssertTrue(prompt.contains("Never invent drug doses or guideline citations."))
        // The original contract is still intact.
        XCTAssertTrue(prompt.contains("Do NOT add, remove, or reorder"))
    }

    func testReviewPromptIncludesLinkedContext() {
        let context = PromptLinkContext(
            stimulus: Stimulus(id: "s1", kind: .vignette, body: "A 64-year-old presents with dyspnea."),
            sources: [Source(id: "src1", citation: "WHO Hypertension Guidelines 2023")],
            objectives: [LearningObjective(id: "o1", text: "Apply oxygenation priorities", cognitiveLevel: .apply)]
        )
        let prompt = review.makePrompt(question: sampleQuestion(), quizTitle: "Bio", persona: nursingPersona(), linkedContext: context)
        XCTAssertTrue(prompt.contains("A 64-year-old presents with dyspnea."))
        XCTAssertTrue(prompt.contains("WHO Hypertension Guidelines 2023"))
        XCTAssertTrue(prompt.contains("Apply oxygenation priorities"))
        // When a source is linked, instruct the model to defer to it.
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("defer"))
    }

    // MARK: - Batch (whole-quiz) prompt

    func testGeneralBatchPromptUnchanged() {
        let questions = [sampleQuestion()]
        XCTAssertEqual(
            review.makeBatchPrompt(questions: questions, quizTitle: "Bio", persona: .general),
            review.makeBatchPrompt(questions: questions, quizTitle: "Bio")
        )
        XCTAssertFalse(review.makeBatchPrompt(questions: questions, quizTitle: "Bio").contains("discipline-specific"))
    }

    func testPersonaBatchPromptAppendsGuidelines() {
        let prompt = review.makeBatchPrompt(questions: [sampleQuestion()], quizTitle: "Bio", persona: nursingPersona())
        XCTAssertTrue(prompt.contains("Flag any item that rewards an unsafe action."))
        XCTAssertTrue(prompt.contains("Never invent drug doses or guideline citations."))
    }

    // MARK: - PromptLinkContext resolver

    func testQuizResolvesPromptLinkContextForQuestion() {
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "Per the vignette…",
            answers: [QuizAnswer(text: "A", isCorrect: true)],
            objectiveIDs: ["o1"],
            sourceIDs: ["src1"],
            stimulusID: "s1"
        )
        let quiz = Quiz(
            title: "Linked",
            questions: [question],
            objectives: [LearningObjective(id: "o1", text: "Analyze", cognitiveLevel: .analyze)],
            stimuli: [Stimulus(id: "s1", kind: .vignette, body: "Case body")],
            sources: [Source(id: "src1", citation: "Smith 2020")]
        )
        let context = quiz.promptLinkContext(for: question)
        XCTAssertEqual(context.stimulus?.body, "Case body")
        XCTAssertEqual(context.sources.map(\.id), ["src1"])
        XCTAssertEqual(context.objectives.map(\.id), ["o1"])
        XCTAssertFalse(context.isEmpty)
    }

    func testEmptyPromptLinkContextForUnlinkedQuestion() {
        let question = sampleQuestion()
        let quiz = Quiz(title: "Plain", questions: [question])
        XCTAssertTrue(quiz.promptLinkContext(for: question).isEmpty)
    }

    // MARK: - Authoring service

    func testGeneralAuthoringSystemInstructionHasNoPreamble() {
        let general = authoring.systemInstruction(persona: .general)
        XCTAssertEqual(general, authoring.systemInstruction())
        XCTAssertFalse(general.contains("nurse educator"))
        XCTAssertTrue(general.contains("instructional designer"))
    }

    func testPersonaAuthoringSystemInstructionPrependsPreamble() {
        let instruction = authoring.systemInstruction(persona: nursingPersona())
        XCTAssertTrue(instruction.contains("nurse educator"))
        XCTAssertTrue(instruction.contains("instructional designer"))
    }

    func testGeneralGenerationPromptAddsNoPersonaSections() {
        let prompt = authoring.makeGenerationPrompt(topic: "Cells", count: 2, types: [.multipleChoice], persona: .general)
        XCTAssertEqual(
            prompt,
            authoring.makeGenerationPrompt(topic: "Cells", count: 2, types: [.multipleChoice])
        )
        XCTAssertFalse(prompt.contains("discipline-specific"))
    }

    func testPersonaGenerationPromptIncludesGuidelinesAndExemplars() {
        let prompt = authoring.makeGenerationPrompt(topic: "Cells", count: 2, types: [.multipleChoice], persona: nursingPersona())
        XCTAssertTrue(prompt.contains("Prefer single-best-action clinical-judgment stems."))
        XCTAssertTrue(prompt.contains("A vignette with one safest action and plausible-but-unsafe distractors."))
    }

    func testPersonaDistractorsPromptIncludesStrategy() {
        let prompt = authoring.makeDistractorsPrompt(prompt: "Stem", correctAnswer: "X", count: 3, persona: nursingPersona())
        XCTAssertTrue(prompt.contains("Each distractor is a plausible-but-unsafe action."))
    }

    func testGeneralDistractorsPromptUnchanged() {
        XCTAssertEqual(
            authoring.makeDistractorsPrompt(prompt: "Stem", correctAnswer: "X", count: 3, persona: .general),
            authoring.makeDistractorsPrompt(prompt: "Stem", correctAnswer: "X", count: 3)
        )
    }

    func testPersonaFeedbackPromptIncludesGuidelinesAndContext() {
        let context = PromptLinkContext(sources: [Source(id: "s", citation: "WHO 2023")])
        let prompt = authoring.makeFeedbackPrompt(question: sampleQuestion(), quizTitle: "Bio", persona: nursingPersona(), linkedContext: context)
        XCTAssertTrue(prompt.contains("WHO 2023"))
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("defer"))
    }
}
