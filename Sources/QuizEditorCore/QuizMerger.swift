import Foundation

/// Appends questions from other quizzes into the current one, assigning fresh
/// identifiers and optionally skipping duplicates (same prompt text + type).
public struct QuizMerger: Sendable {
    /// What to do when an incoming question duplicates one already present.
    public enum DuplicatePolicy: String, CaseIterable, Sendable, Identifiable {
        /// Drop the incoming duplicate, keeping the existing question.
        case skip
        /// Add the incoming question anyway, so both copies are kept.
        case keepBoth

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .skip: "Skip duplicates"
            case .keepBoth: "Keep both copies"
            }
        }
    }

    public struct MergeResult: Sendable, Equatable {
        public let merged: Quiz
        public let addedCount: Int
        public let skippedCount: Int

        public init(merged: Quiz, addedCount: Int, skippedCount: Int) {
            self.merged = merged
            self.addedCount = addedCount
            self.skippedCount = skippedCount
        }
    }

    private let html = HTMLUtilities()

    public init() {}

    /// Returns a new quiz with `incoming` appended to `base`. Every appended
    /// question (and its answers/matches) gets fresh IDs so selection stays
    /// stable and identities never collide with the originals.
    public func merge(base: Quiz, incoming: [QuizQuestion], duplicatePolicy: DuplicatePolicy) -> MergeResult {
        var seenKeys = Set(base.questions.map(duplicateKey(for:)))
        var mergedQuestions = base.questions
        var addedCount = 0
        var skippedCount = 0

        for question in incoming {
            let key = duplicateKey(for: question)
            if duplicatePolicy == .skip, seenKeys.contains(key) {
                skippedCount += 1
                continue
            }
            mergedQuestions.append(withFreshIDs(question))
            seenKeys.insert(key)
            addedCount += 1
        }

        let merged = Quiz(id: base.id, title: base.title, questions: mergedQuestions)
        return MergeResult(merged: merged, addedCount: addedCount, skippedCount: skippedCount)
    }

    /// How many of `incoming` would be skipped as duplicates of `base`. Used to
    /// preview the effect of a merge before committing.
    public func duplicateCount(base: Quiz, incoming: [QuizQuestion]) -> Int {
        let baseKeys = Set(base.questions.map(duplicateKey(for:)))
        var seen = baseKeys
        var duplicates = 0
        for question in incoming {
            let key = duplicateKey(for: question)
            if seen.contains(key) { duplicates += 1 } else { seen.insert(key) }
        }
        return duplicates
    }

    /// Identity used for de-duplication: normalized plain-text prompt + type.
    public func duplicateKey(for question: QuizQuestion) -> String {
        let prompt = html.plainText(fromHTML: question.prompt)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return "\(question.type.rawValue)|\(prompt)"
    }

    /// Clones a question with new UUIDs for it and all of its child elements.
    public func withFreshIDs(_ question: QuizQuestion) -> QuizQuestion {
        var copy = question
        copy.id = UUID()
        copy.answers = question.answers.map { answer in
            QuizAnswer(text: answer.text, isCorrect: answer.isCorrect)
        }
        copy.matches = question.matches.map { pair in
            MatchingPair(prompt: pair.prompt, match: pair.match)
        }
        return copy
    }
}
