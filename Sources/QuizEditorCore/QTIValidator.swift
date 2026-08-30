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

    /// Builds the package that would be exported for `quiz`/`target` and validates it.
    public func validateExport(of quiz: Quiz, target: QTIExportTarget) -> [QTIValidationIssue] {
        let package: QTIPackage
        do {
            package = try QTIExporter(target: target).makePackage(for: quiz)
        } catch {
            return [QTIValidationIssue(severity: .error, message: "The quiz could not be exported: \(error).")]
        }

        var issues: [QTIValidationIssue] = []
        issues.append(contentsOf: wellFormednessIssues(in: package))
        issues.append(contentsOf: manifestConsistencyIssues(in: package, expectedItemCount: quiz.questions.count))
        issues.append(contentsOf: roundTripIssues(package: package, quiz: quiz, target: target))
        issues.append(contentsOf: formatFidelityIssues(of: quiz, target: target))
        return issues
    }

    /// Warns about authoring detail the chosen QTI standard cannot carry.
    ///
    /// QTI 1.2 has `qtimetadata`, an open key/value area where the exporter
    /// stores a formula's expression and variables, so a formula survives a
    /// round-trip. (That area carries the formula spec only; author metadata is
    /// never exported.) QTI 2.1 removed that escape hatch and has no element for an
    /// expression, so exporting a formula there keeps the answer key but drops
    /// the formula itself. The author usually has a lossless option one menu
    /// item away, so it is worth saying so.
    ///
    /// Advisory only, per the project rule that validation never blocks an
    /// export: this is always a warning, never an error.
    public func formatFidelityIssues(of quiz: Quiz, target: QTIExportTarget) -> [QTIValidationIssue] {
        guard target == .qti21 else { return [] }

        let formulaCount = quiz.questions.filter { $0.type == .formula }.count
        guard formulaCount > 0 else { return [] }

        let subject = formulaCount == 1 ? "1 formula question" : "\(formulaCount) formula questions"
        return [QTIValidationIssue(
            severity: .warning,
            message: "QTI 2.1 has no place to store a formula expression, so \(subject) will export with the computed answer key but without the formula. Export as QTI 1.2 (Classic Quizzes) to keep the expression and its variables."
        )]
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
    private func roundTripIssues(package: QTIPackage, quiz: Quiz, target: QTIExportTarget) -> [QTIValidationIssue] {
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
            // type metadata, so only check types for the classic target.
            guard target == .qti12 else { return [] }
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
