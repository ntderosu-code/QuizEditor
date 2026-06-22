import XCTest
@testable import QuizEditorApp

final class RichTextToolbarTests: XCTestCase {
    func testInsertActionsUseDiscoverableOrderAndLabels() {
        XCTAssertEqual(RichTextInsertAction.allCases, [.link, .table, .image])
        XCTAssertEqual(RichTextInsertAction.link.title, "Link")
        XCTAssertEqual(RichTextInsertAction.table.title, "Table")
        XCTAssertEqual(RichTextInsertAction.image.title, "Image")
    }

    func testToolbarButtonsHaveLargerHitTargetsThanTheirVisualIcons() {
        XCTAssertGreaterThanOrEqual(RichTextToolbarMetrics.buttonMinWidth, 32)
        XCTAssertGreaterThanOrEqual(RichTextToolbarMetrics.buttonMinHeight, 30)
    }
}
