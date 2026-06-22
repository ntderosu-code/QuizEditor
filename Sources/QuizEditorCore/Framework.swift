import Foundation

/// A competency/standards framework taxonomy (#25) that questions link to via
/// `QuizQuestion.competencyIDs`, distinct from free-form tags. Frameworks are
/// data: a built-in starter ships in code, users import or author their own
/// locally. Advisory metadata only — never written into an export, never networked.
///
/// Every type decodes tolerantly, mirroring the rest of the model, so a framework
/// saved against an older schema keeps loading.

/// One node in a framework. Nests via `parentID` (nil = top level), so a taxonomy
/// like Torts > Negligence > Proximate Cause is a flat list with parent links.
public struct FrameworkNode: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    /// A short code/number shown alongside the label, e.g. "1.1" or "EPAS 2".
    public var code: String
    public var label: String
    public var parentID: String?

    public init(id: String = UUID().uuidString, code: String = "", label: String = "", parentID: String? = nil) {
        self.id = id
        self.code = code
        self.label = label
        self.parentID = parentID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        parentID = try c.decodeIfPresent(String.self, forKey: .parentID)
    }

    private enum CodingKeys: String, CodingKey { case id, code, label, parentID }

    /// A label for chips and pickers: "code — label" when a code is present.
    public var displayLabel: String {
        code.trimmingCharacters(in: .whitespaces).isEmpty ? label : "\(code) — \(label)"
    }
}

public struct Framework: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var source: String
    public var version: Int
    public var nodes: [FrameworkNode]
    public var isBuiltIn: Bool

    public init(
        id: String,
        name: String,
        source: String = "",
        version: Int = 1,
        nodes: [FrameworkNode] = [],
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.version = version
        self.nodes = nodes
        self.isBuiltIn = isBuiltIn
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // id and name are required; everything else falls back to a default.
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        nodes = try c.decodeIfPresent([FrameworkNode].self, forKey: .nodes) ?? []
        isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
    }

    private enum CodingKeys: String, CodingKey { case id, name, source, version, nodes, isBuiltIn }

    // MARK: - Tree helpers

    /// The nodes whose parent is `parentID` (pass nil for the top level), in order.
    public func children(of parentID: String?) -> [FrameworkNode] {
        nodes.filter { $0.parentID == parentID }
    }

    public func node(withID id: String) -> FrameworkNode? {
        nodes.first { $0.id == id }
    }
}

// MARK: - Built-in starter

public extension Framework {
    /// A recognizable built-in starter so coverage works out of the box; users
    /// import or author discipline frameworks for the rest.
    static let bloom = Framework(
        id: "app.quizeditor.framework.bloom",
        name: "Bloom's Revised Taxonomy",
        source: "Anderson & Krathwohl, 2001",
        version: 1,
        nodes: [
            FrameworkNode(id: "bloom.remember", code: "1", label: "Remember"),
            FrameworkNode(id: "bloom.understand", code: "2", label: "Understand"),
            FrameworkNode(id: "bloom.apply", code: "3", label: "Apply"),
            FrameworkNode(id: "bloom.analyze", code: "4", label: "Analyze"),
            FrameworkNode(id: "bloom.evaluate", code: "5", label: "Evaluate"),
            FrameworkNode(id: "bloom.create", code: "6", label: "Create")
        ],
        isBuiltIn: true
    )
}

// MARK: - Import

public struct FrameworkImportResult: Sendable {
    public let framework: Framework
    public let warnings: [String]

    public init(framework: Framework, warnings: [String]) {
        self.framework = framework
        self.warnings = warnings
    }
}

public extension Framework {
    private static let knownKeys: Set<String> = ["id", "name", "source", "version", "nodes", "isBuiltIn"]

    /// Decodes a framework from `.qeframework`/JSON, warning about unknown top-level
    /// keys (forward-compatible). Throws only when `id`/`name` are missing.
    static func importResult(fromJSON data: Data) throws -> FrameworkImportResult {
        let framework = try JSONDecoder().decode(Framework.self, from: data)
        var warnings: [String] = []
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let unknown = object.keys.filter { !knownKeys.contains($0) }.sorted()
            if !unknown.isEmpty {
                warnings.append("Ignored unknown field\(unknown.count == 1 ? "" : "s"): \(unknown.joined(separator: ", ")). They may be from a newer version of QuizEditor.")
            }
        }
        return FrameworkImportResult(framework: framework, warnings: warnings)
    }
}
