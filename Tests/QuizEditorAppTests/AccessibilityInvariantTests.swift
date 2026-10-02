import XCTest

final class AccessibilityInvariantTests: XCTestCase {
    private var appSourceDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/QuizEditorApp", isDirectory: true)
    }

    private func source(named name: String) throws -> String {
        let url = appSourceDirectory.appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let comment = line.range(of: "//") else { return line }
                return line[line.startIndex..<comment.lowerBound]
            }
            .joined(separator: "\n")
    }

    func testRichTextEditorExposesMultilineTextboxSemantics() throws {
        let code = try source(named: "RichTextViews.swift")

        XCTAssertTrue(code.contains("role=\"textbox\""))
        XCTAssertTrue(code.contains("aria-multiline=\"true\""))
        XCTAssertTrue(code.contains("aria-label=\"\\(escapedLabel)\""))
        XCTAssertTrue(code.contains("spellcheck=\"true\""))
    }

    func testDisclosureLabelsUseNativeDisclosureActivation() throws {
        let metadataCode = try source(named: "QuestionMetadataEditor.swift")
        let appCode = try source(named: "QuizEditorApp.swift")

        XCTAssertFalse(metadataCode.contains("onTapGesture { isExpanded.toggle() }"))
        XCTAssertFalse(appCode.contains("onTapGesture { isExpanded.toggle() }"))
    }

    func testQuestionPromptsAreNotHardTruncatedInNavigators() throws {
        let sidebarCode = try source(named: "SidebarViews.swift")
        let quickSwitchCode = try source(named: "QuickSwitchSheet.swift")

        XCTAssertFalse(sidebarCode.contains("Text(plainPrompt)\n                    .font(.body)\n                    .lineLimit(2)"))
        XCTAssertFalse(quickSwitchCode.contains("Text(plainPrompt(entry.question))\n                                            .lineLimit(1)"))
    }
}
