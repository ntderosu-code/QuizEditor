import Foundation
import QuizEditorCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Guided generation for the on-device Apple Foundation Models provider.
///
/// Small on-device models are unreliable at emitting clean JSON in free text:
/// they wrap it in prose, truncate it, or echo example placeholders. Guided
/// generation uses constrained sampling against a Swift type so the model can
/// only produce well-formed structured output. Each method below returns a JSON
/// string in exactly the shape the existing `QuizEditorCore` parsers expect, so
/// all of the alignment and correctness logic in Core is reused unchanged.
enum GuidedFoundationModels {
    enum GuidedError: Error, CustomStringConvertible {
        case unavailable
        case unsupportedOS

        var description: String {
            switch self {
            case .unavailable:
                "Apple Foundation Models is not available on this Mac. Enable Apple Intelligence on a supported Mac, or use the Copy/Paste provider."
            case .unsupportedOS:
                "Apple Foundation Models requires a newer macOS. Use the Copy/Paste provider or an OpenAI-compatible API on this Mac."
            }
        }
    }

    // MARK: - Public, provider-shaped entry points (return Core-parseable JSON)

    static func review(system: String, user: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let gen = try await generate(instructions: system, prompt: user, type: GenReview.self)
            return jsonString(reviewObject(from: gen))
        }
        #endif
        throw GuidedError.unsupportedOS
    }

    static func batchReview(system: String, user: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let gen = try await generate(instructions: system, prompt: user, type: GenBatchReview.self)
            let array = gen.items.map { reviewObject(from: $0.review, index: $0.index) }
            return jsonString(array)
        }
        #endif
        throw GuidedError.unsupportedOS
    }

    static func distractors(system: String, user: String, labelsMisconceptions: Bool) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if labelsMisconceptions {
                let gen = try await generate(instructions: system, prompt: user, type: GenLabeledDistractors.self)
                let items = gen.distractors.map { ["text": $0.text, "misconception": $0.misconception] }
                return jsonString(["distractors": items])
            } else {
                let gen = try await generate(instructions: system, prompt: user, type: GenDistractors.self)
                return jsonString(["distractors": gen.distractors])
            }
        }
        #endif
        throw GuidedError.unsupportedOS
    }

    static func feedback(system: String, user: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let gen = try await generate(instructions: system, prompt: user, type: GenFeedback.self)
            return jsonString(["feedback": gen.feedback])
        }
        #endif
        throw GuidedError.unsupportedOS
    }

    static func questions(system: String, user: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let gen = try await generate(instructions: system, prompt: user, type: GenQuestions.self)
            let array = gen.questions.map { question -> [String: Any] in
                [
                    "type": question.type,
                    "prompt": question.prompt,
                    "answers": question.answers.map { ["text": $0.text, "correct": $0.correct] },
                    "matches": question.matches.map { ["term": $0.term, "match": $0.match] },
                    "feedback": question.feedback
                ]
            }
            return jsonString(["questions": array])
        }
        #endif
        throw GuidedError.unsupportedOS
    }

    // MARK: - Serialization (Gen* values → Core-shaped JSON)

    private static func jsonString(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
extension GuidedFoundationModels {
    /// Runs one guided request. `instructions` becomes the session's system role;
    /// `prompt` is the user turn. Throws if the on-device model is unavailable.
    static func generate<T: Generable>(instructions: String, prompt: String, type: T.Type) async throws -> T {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { throw GuidedError.unavailable }
        let session = LanguageModelSession(model: model, instructions: instructions)
        return try await session.respond(to: prompt, generating: T.self).content
    }

    static func reviewObject(from gen: GenReview, index: Int? = nil) -> [String: Any] {
        var object: [String: Any] = [
            "summary": gen.summary,
            "suggestions": gen.suggestions,
            "revised": [
                "prompt": gen.revisedPrompt,
                "answers": gen.revisedAnswers,
                "feedback": gen.revisedFeedback
            ]
        ]
        if let index { object["index"] = index }
        return object
    }
}

// MARK: - Generable schemas

/// A single-question review. Every field is always returned (optionals are not
/// among the guaranteed guided-generation types); Core suppresses any field that
/// matches the original, so repeating unchanged text is safe.
@available(macOS 26.0, *)
@Generable
struct GenReview {
    @Guide(description: "one short paragraph assessing the question overall")
    var summary: String
    @Guide(description: "each entry is one specific issue and its concrete fix; leave empty if there are none")
    var suggestions: [String]
    @Guide(description: "the improved stem text; repeat the original verbatim if it needs no change")
    var revisedPrompt: String
    @Guide(description: "every answer option in its original order, reworded for clarity only; keep the same number of options and the same meaning; repeat any option verbatim if it is already fine")
    var revisedAnswers: [String]
    @Guide(description: "improved feedback for students; repeat the original verbatim if unchanged")
    var revisedFeedback: String
}

@available(macOS 26.0, *)
@Generable
struct GenBatchItem {
    @Guide(description: "the index of the question this review refers to, starting at 0")
    var index: Int
    var review: GenReview
}

@available(macOS 26.0, *)
@Generable
struct GenBatchReview {
    @Guide(description: "one entry per reviewed question, in order")
    var items: [GenBatchItem]
}

@available(macOS 26.0, *)
@Generable
struct GenDistractors {
    @Guide(description: "real, plausible-but-incorrect answer options for the stem; never placeholder text")
    var distractors: [String]
}

@available(macOS 26.0, *)
@Generable
struct GenLabeledDistractor {
    @Guide(description: "the distractor: a real, plausible-but-incorrect answer option; never placeholder text")
    var text: String
    @Guide(description: "the common misconception this distractor reflects")
    var misconception: String
}

@available(macOS 26.0, *)
@Generable
struct GenLabeledDistractors {
    var distractors: [GenLabeledDistractor]
}

@available(macOS 26.0, *)
@Generable
struct GenFeedback {
    @Guide(description: "feedback for students explaining why the key is correct and the distractors are plausible but wrong")
    var feedback: String
}

@available(macOS 26.0, *)
@Generable
struct GenAnswer {
    var text: String
    @Guide(description: "true if this option is a correct answer")
    var correct: Bool
}

@available(macOS 26.0, *)
@Generable
struct GenMatch {
    var term: String
    var match: String
}

@available(macOS 26.0, *)
@Generable
struct GenQuestion {
    @Guide(description: "the question type, one of: multipleChoice, multipleAnswer, trueFalse, fillInBlank, shortAnswer, essay, matching, numeric")
    var type: String
    @Guide(description: "the question stem")
    var prompt: String
    @Guide(description: "answer options for choice-based types; empty for essay and matching")
    var answers: [GenAnswer]
    @Guide(description: "matching pairs; only for the matching type, otherwise empty")
    var matches: [GenMatch]
    @Guide(description: "feedback explaining why the key is correct and the distractors are not")
    var feedback: String
}

@available(macOS 26.0, *)
@Generable
struct GenQuestions {
    var questions: [GenQuestion]
}
#endif
