import Foundation

public struct QTIPackageWriter: Sendable {
    public enum WriterError: Error, Equatable, CustomStringConvertible {
        case zipCommandFailed(status: Int32)
        case missingZipExecutable

        public var description: String {
            switch self {
            case .zipCommandFailed(let status):
                "The zip command failed with status \(status)."
            case .missingZipExecutable:
                "The system zip command is unavailable."
            }
        }
    }

    private let exporter: CanvasQTIExporter

    public init(exporter: CanvasQTIExporter = CanvasQTIExporter()) {
        self.exporter = exporter
    }

    public init(engine: CanvasQuizEngine) {
        self.exporter = CanvasQTIExporter(engine: engine)
    }

    public func writeZip(for quiz: Quiz, to outputURL: URL) throws {
        let zipData = try makeZipData(for: quiz)
        try zipData.write(to: outputURL, options: .atomic)
    }

    public func makeZipData(for quiz: Quiz) throws -> Data {
        let workingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let archiveURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        defer {
            try? FileManager.default.removeItem(at: workingDirectory)
            try? FileManager.default.removeItem(at: archiveURL)
        }

        try writePackageFiles(for: quiz, into: workingDirectory)
        try zipDirectory(workingDirectory, to: archiveURL)
        return try Data(contentsOf: archiveURL)
    }

    public func writePackageFiles(for quiz: Quiz, into directoryURL: URL) throws {
        let package = try exporter.makePackage(for: quiz)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        for file in package.files {
            let fileURL = directoryURL.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(file.contents.utf8).write(to: fileURL, options: .atomic)
        }
    }

    private func zipDirectory(_ directoryURL: URL, to archiveURL: URL) throws {
        guard FileManager.default.fileExists(atPath: "/usr/bin/zip") else {
            throw WriterError.missingZipExecutable
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = directoryURL
        process.arguments = ["-qr", archiveURL.path, "."]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw WriterError.zipCommandFailed(status: process.terminationStatus)
        }
    }
}
