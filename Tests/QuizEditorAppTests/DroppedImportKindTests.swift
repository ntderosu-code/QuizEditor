import XCTest
@testable import QuizEditorApp

final class DroppedImportKindTests: XCTestCase {
    private func kind(_ filename: String) -> DroppedImportKind? {
        DroppedImportKind(url: URL(fileURLWithPath: "/tmp/\(filename)"))
    }

    func testRecognizesEachSupportedImportFormat() {
        XCTAssertEqual(kind("bank.zip"), .qtiPackage)
        XCTAssertEqual(kind("course.imscc"), .commonCartridge)
        XCTAssertEqual(kind("midterm.quizeditor"), .quizDocument)
    }

    func testExtensionMatchingIgnoresCase() {
        XCTAssertEqual(kind("BANK.ZIP"), .qtiPackage)
        XCTAssertEqual(kind("Course.IMSCC"), .commonCartridge)
        XCTAssertEqual(kind("Midterm.QuizEditor"), .quizDocument)
    }

    func testRejectsFormatsTheImportersCannotRead() {
        XCTAssertNil(kind("notes.pdf"))
        XCTAssertNil(kind("questions.docx"))
        XCTAssertNil(kind("README"))
    }

    /// The drop handler routes a mixed drop to a single importer, so the order
    /// decides which one wins. Quiz documents merge, packages import.
    func testFirstImportableURLWinsInAMixedDrop() {
        let urls = [
            URL(fileURLWithPath: "/tmp/readme.txt"),
            URL(fileURLWithPath: "/tmp/course.imscc"),
            URL(fileURLWithPath: "/tmp/bank.zip")
        ]
        let first = urls.compactMap { url in DroppedImportKind(url: url).map { ($0, url) } }.first
        XCTAssertEqual(first?.0, .commonCartridge)
    }
}
