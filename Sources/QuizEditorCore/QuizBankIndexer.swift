import Foundation

/// One question discovered in the question bank, tagged with the file it came from.
public struct BankQuestion: Identifiable, Sendable, Equatable {
    public let question: QuizQuestion
    public let sourceTitle: String
    public let sourceURL: URL

    public var id: UUID { question.id }

    public init(question: QuizQuestion, sourceTitle: String, sourceURL: URL) {
        self.question = question
        self.sourceTitle = sourceTitle
        self.sourceURL = sourceURL
    }
}

/// Indexes every `.quizeditor` file in a folder (read-only) and offers full-text
/// search and type/tag filtering across all of their questions. Source files are
/// only read, never written, so browsing the bank can't change saved quizzes.
public struct QuizBankIndexer: Sendable {
    /// Filters applied to a set of bank questions.
    public struct Query: Sendable, Equatable {
        public var searchText: String
        public var type: QuizQuestionType?
        public var tag: String?

        public init(searchText: String = "", type: QuizQuestionType? = nil, tag: String? = nil) {
            self.searchText = searchText
            self.type = type
            self.tag = tag
        }

        public var isEmpty: Bool {
            searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && type == nil && tag == nil
        }
    }

    private let html = HTMLUtilities()

    public init() {}

    /// Reads and flattens every `.quizeditor` file under `folder` (recursively).
    /// Files that can't be read or decoded are skipped rather than failing the
    /// whole index.
    public func index(folder: URL) -> [BankQuestion] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var quizzes: [(url: URL, quiz: Quiz)] = []
        for case let url as URL in enumerator where url.pathExtension == "quizeditor" {
            guard
                let data = try? Data(contentsOf: url),
                let quiz = try? JSONDecoder().decode(Quiz.self, from: data)
            else { continue }
            quizzes.append((url, quiz))
        }
        return index(quizzes: quizzes)
    }

    /// Flattens already-decoded quizzes into bank questions. Separated from disk
    /// access so it can be unit-tested without a filesystem.
    public func index(quizzes: [(url: URL, quiz: Quiz)]) -> [BankQuestion] {
        quizzes.flatMap { entry in
            entry.quiz.questions.map { question in
                BankQuestion(question: question, sourceTitle: entry.quiz.title, sourceURL: entry.url)
            }
        }
    }

    /// Applies a query to a bank. Search matches the prompt, answer/match text,
    /// tags, and the source quiz title (all case-insensitively).
    public func filter(_ items: [BankQuestion], with query: Query) -> [BankQuestion] {
        let needle = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            if let type = query.type, item.question.type != type { return false }
            if let tag = query.tag, !item.question.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                return false
            }
            if needle.isEmpty { return true }
            return searchableText(for: item).contains(needle)
        }
    }

    /// Every distinct tag across the bank, for building a filter menu.
    public func tags(in items: [BankQuestion]) -> [String] {
        var seenKeys: Set<String> = []
        var orderedTags: [String] = []
        for item in items {
            for tag in item.question.tags {
                let key = tag.lowercased()
                if !seenKeys.contains(key) {
                    seenKeys.insert(key)
                    orderedTags.append(tag)
                }
            }
        }
        return orderedTags.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func searchableText(for item: BankQuestion) -> String {
        var parts = [html.plainText(fromHTML: item.question.prompt), item.sourceTitle]
        parts.append(contentsOf: item.question.answers.map { html.plainText(fromHTML: $0.text) })
        parts.append(contentsOf: item.question.matches.flatMap { [$0.prompt, $0.match] })
        parts.append(contentsOf: item.question.tags)
        parts.append(html.plainText(fromHTML: item.question.feedback))
        return parts.joined(separator: "\n").lowercased()
    }
}
