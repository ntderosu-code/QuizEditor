import Foundation

/// How many questions an export includes and in what order.
///
/// Both export paths (paper exam PDF, formatted HTML document) share this, so a
/// student copy and the answer key printed from it can be reproduced exactly.
public struct ExamSelection: Sendable, Equatable {
    /// Shuffle the bank before taking `questionCount` questions.
    public var shuffleQuestions: Bool
    /// How many questions to include. `nil` means every question.
    public var questionCount: Int?
    /// Text the shuffle seed is derived from, typically the version label.
    /// The same label always produces the same order, which is what lets an
    /// answer key exported later line up with the student copy.
    public var seedLabel: String

    public init(shuffleQuestions: Bool = false, questionCount: Int? = nil, seedLabel: String = "") {
        self.shuffleQuestions = shuffleQuestions
        self.questionCount = questionCount
        self.seedLabel = seedLabel
    }

    /// FNV-1a over the label's UTF-8 bytes.
    ///
    /// Swift's `String.hashValue` is salted per process launch, so an answer key
    /// exported in a later session would not match the student copy already
    /// printed. This hash is fixed for all time, which is the whole point of the
    /// seed, and it is pinned by test.
    public static func stableSeed(for label: String) -> UInt64 {
        let offsetBasis: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211
        var hash = offsetBasis
        for byte in label.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}

/// SplitMix64: a small, well-distributed seedable generator. Swift ships no
/// seedable RNG, and reproducibility across launches is a requirement here.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Derives the quiz an export should actually render.
///
/// Returns a whole `Quiz` rather than a question list so everything downstream
/// stays correct without knowing selection happened: the paper exam's score
/// field reads `totalPoints` and `questions.count` from the quiz it is given,
/// and a 20-of-25 exam must be out of the 20 questions it prints.
public enum ExamAssembler {
    public static func assemble(_ quiz: Quiz, selection: ExamSelection) -> Quiz {
        var questions = quiz.questions

        if selection.shuffleQuestions {
            var generator = SeededGenerator(seed: ExamSelection.stableSeed(for: selection.seedLabel))
            questions.shuffle(using: &generator)
        }

        if let requested = selection.questionCount {
            let count = min(max(requested, 0), questions.count)
            questions = Array(questions.prefix(count))
        }

        var assembled = quiz
        assembled.questions = questions
        return assembled
    }
}
