import Foundation

public struct CorrectAnswerMarker: Equatable, Codable, Sendable {
    public enum Location: String, CaseIterable, Identifiable, Codable, Sendable {
        case beginningOfLine
        case endOfLine
        case afterEnumeration

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .beginningOfLine: "Beginning of line"
            case .endOfLine: "End of line"
            case .afterEnumeration: "After enumerated choice"
            }
        }
    }

    public var symbol: String
    public var location: Location

    public init(symbol: String = "*", location: Location = .beginningOfLine) {
        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        self.symbol = trimmedSymbol.isEmpty ? "*" : trimmedSymbol
        self.location = location
    }
}

public struct MarkedTextParser: Sendable {
    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case missingTitle
        case missingPrompt(questionNumber: Int)
        case unsupportedType(String)

        public var description: String {
            switch self {
            case .missingTitle:
                "Add a quiz title with `Title: Your Quiz Name`."
            case .missingPrompt(let questionNumber):
                "Question \(questionNumber) needs a `Question:` line."
            case .unsupportedType(let value):
                "Unsupported question type: \(value)."
            }
        }
    }

    private let correctAnswerMarker: CorrectAnswerMarker

    public init(correctAnswerMarker: CorrectAnswerMarker = CorrectAnswerMarker()) {
        self.correctAnswerMarker = correctAnswerMarker
    }

    public func parse(_ source: String) throws -> Quiz {
        let normalizedLines = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        if shouldUseFlexibleParser(normalizedLines) {
            return parseFlexible(normalizedLines)
        }

        return try parseLabeled(normalizedLines)
    }

    private func shouldUseFlexibleParser(_ lines: [String]) -> Bool {
        let nonEmptyLines = lines.filter { !$0.isEmpty }
        guard !nonEmptyLines.isEmpty else { return false }
        return !nonEmptyLines.contains { line in
            let lowered = line.lowercased()
            return lowered.hasPrefix("title:") || lowered.hasPrefix("question:") || lowered.hasPrefix("type:")
        }
    }

    private func parseLabeled(_ lines: [String]) throws -> Quiz {
        var title = ""
        var blocks: [[String]] = []
        var currentBlock: [String] = []

        for line in lines {
            if line.isEmpty {
                if !currentBlock.isEmpty {
                    blocks.append(currentBlock)
                    currentBlock.removeAll()
                }
                continue
            }

            if line.lowercased().hasPrefix("title:") {
                title = value(after: ":", in: line)
            } else {
                currentBlock.append(line)
            }
        }

        if !currentBlock.isEmpty {
            blocks.append(currentBlock)
        }

        guard !title.isEmpty else { throw ParseError.missingTitle }

        let questions = try blocks.enumerated().map { index, block in
            try parseQuestion(block, questionNumber: index + 1)
        }

        return Quiz(title: title, questions: questions)
    }

    private func parseFlexible(_ lines: [String]) -> Quiz {
        var questions: [QuizQuestion] = []
        var currentPrompt = ""
        var currentAnswers: [QuizAnswer] = []

        func finishQuestion() {
            let prompt = currentPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else { return }
            let type: QuizQuestionType = currentAnswers.filter(\.isCorrect).count > 1 ? .multipleAnswer : .multipleChoice
            questions.append(QuizQuestion(type: type, prompt: prompt, answers: currentAnswers))
            currentPrompt = ""
            currentAnswers = []
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                continue
            }

            if isLikelyAnswerLine(line), let answer = parseAnswer(line) {
                currentAnswers.append(answer)
                continue
            }

            if !currentPrompt.isEmpty, currentAnswers.isEmpty, !startsWithNumberEnumeration(line) {
                currentPrompt += " " + strippedQuestionNumber(line)
            } else {
                finishQuestion()
                currentPrompt = strippedQuestionNumber(line)
            }
        }

        finishQuestion()
        return Quiz(title: "Imported Quiz", questions: questions)
    }

    private func parseQuestion(_ lines: [String], questionNumber: Int) throws -> QuizQuestion {
        var type = QuizQuestionType.multipleChoice
        var prompt = ""
        var answers: [QuizAnswer] = []
        var matches: [MatchingPair] = []
        var feedback = ""

        for line in lines {
            let lowered = line.lowercased()
            if lowered.hasPrefix("type:") {
                type = try parseQuestionType(value(after: ":", in: line))
            } else if lowered.hasPrefix("question:") {
                prompt = value(after: ":", in: line)
            } else if lowered.hasPrefix("feedback:") {
                feedback = value(after: ":", in: line)
            } else if type == .matching, let pair = parseMatchingPair(line) {
                matches.append(pair)
            } else if let answer = parseAnswer(line) {
                answers.append(answer)
            }
        }

        guard !prompt.isEmpty else { throw ParseError.missingPrompt(questionNumber: questionNumber) }

        if type == .trueFalse, answers.isEmpty {
            answers = [QuizAnswer(text: "True"), QuizAnswer(text: "False")]
        }

        return QuizQuestion(type: type, prompt: prompt, answers: answers, matches: matches, feedback: feedback)
    }

    private func parseQuestionType(_ rawValue: String) throws -> QuizQuestionType {
        let normalized = rawValue
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch normalized {
        case "multiple choice", "mc": return .multipleChoice
        case "multiple answer", "multiple answers", "ma": return .multipleAnswer
        case "true false", "true/false", "tf": return .trueFalse
        case "fill in blank", "fill in the blank", "blank": return .fillInBlank
        case "short answer", "short": return .shortAnswer
        case "essay": return .essay
        case "matching", "match": return .matching
        default: throw ParseError.unsupportedType(rawValue)
        }
    }

    private func parseAnswer(_ line: String) -> QuizAnswer? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        for symbol in markerSymbols {
            if let text = correctAnswerText(in: trimmedLine, marker: symbol), !text.isEmpty {
                return QuizAnswer(text: text, isCorrect: true)
            }
        }

        if trimmedLine.hasPrefix("-") || startsWithEnumeration(trimmedLine) {
            let text = stripLeadingAnswerSyntax(trimmedLine)
            guard !text.isEmpty else { return nil }
            return QuizAnswer(text: text, isCorrect: false)
        }

        return nil
    }

    private var markerSymbols: [String] {
        Array(Set([correctAnswerMarker.symbol, "*"]).filter { !$0.isEmpty }).sorted { $0.count > $1.count }
    }

    private func correctAnswerText(in line: String, marker: String) -> String? {
        if line.hasPrefix(marker) {
            return stripLeadingAnswerSyntax(String(line.dropFirst(marker.count)))
        }

        if line.hasSuffix(marker) {
            return stripLeadingAnswerSyntax(String(line.dropLast(marker.count)))
        }

        let withoutEnumeration = stripLeadingEnumeration(line)
        if withoutEnumeration.hasPrefix(marker) {
            return stripLeadingAnswerSyntax(String(withoutEnumeration.dropFirst(marker.count)))
        }

        return nil
    }

    private func parseMatchingPair(_ line: String) -> MatchingPair? {
        let cleanLine = stripLeadingAnswerSyntax(line)
        let parts = cleanLine.components(separatedBy: "=>")
        guard parts.count == 2 else { return nil }

        let prompt = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let match = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !match.isEmpty else { return nil }

        return MatchingPair(prompt: prompt, match: match)
    }

    private func isLikelyAnswerLine(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedLine.hasPrefix("-") || markerSymbols.contains(where: { trimmedLine.hasPrefix($0) }) {
            return true
        }
        return startsWithEnumeration(trimmedLine) && startsWithLetterEnumeration(trimmedLine)
    }

    private func strippedQuestionNumber(_ line: String) -> String {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard startsWithNumberEnumeration(trimmedLine) else { return trimmedLine }
        return stripLeadingEnumeration(trimmedLine)
    }

    private func stripLeadingAnswerSyntax(_ line: String) -> String {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedLine.hasPrefix("-") {
            return String(trimmedLine.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return stripLeadingEnumeration(trimmedLine)
    }

    private func stripLeadingEnumeration(_ line: String) -> String {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstCharacter = trimmedLine.first else { return trimmedLine }

        if firstCharacter == "(", let closeIndex = trimmedLine.firstIndex(of: ")") {
            let candidate = trimmedLine[trimmedLine.index(after: trimmedLine.startIndex)..<closeIndex]
            if isShortEnumerationToken(candidate) {
                return String(trimmedLine[trimmedLine.index(after: closeIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let secondIndex = trimmedLine.index(after: trimmedLine.startIndex)
        guard secondIndex < trimmedLine.endIndex else { return trimmedLine }
        let secondCharacter = trimmedLine[secondIndex]
        if (secondCharacter == "." || secondCharacter == ")") && isEnumerationCharacter(firstCharacter) {
            return String(trimmedLine[trimmedLine.index(after: secondIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmedLine
    }

    private func startsWithEnumeration(_ line: String) -> Bool {
        stripLeadingEnumeration(line) != line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startsWithLetterEnumeration(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstCharacter = trimmedLine.first else { return false }
        if firstCharacter.isLetter {
            return true
        }

        return markerSymbols.contains { marker in
            guard trimmedLine.hasPrefix(marker) else { return false }
            let textAfterMarker = String(trimmedLine.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            guard let firstTextCharacter = textAfterMarker.first else { return false }
            return firstTextCharacter.isLetter
        }
    }

    private func startsWithNumberEnumeration(_ line: String) -> Bool {
        guard let firstCharacter = line.trimmingCharacters(in: .whitespacesAndNewlines).first else { return false }
        return firstCharacter.isNumber
    }

    private func isShortEnumerationToken(_ token: Substring) -> Bool {
        (1...3).contains(token.count) && token.allSatisfy(isEnumerationCharacter)
    }

    private func isEnumerationCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    private func value(after separator: Character, in line: String) -> String {
        guard let separatorIndex = line.firstIndex(of: separator) else { return "" }
        return String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
