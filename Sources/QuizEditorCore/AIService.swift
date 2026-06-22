import Foundation

public enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case openAICompatible
    case copyPaste
    case foundationModels

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAICompatible: "OpenAI-compatible API"
        case .copyPaste: "Copy/Paste to Claude or ChatGPT"
        case .foundationModels: "Apple Foundation Models"
        }
    }

    public var requiresAPIKey: Bool {
        self == .openAICompatible
    }
}

public struct AIConfiguration: Equatable, Sendable {
    public enum ValidationError: Error, Equatable, CustomStringConvertible {
        case missingAPIKey
        case missingModel

        public var description: String {
            switch self {
            case .missingAPIKey: "Add an API key before running AI features."
            case .missingModel: "Choose a model before running AI features."
            }
        }
    }

    public var apiKey: String
    public var endpoint: URL
    public var model: String

    public init(
        apiKey: String,
        endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!,
        model: String = "gpt-4o-mini"
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.model = model
    }
}

public enum AIFeature: String, CaseIterable, Identifiable, Sendable {
    case review
    case author
    case revise
    case generateFeedback

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .review: "AI Review"
        case .author: "AI Authoring"
        case .revise: "AI Revision"
        case .generateFeedback: "Feedback Drafting"
        }
    }

    var systemInstruction: String {
        switch self {
        case .review:
            "You are performing an AI review of a quiz for accuracy, clarity, QTI/LMS import readiness, and WCAG accessibility. Return concise, prioritized recommendations."
        case .author:
            "You are authoring quiz questions. Return well-structured questions with answer choices, correct answers marked with *, and feedback."
        case .revise:
            "You are revising quiz questions. Preserve intent while improving clarity, accessibility, distractor quality, and alignment."
        case .generateFeedback:
            "You are drafting useful quiz feedback. Explain why correct answers are correct and incorrect answers are plausible but wrong."
        }
    }
}

public struct AIPromptBuilder: Sendable {
    public init() {}

    public func makePrompt(feature: AIFeature, quiz: Quiz, userInstruction: String) -> String {
        """
        You are helping improve a quiz in Quiz Editor.

        Task: \(feature.displayName)
        System role: \(feature.systemInstruction)
        User instruction: \(userInstruction.isEmpty ? "Use your best instructional design judgment." : userInstruction)

        Requirements:
        - Keep wording accessible and concise.
        - Flag ambiguity, more than one correct answer, weak distractors, and missing feedback.
        - Maintain WCAG-friendly language and avoid relying on color, visual position, or images without alt text.
        - Preserve QTI compatibility.
        - If revising or authoring, return marked text using `*` before correct answers.
        - Paste the full response back into Quiz Editor after the model answers.

        Quiz:
        \(quiz.markedTextRepresentation)
        """
    }
}

public struct AIRequestFactory: Sendable {
    private let promptBuilder: AIPromptBuilder

    public init(promptBuilder: AIPromptBuilder = AIPromptBuilder()) {
        self.promptBuilder = promptBuilder
    }

    public func validate(_ configuration: AIConfiguration) throws {
        if configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AIConfiguration.ValidationError.missingAPIKey
        }
        if configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AIConfiguration.ValidationError.missingModel
        }
    }

    public func makeRequest(feature: AIFeature, quiz: Quiz, userInstruction: String, configuration: AIConfiguration) -> URLRequest {
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = makeBody(feature: feature, quiz: quiz, userInstruction: userInstruction, configuration: configuration)
        return request
    }

    public func makeRawRequest(systemInstruction: String, userPrompt: String, configuration: AIConfiguration, temperature: Double) -> URLRequest {
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let messages: [[String: String]] = [
            ["role": "system", "content": systemInstruction],
            ["role": "user", "content": userPrompt]
        ]
        let payload: [String: Any] = [
            "model": configuration.model,
            "messages": messages,
            "temperature": temperature
        ]
        request.httpBody = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
        return request
    }

    private func makeBody(feature: AIFeature, quiz: Quiz, userInstruction: String, configuration: AIConfiguration) -> Data {
        let messages: [[String: String]] = [
            ["role": "system", "content": feature.systemInstruction],
            ["role": "user", "content": promptBuilder.makePrompt(feature: feature, quiz: quiz, userInstruction: userInstruction)]
        ]
        let payload: [String: Any] = [
            "model": configuration.model,
            "messages": messages,
            "temperature": feature == .author ? 0.7 : 0.2
        ]
        return (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
    }
}

