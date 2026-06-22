import Foundation

/// How a numeric question is graded. The three modes are the portable subset
/// supported by both Canvas engines (Classic `numerical_question` and New Quizzes
/// Numeric): an exact value with an absolute margin, an inclusive range, or a
/// value to a number of significant digits.
public enum NumericGradingMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case exact
    case range
    case precision

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .exact: "Exact (± margin)"
        case .range: "Range"
        case .precision: "Precision (digits)"
        }
    }
}

/// The grading spec for a numeric question, plus an advisory expected unit.
///
/// The unit is **tool-only** authoring metadata: QTI and Canvas have no gradeable
/// unit concept, so it is never written into an export. It exists for the linter
/// and AI (e.g. the chemistry "missing units" guidance).
public struct NumericAnswer: Codable, Sendable, Equatable {
    public var mode: NumericGradingMode
    public var value: Double?
    /// Absolute tolerance for `.exact` (0 = exact match).
    public var margin: Double?
    public var rangeMin: Double?
    public var rangeMax: Double?
    /// Significant digits for `.precision`.
    public var precisionDigits: Int?
    /// Advisory only — never exported. Shown in the UI as tool-only.
    public var expectedUnit: String?

    public init(
        mode: NumericGradingMode = .exact,
        value: Double? = nil,
        margin: Double? = nil,
        rangeMin: Double? = nil,
        rangeMax: Double? = nil,
        precisionDigits: Int? = nil,
        expectedUnit: String? = nil
    ) {
        self.mode = mode
        self.value = value
        self.margin = margin
        self.rangeMin = rangeMin
        self.rangeMax = rangeMax
        self.precisionDigits = precisionDigits
        self.expectedUnit = expectedUnit
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(NumericGradingMode.self, forKey: .mode) ?? .exact
        value = try c.decodeIfPresent(Double.self, forKey: .value)
        margin = try c.decodeIfPresent(Double.self, forKey: .margin)
        rangeMin = try c.decodeIfPresent(Double.self, forKey: .rangeMin)
        rangeMax = try c.decodeIfPresent(Double.self, forKey: .rangeMax)
        precisionDigits = try c.decodeIfPresent(Int.self, forKey: .precisionDigits)
        expectedUnit = try c.decodeIfPresent(String.self, forKey: .expectedUnit)
    }

    private enum CodingKeys: String, CodingKey {
        case mode, value, margin, rangeMin, rangeMax, precisionDigits, expectedUnit
    }

    /// True when there's enough to grade against.
    public var isConfigured: Bool {
        switch mode {
        case .exact, .precision: value != nil
        case .range: rangeMin != nil && rangeMax != nil
        }
    }

    /// The inclusive accepted interval, when the mode defines one. Used by the
    /// exporters to emit gte/lte conditions.
    public var acceptedInterval: (low: Double, high: Double)? {
        switch mode {
        case .exact:
            guard let value else { return nil }
            let m = abs(margin ?? 0)
            return (value - m, value + m)
        case .range:
            guard let low = rangeMin, let high = rangeMax else { return nil }
            return (Swift.min(low, high), Swift.max(low, high))
        case .precision:
            return nil
        }
    }
}
