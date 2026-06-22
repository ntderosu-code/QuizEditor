import Foundation

/// A coverage/blueprint report (#25): how a quiz's questions map onto one or more
/// competency frameworks, which nodes have no items (gaps), how many questions map
/// to nothing, and the cognitive-level balance drawn from linked objectives. Pure
/// data, computed locally — used by the Quality Check coverage view.
public struct CoverageReport: Sendable, Equatable {
    public struct NodeCoverage: Sendable, Equatable, Identifiable {
        public let frameworkID: String
        public let frameworkName: String
        public let node: FrameworkNode
        public let questionCount: Int

        public var id: String { "\(frameworkID)/\(node.id)" }
    }

    public let nodeCoverage: [NodeCoverage]
    public let unmappedQuestionCount: Int
    public let totalQuestions: Int
    public let cognitiveLevelCounts: [CognitiveLevel: Int]

    public init(
        nodeCoverage: [NodeCoverage],
        unmappedQuestionCount: Int,
        totalQuestions: Int,
        cognitiveLevelCounts: [CognitiveLevel: Int]
    ) {
        self.nodeCoverage = nodeCoverage
        self.unmappedQuestionCount = unmappedQuestionCount
        self.totalQuestions = totalQuestions
        self.cognitiveLevelCounts = cognitiveLevelCounts
    }

    /// Nodes no question maps to.
    public var gaps: [NodeCoverage] { nodeCoverage.filter { $0.questionCount == 0 } }

    /// Builds the report for a quiz against the supplied frameworks.
    public static func make(quiz: Quiz, frameworks: [Framework]) -> CoverageReport {
        var nodeCoverage: [NodeCoverage] = []
        for framework in frameworks {
            for node in framework.nodes {
                let count = quiz.questions.filter { $0.competencyIDs.contains(node.id) }.count
                nodeCoverage.append(NodeCoverage(
                    frameworkID: framework.id,
                    frameworkName: framework.name,
                    node: node,
                    questionCount: count
                ))
            }
        }

        let unmapped = quiz.questions.filter { $0.competencyIDs.isEmpty }.count

        let objectivesByID = Dictionary(quiz.objectives.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var cognitiveCounts: [CognitiveLevel: Int] = [:]
        for question in quiz.questions {
            for objectiveID in question.objectiveIDs {
                if let level = objectivesByID[objectiveID]?.cognitiveLevel {
                    cognitiveCounts[level, default: 0] += 1
                }
            }
        }

        return CoverageReport(
            nodeCoverage: nodeCoverage,
            unmappedQuestionCount: unmapped,
            totalQuestions: quiz.questions.count,
            cognitiveLevelCounts: cognitiveCounts
        )
    }
}
