import XCTest

/// Guards the crash that killed the app after every paper exam PDF export.
///
/// `PaperExamPDFExporter` conforms to `WKNavigationDelegate`, which is
/// `@MainActor` in the SDK, so Swift infers main-actor isolation for the whole
/// class. AppKit, however, calls the print operation's `didRun:` selector from
/// the thread running the modal operation, and Swift 6's executor check traps:
///
///     _dispatch_assert_queue_fail
///     swift_task_checkIsolatedSwift
///     @objc PaperExamPDFExporter.printOperationDidRun(_:success:contextInfo:)
///     -[NSConcretePrintOperation _finishModalOperation]
///
/// The PDF is written before the trap, so the export looks like it worked right
/// up until the app disappears. The callback must therefore be `nonisolated` and
/// hop to the main actor itself.
///
/// This is a source-level invariant: the trap only fires inside a real AppKit
/// print operation, which no unit test can drive.
final class PrintOperationIsolationTests: XCTestCase {
    private var exporterSource: String {
        get throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/QuizEditorApp/PaperExamPDFExporter.swift")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    func testPrintOperationCallbackIsNonisolated() throws {
        let code = try exporterSource
        guard let declaration = code.range(of: "func printOperationDidRun(") else {
            return XCTFail("PaperExamPDFExporter no longer declares printOperationDidRun")
        }
        let line = code[code.lineRange(for: declaration)]
        XCTAssertTrue(
            line.contains("nonisolated"),
            """
            printOperationDidRun must be nonisolated. AppKit calls it off the \
            main thread, and main-actor isolation makes Swift 6 trap there, \
            killing the app after the PDF is written.
            """
        )
    }
}
