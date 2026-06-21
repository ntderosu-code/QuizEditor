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

    func run(system: String, user: String, temperature: Double = 0.2) async throws -> String {
        switch provider {
        case .openAICompatible:
            let endpointURL = URL(string: endpoint) ?? URL(string: "https://api.openai.com/v1/chat/completions")!
            let configuration = AIConfiguration(apiKey: apiKey, endpoint: endpointURL, model: model)
            return try await AIClient().complete(
                systemInstruction: system,
                userPrompt: user,
                configuration: configuration,
                temperature: temperature
            )
        case .foundationModels:
            return await FoundationModelsRunner.run(prompt: system + "\n\n" + user)
        case .copyPaste:
            throw RunnerError.copyPasteRequiresManualRun
        }
    }
}
