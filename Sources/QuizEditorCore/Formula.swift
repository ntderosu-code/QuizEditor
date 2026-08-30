import Foundation

/// A single variable the author defines for a formula question, with the value
/// that will be substituted into the expression at runtime (Canvas's "formulas"
/// feature lets the author randomize from a set of permitted values per
/// variable; the simplified model here ships one fixed value per variable and
/// is portable to both Classic `calculated_question` and New Quizzes' numeric
/// formula item).
public struct FormulaVariable: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var value: Double

    public init(id: String = UUID().uuidString, name: String, value: Double) {
        self.id = id
        self.name = name
        self.value = value
    }
}

/// The grading spec for a formula (calculated) question.
///
/// `expectedUnit` is **tool-only** authoring metadata — QTI has no gradeable
/// unit concept, so it is never written into an export. It exists for the
/// linter and AI.
public struct FormulaAnswer: Codable, Sendable, Equatable {
    public var variables: [FormulaVariable]
    public var expression: String
    /// Absolute tolerance for grading the computed result (0 = exact match).
    public var tolerance: Double
    /// Advisory only — never exported.
    public var expectedUnit: String?

    public init(
        variables: [FormulaVariable] = [],
        expression: String = "",
        tolerance: Double = 0,
        expectedUnit: String? = nil
    ) {
        self.variables = variables
        self.expression = expression
        self.tolerance = tolerance
        self.expectedUnit = expectedUnit
    }

    /// The result of substituting the variable values into the expression using
    /// a tiny, predictable evaluator: `*`, `/`, `+`, `-`, parentheses, and the
    /// variable names. Empty/malformed expressions, and any result that is not
    /// finite (division by a zero-valued variable), return `nil` so the exporter
    /// can fall back to the unconfigured condition. The evaluator is intentionally
    /// minimal — Canvas evaluates the full expression server-side; we only need
    /// enough here to produce a representative numeric value for the answer key.
    public var computedValue: Double? {
        FormulaEvaluator.evaluate(expression: expression, variables: variables)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        variables = try c.decodeIfPresent([FormulaVariable].self, forKey: .variables) ?? []
        expression = try c.decodeIfPresent(String.self, forKey: .expression) ?? ""
        tolerance = try c.decodeIfPresent(Double.self, forKey: .tolerance) ?? 0
        expectedUnit = try c.decodeIfPresent(String.self, forKey: .expectedUnit)
    }

    private enum CodingKeys: String, CodingKey {
        case variables, expression, tolerance, expectedUnit
    }
}

/// Tiny recursive-descent expression evaluator for formula questions. Supports
/// the four basic arithmetic operators, parentheses, and variable references
/// (any other token is an error). Not a full language; the formula author is
/// expected to write simple expressions.
enum FormulaEvaluator {
    static func evaluate(expression: String, variables: [FormulaVariable]) -> Double? {
        let tokens = tokenize(expression)
        var index = 0
        guard let value = parseExpression(tokens: tokens, index: &index, variables: variables),
              index == tokens.count else {
            return nil
        }
        // Dividing by a zero-valued variable produces infinity or NaN. That is not
        // a usable answer key, and the whole-number formatters downstream would
        // trap converting it to Int, so treat it the same as a malformed
        // expression: unconfigured.
        guard value.isFinite else { return nil }
        return value
    }

    private enum Token: Equatable {
        case number(Double)
        case name(String)
        case plus, minus, mul, div
        case lparen, rparen
    }

    private static func tokenize(_ source: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        for character in source {
            if character.isWhitespace {
                flushName(&current, into: &tokens)
                continue
            }
            switch character {
            case "+": flushName(&current, into: &tokens); tokens.append(.plus)
            case "-": flushName(&current, into: &tokens); tokens.append(.minus)
            case "*": flushName(&current, into: &tokens); tokens.append(.mul)
            case "/": flushName(&current, into: &tokens); tokens.append(.div)
            case "(": flushName(&current, into: &tokens); tokens.append(.lparen)
            case ")": flushName(&current, into: &tokens); tokens.append(.rparen)
            default: current.append(character)
            }
        }
        flushName(&current, into: &tokens)
        return tokens
    }

    private static func flushName(_ buffer: inout String, into tokens: inout [Token]) {
        guard !buffer.isEmpty else { return }
        if let value = Double(buffer) {
            tokens.append(.number(value))
        } else {
            tokens.append(.name(buffer))
        }
        buffer.removeAll(keepingCapacity: true)
    }

    // expression = term ((+|-) term)*
    private static func parseExpression(tokens: [Token], index: inout Int, variables: [FormulaVariable]) -> Double? {
        guard var left = parseTerm(tokens: tokens, index: &index, variables: variables) else { return nil }
        while index < tokens.count {
            let op: (Double, Double) -> Double
            switch tokens[index] {
            case .plus: op = (+); index += 1
            case .minus: op = (-); index += 1
            default: return left
            }
            guard let right = parseTerm(tokens: tokens, index: &index, variables: variables) else { return nil }
            left = op(left, right)
        }
        return left
    }

    // term = factor ((*|/) factor)*
    private static func parseTerm(tokens: [Token], index: inout Int, variables: [FormulaVariable]) -> Double? {
        guard var left = parseFactor(tokens: tokens, index: &index, variables: variables) else { return nil }
        while index < tokens.count {
            let op: (Double, Double) -> Double
            switch tokens[index] {
            case .mul: op = (*); index += 1
            case .div: op = (/); index += 1
            default: return left
            }
            guard let right = parseFactor(tokens: tokens, index: &index, variables: variables) else { return nil }
            left = op(left, right)
        }
        return left
    }

    private static func parseFactor(tokens: [Token], index: inout Int, variables: [FormulaVariable]) -> Double? {
        guard index < tokens.count else { return nil }
        switch tokens[index] {
        case .number(let value):
            index += 1
            return value
        case .name(let identifier):
            index += 1
            return variables.first { $0.name == identifier }?.value
        case .minus:
            index += 1
            return parseFactor(tokens: tokens, index: &index, variables: variables).map { -$0 }
        case .plus:
            index += 1
            return parseFactor(tokens: tokens, index: &index, variables: variables)
        case .lparen:
            index += 1
            let value = parseExpression(tokens: tokens, index: &index, variables: variables)
            if index < tokens.count, case .rparen = tokens[index] { index += 1 }
            return value
        case .rparen, .mul, .div:
            return nil
        }
    }
}
