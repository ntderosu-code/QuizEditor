import Foundation

/// One problem found while validating a QTI export.
public struct QTIValidationIssue: Equatable, Sendable, Identifiable {
    public enum Severity: Sendable, Equatable {
        /// The package is malformed or loses data — fix before relying on it.
        case error
        /// The package is usable but something is worth knowing.
        case warning
    }

    public let severity: Severity
    public let message: String

    public var id: String { "\(severity)|\(message)" }

    public init(severity: Severity, message: String) {
        self.severity = severity
        self.message = message
    }
}

/// Validates a Canvas QTI export: every file is well-formed XML, the manifest and
/// item files agree, and — the real proof — the package re-imports cleanly with
/// the same questions. This exercises both the export and import code paths.
public struct QTIValidator: Sendable {
    public init() {}

    /// Builds the package that would be exported for `quiz`/`engine` and validates it.
    public func validateExport(of quiz: Quiz, engine: CanvasQuizEngine) -> [QTIValidationIssue] {
        let package: QTIPackage
        do {
            package = try CanvasQTIExporter(engine: engine).makePackage(for: quiz)
        } catch {
            return [QTIValidationIssue(severity: .error, message: "The quiz could not be exported: \(error).")]
        }

        var issues: [QTIValidationIssue] = []
        issues.append(contentsOf: wellFormednessIssues(in: package))
        issues.append(contentsOf: manifestConsistencyIssues(in: package, expectedItemCount: quiz.questions.count))
        issues.append(contentsOf: roundTripIssues(package: package, quiz: quiz, engine: engine))
        return issues
    }

    /// Checks that every file in the package parses as well-formed XML.
    public func wellFormednessIssues(in package: QTIPackage) -> [QTIValidationIssue] {
        package.files.compactMap { file in
            guard let data = file.contents.data(using: .utf8) else {
                return QTIValidationIssue(severity: .error, message: "\(file.path) is not valid UTF-8.")
            }
            do {
                _ = try XMLDocument(data: data, options: [])
                return nil
            } catch {
                return QTIValidationIssue(severity: .error, message: "\(file.path) is not well-formed XML: \(error.localizedDescription)")
            }
        }
    }

    /// Checks the manifest exists, references each item file, and that the item
    /// file count matches the number of questions.
    public func manifestConsistencyIssues(in package: QTIPackage, expectedItemCount: Int) -> [QTIValidationIssue] {
        var issues: [QTIValidationIssue] = []

        guard let manifest = package.file(named: "imsmanifest.xml") else {
            return [QTIValidationIssue(severity: .error, message: "The package has no imsmanifest.xml.")]
        }
        if package.file(named: "assessment.xml") == nil {
            issues.append(QTIValidationIssue(severity: .error, message: "The package has no assessment.xml."))
        }

        let itemFiles = package.files.filter { $0.path.hasPrefix("items/") }
        if itemFiles.count != expectedItemCount {
            issues.append(QTIValidationIssue(
                severity: .error,
                message: "Expected \(expectedItemCount) item file(s) but the package contains \(itemFiles.count)."
            ))
        }
        for item in itemFiles where !manifest.contents.contains(item.path) {
            issues.append(QTIValidationIssue(severity: .warning, message: "\(item.path) is not referenced by the manifest."))
        }

        return issues
    }

    /// Writes the package to a temporary directory, re-imports it, and confirms
    /// the questions survive the round trip.
    private func roundTripIssues(package: QTIPackage, quiz: Quiz, engine: CanvasQuizEngine) -> [QTIValidationIssue] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for file in package.files {
                let fileURL = directory.appendingPathComponent(file.path)
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(file.contents.utf8).write(to: fileURL)
            }

            let reimported = try QTIImporter(preserveFormatting: true).importQuiz(fromDirectory: directory)

            if reimported.questions.count != quiz.questions.count {
                return [QTIValidationIssue(
                    severity: .error,
                    message: "Round-trip mismatch: exported \(quiz.questions.count) question(s) but re-imported \(reimported.questions.count)."
                )]
            }

            // Classic QTI 1.2 preserves the Canvas question type; QTI 2.1 has no
            // type metadata, so only check types for the classic engine.
            guard engine == .classicQuizzes else { return [] }
            var issues: [QTIValidationIssue] = []
            for (index, pair) in zip(quiz.questions, reimported.questions).enumerated() where pair.0.type != pair.1.type {
                issues.append(QTIValidationIssue(
                    severity: .warning,
                    message: "Question \(index + 1) changed type on round-trip: \(pair.0.type.displayName) → \(pair.1.type.displayName)."
                ))
            }
            return issues
        } catch {
            return [QTIValidationIssue(severity: .warning, message: "Round-trip check could not run: \(error.localizedDescription).")]
        }
    }
}