public struct AIClient: Sendable {
    public enum ClientError: Error, Equatable, CustomStringConvertible {
        case invalidResponse
        case serverError(statusCode: Int)
        case missingContent

        public var description: String {
            switch self {
            case .invalidResponse: "The AI provider returned an invalid response."
            case .serverError(let statusCode): "The AI provider returned HTTP \(statusCode)."
            case .missingContent: "The AI provider response did not include text content."
            }
        }
    }

    private let factory: AIRequestFactory
    private let session: URLSession

    public init(factory: AIRequestFactory = AIRequestFactory(), session: URLSession = .shared) {
        self.factory = factory
        self.session = session
    }

    public func run(feature: AIFeature, quiz: Quiz, instruction: String, configuration: AIConfiguration) async throws -> String {
        try factory.validate(configuration)
        let request = factory.makeRequest(feature: feature, quiz: quiz, userInstruction: instruction, configuration: configuration)
        return try await send(request)
    }

    public func complete(systemInstruction: String, userPrompt: String, configuration: AIConfiguration, temperature: Double = 0.2) async throws -> String {
        try factory.validate(configuration)
        let request = factory.makeRawRequest(systemInstruction: systemInstruction, userPrompt: userPrompt, configuration: configuration, temperature: temperature)
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> String {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ClientError.serverError(statusCode: httpResponse.statusCode)
        }

        guard let content = Self.extractContent(from: data) else { throw ClientError.missingContent }
        return content
    }

    private static func extractContent(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let firstChoice = choices.first,
            let message = firstChoice["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            return nil
        }
        return content
    }
}

public extension Quiz {
    var markedTextRepresentation: String {
        var lines = ["Title: \(title)"]
        for question in questions {
            lines.append("")
            lines.append("Type: \(question.type.displayName)")
            lines.append("Question: \(question.prompt)")
            if question.type == .matching {
                lines.append(contentsOf: question.matches.map { "- \($0.prompt) => \($0.match)" })
            } else {
                lines.append(contentsOf: question.answers.map { answer in
                    "\(answer.isCorrect ? "*" : "-") \(answer.text)"
                })
            }
            if !question.feedback.isEmpty {
                lines.append("Feedback: \(question.feedback)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Splits the quiz into consecutive sub-quizzes whose marked-text representation
    /// stays within `maxCharacters`. On-device models (Apple Foundation Models) have a
    /// small context window of roughly 4096 tokens shared between the prompt and the
    /// reply, so a long quiz has to be processed a page at a time. Each sub-quiz keeps
    /// the quiz title. A single question larger than the budget is kept whole in its own
    /// batch rather than being split, since splitting a question would corrupt it.
    func batched(maxCharacters: Int) -> [Quiz] {
        guard !questions.isEmpty else { return [] }
        guard maxCharacters > 0 else { return [self] }

        var batches: [Quiz] = []
        var current: [QuizQuestion] = []

        for question in questions {
            let candidate = Quiz(title: title, questions: current + [question])
            if !current.isEmpty, candidate.markedTextRepresentation.count > maxCharacters {
                // Adding this question would overflow the budget, so close the current
                // batch and start a new one with the question.
                batches.append(Quiz(title: title, questions: current))
                current = [question]
            } else {
                current.append(question)
            }
        }

        if !current.isEmpty {
            batches.append(Quiz(title: title, questions: current))
        }
        return batches
    }
}
