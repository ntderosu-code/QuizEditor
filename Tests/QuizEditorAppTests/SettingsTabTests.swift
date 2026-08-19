import XCTest
@testable import QuizEditorApp

final class SettingsTabTests: XCTestCase {
    func testGeneralComesFirstSoSettingsOpensOnTheAppWideChoice() {
        XCTAssertEqual(SettingsTab.allCases, [.general, .ai])
    }

    func testTabsUsePlainUserFacingTitles() {
        XCTAssertEqual(SettingsTab.general.title, "General")
        XCTAssertEqual(SettingsTab.ai.title, "AI")
    }

    /// The stored raw values back an @AppStorage selection, so renaming one would
    /// silently reset every user's chosen pane.
    func testRawValuesAreStableStorageKeys() {
        XCTAssertEqual(SettingsTab.general.rawValue, "general")
        XCTAssertEqual(SettingsTab.ai.rawValue, "ai")
        XCTAssertEqual(SettingsTab(rawValue: "ai"), .ai)
    }
}
