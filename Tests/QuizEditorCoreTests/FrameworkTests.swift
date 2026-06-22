import XCTest
@testable import QuizEditorCore

/// #25: a structured, user-editable competency/standards framework taxonomy that
/// questions link to. These cover the data model, the built-in starter, and
/// import validation.
final class FrameworkTests: XCTestCase {
    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func testFrameworkRoundTripsWithNestedNodes() throws {
        let framework = Framework(
            id: "user.torts",
            name: "Torts",
            source: "Law School",
            version: 1,
            nodes: [
                FrameworkNode(id: "n1", code: "1", label: "Negligence"),
                FrameworkNode(id: "n2", code: "1.1", label: "Proximate Cause", parentID: "n1")
            ]
        )
        XCTAssertEqual(try roundTrip(framework), framework)
    }

    func testBuiltInBloomFrameworkHasSixLevels() {
        let bloom = Framework.bloom
        XCTAssertTrue(bloom.isBuiltIn)
        XCTAssertEqual(bloom.nodes.count, 6)
        XCTAssertTrue(bloom.nodes.contains { $0.label == "Apply" })
    }

    func testFrameworkSavedBeforeFieldsExistedStillDecodes() throws {
        // A minimal framework JSON: only id and name, no nodes/source/version.
        let legacy = """
        { "id": "f1", "name": "Minimal" }
        """.data(using: .utf8)!
        let framework = try JSONDecoder().decode(Framework.self, from: legacy)
        XCTAssertEqual(framework.id, "f1")
        XCTAssertEqual(framework.nodes, [])
        XCTAssertFalse(framework.isBuiltIn)
    }

    func testImportAcceptsValidFrameworkAndFlagsUnknownKeys() throws {
        let json = """
        { "id": "user.imported", "name": "Imported", "futureField": 1 }
        """
        let result = try Framework.importResult(fromJSON: Data(json.utf8))
        XCTAssertEqual(result.framework.id, "user.imported")
        XCTAssertTrue(result.warnings.contains { $0.contains("futureField") })
    }

    func testImportRejectsFrameworkMissingRequiredFields() {
        let json = """
        { "source": "nowhere" }
        """
        XCTAssertThrowsError(try Framework.importResult(fromJSON: Data(json.utf8)))
    }

    func testNodeChildrenAndPathHelpers() {
        let framework = Framework(
            id: "f", name: "F",
            nodes: [
                FrameworkNode(id: "a", code: "A", label: "Alpha"),
                FrameworkNode(id: "b", code: "A.1", label: "Beta", parentID: "a")
            ]
        )
        XCTAssertEqual(framework.children(of: nil).map(\.id), ["a"])
        XCTAssertEqual(framework.children(of: "a").map(\.id), ["b"])
        XCTAssertEqual(framework.node(withID: "b")?.label, "Beta")
    }
}
