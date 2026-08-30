import XCTest
@testable import QuizEditorCore

/// Every error the app surfaces reaches the user through `localizedDescription`
/// in an alert. Without `LocalizedError`, Foundation ignores a type's own
/// `description` and produces "The operation couldn't be completed.
/// (QuizEditorCore.QTIImporter.ImportError error 2.)" — an enum ordinal in an
/// alert. These tests pin the written sentence to what the user actually sees.
final class ErrorMessageTests: XCTestCase {
    /// Foundation reads `errorDescription` off `LocalizedError`; anything else
    /// falls back to the "couldn't be completed" boilerplate.
    private func assertUserFacing(
        _ error: some Error,
        equals expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(error.localizedDescription, expected, file: file, line: line)
        XCTAssertFalse(
            error.localizedDescription.contains("couldn’t be completed"),
            "\(type(of: error)) is leaking Foundation's boilerplate to the user",
            file: file,
            line: line
        )
    }

    func testQTIImportErrorsReadAsSentences() {
        assertUserFacing(
            QTIImporter.ImportError.manifestNotFound,
            equals: "The archive does not contain an imsmanifest.xml file."
        )
        assertUserFacing(
            QTIImporter.ImportError.noQuestionsFound,
            equals: "No supported quiz questions were found in the QTI archive."
        )
        assertUserFacing(
            QTIImporter.ImportError.unzipFailed(status: 9),
            equals: "The QTI archive could not be expanded. unzip exited with status 9."
        )
        assertUserFacing(
            QTIImporter.ImportError.missingUnzipExecutable,
            equals: "The system unzip command is unavailable."
        )
    }

    func testPackageWriterErrorsReadAsSentences() {
        assertUserFacing(
            QTIPackageWriter.WriterError.missingZipExecutable,
            equals: "The system zip command is unavailable."
        )
        assertUserFacing(
            QTIPackageWriter.WriterError.zipCommandFailed(status: 3),
            equals: "The zip command failed with status 3."
        )
    }

    func testMarkedTextParseErrorsReadAsSentences() {
        let error = MarkedTextParser.ParseError.missingTitle
        assertUserFacing(error, equals: String(describing: error))
    }

    func testAIErrorsReadAsSentences() {
        let validation = AIConfiguration.ValidationError.missingAPIKey
        assertUserFacing(validation, equals: String(describing: validation))

        let client = AIClient.ClientError.missingContent
        assertUserFacing(client, equals: String(describing: client))
    }

    func testExportErrorsReadAsSentences() {
        assertUserFacing(
            QTIExporter.ExportError.emptyQuizTitle,
            equals: "The quiz needs a title before it can be exported."
        )
        assertUserFacing(
            QTIExporter.ExportError.noQuestions,
            equals: "The quiz has no questions to export."
        )
    }
}
