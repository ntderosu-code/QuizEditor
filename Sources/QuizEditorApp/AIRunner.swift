import Foundation
import QuizEditorCore

/// Runs a single system+user prompt through whichever AI provider the user has
/// configured. Shared by the inline review, distractor/feedback generation, and
/// the authoring sheet so they all behave consistently.
struct ConfiguredAIRunner {
    var provider: AIProvider
    var apiKey: String
    var endpoint: String
    var model: String

    /// Copy/Paste can't run automatically — the caller copies a prompt and the
    /// user pastes the model's reply back in.
    var supportsAutoRun: Bool { provider != .copyPaste }

    enum RunnerError: Error, CustomStringConvertible {
        case copyPasteRequiresManualRun

        var description: String {
            switch self {
            case .copyPasteRequiresManualRun:
                "This provider can't run automatically. Use Copy Prompt, run it in your assistant, then paste the response back."
            }
        }
    }

    // MARK: - Feature-specific runs (structured)
    //
    // For Apple Foundation Models these use guided generation so the on-device
    // model returns well-formed structured output (no raw-JSON parse failures, no
    // echoed example placeholders). For the OpenAI-compatible API they fall back to
    // the same text completion the Core parsers already handle. All return a JSON
    // string in the shape the matching `QuizEditorCore` parser expects.

    func runReview(system: String, user: String, temperature: Double = 0.2) async throws -> String {
        switch provider {
        case .openAICompatible: return try await openAIComplete(system: system, user: user, temperature: temperature)
        case .foundationModels: return try await GuidedFoundationModels.review(system: system, user: user)
        case .copyPaste: throw RunnerError.copyPasteRequiresManualRun
        }
    }

    func runBatchReview(system: String, user: String, temperature: Double = 0.2) async throws -> String {
        switch provider {
        case .openAICompatible: return try await openAIComplete(system: system, user: user, temperature: temperature)
        case .foundationModels: return try await GuidedFoundationModels.batchReview(system: system, user: user)
        case .copyPaste: throw RunnerError.copyPasteRequiresManualRun
        }
    }

    func runDistractors(system: String, user: String, labelsMisconceptions: Bool, temperature: Double = 0.7) async throws -> String {
        switch provider {
        case .openAICompatible: return try await openAIComplete(system: system, user: user, temperature: temperature)
        case .foundationModels: return try await GuidedFoundationModels.distractors(system: system, user: user, labelsMisconceptions: labelsMisconceptions)
        case .copyPaste: throw RunnerError.copyPasteRequiresManualRun
        }
    }

    func runFeedback(system: String, user: String, temperature: Double = 0.4) async throws -> String {
        switch provider {
        case .openAICompatible: return try await openAIComplete(system: system, user: user, temperature: temperature)
        case .foundationModels: return try await GuidedFoundationModels.feedback(system: system, user: user)
        case .copyPaste: throw RunnerError.copyPasteRequiresManualRun
        }
    }

    func runQuestions(system: String, user: String, temperature: Double = 0.7) async throws -> String {
        switch provider {
        case .openAICompatible: return try await openAIComplete(system: system, user: user, temperature: temperature)
        case .foundationModels: return try await GuidedFoundationModels.questions(system: system, user: user)
        case .copyPaste: throw RunnerError.copyPasteRequiresManualRun
        }
    }

    private func openAIComplete(system: String, user: String, temperature: Double) async throws -> String {
        let endpointURL = URL(string: endpoint) ?? URL(string: "https://api.openai.com/v1/chat/completions")!
        let configuration = AIConfiguration(apiKey: apiKey, endpoint: endpointURL, model: model)
        return try await AIClient().complete(
            systemInstruction: system,
            userPrompt: user,
            configuration: configuration,
            temperature: temperature
        )
    }
}
