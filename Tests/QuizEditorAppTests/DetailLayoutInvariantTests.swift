import XCTest

/// Guards the layout decision behind #97.
///
/// `.inspector` on the `NavigationSplitView` put AppKit into a constraint-update
/// loop ("more Update Constraints in Window passes than there are views in the
/// window") that destroyed the window the moment the sidebar divider was
/// dragged, with the AI panel open. Isolating it showed the trigger was neither
/// our panel's content nor an over-constrained set of column widths: replacing
/// the whole inspector body with a single `Text` still crashed, and so did
/// pinning the sidebar and raising the window minimum so three columns always
/// fit. The AI panel is now an ordinary `HSplitView` child of the detail column.
///
/// This is a source-level invariant because the failure is a runtime layout
/// loop: it cannot be caught by exercising types, only by not reintroducing the
/// modifier. `Scripts/ui-crash-regression.sh` covers the runtime side.
final class DetailLayoutInvariantTests: XCTestCase {
    private var appSourceDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // QuizEditorAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
            .appendingPathComponent("Sources/QuizEditorApp", isDirectory: true)
    }

    /// Code only. The comments in these files name the very modifiers this test
    /// bans, to explain why they are banned.
    private func codeWithoutComments(of source: URL) throws -> String {
        try String(contentsOf: source, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let comment = line.range(of: "//") else { return line }
                return line[line.startIndex..<comment.lowerBound]
            }
            .joined(separator: "\n")
    }

    private func swiftSources() throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: appSourceDirectory,
            includingPropertiesForKeys: nil
        )
        let sources = contents.filter { $0.pathExtension == "swift" }
        XCTAssertFalse(sources.isEmpty, "found no app sources at \(appSourceDirectory.path)")
        return sources
    }

    func testAppDoesNotUseTheInspectorModifier() throws {
        for source in try swiftSources() {
            let code = try codeWithoutComments(of: source)
            XCTAssertFalse(
                code.contains(".inspector("),
                """
                \(source.lastPathComponent) uses `.inspector(`, which crashes the \
                window when the sidebar divider is dragged (#97). The AI panel \
                belongs in the detail column's HSplitView.
                """
            )
            XCTAssertFalse(
                code.contains(".inspectorColumnWidth("),
                """
                \(source.lastPathComponent) uses `.inspectorColumnWidth(`, which \
                only applies to `.inspector` (#97). Size the panel with `.frame`.
                """
            )
        }
    }

    /// The other half of #96: one toolbar identifier shared by every document
    /// window made AppKit re-insert SwiftUI's sidebar-toggle item into a toolbar
    /// that already had it, and File ▸ New died on the duplicate.
    func testAppDoesNotGiveTheToolbarASharedIdentifier() throws {
        for source in try swiftSources() {
            let code = try codeWithoutComments(of: source)
            XCTAssertFalse(
                code.contains(".toolbar(id:"),
                """
                \(source.lastPathComponent) uses `.toolbar(id:`. Every document \
                window then shares one toolbar identifier and File ▸ New crashes \
                on a duplicate sidebar-toggle item (#96).
                """
            )
        }
    }
}
