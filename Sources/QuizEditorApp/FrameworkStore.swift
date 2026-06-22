import Foundation
import QuizEditorCore

/// Loads competency frameworks (the built-in starter plus any user frameworks) and
/// persists user frameworks locally. Mirrors `PersonaStore`: built-ins are
/// read-only and always present; user files live in Application Support; nothing
/// here touches the network.
@MainActor
final class FrameworkStore: ObservableObject {
    @Published private(set) var frameworks: [Framework]

    init(frameworks: [Framework]? = nil) {
        self.frameworks = frameworks ?? Self.loadAll()
    }

    func framework(withID id: String?) -> Framework? {
        guard let id else { return nil }
        return frameworks.first { $0.id == id }
    }

    func reload() {
        frameworks = Self.loadAll()
    }

    @discardableResult
    func save(_ framework: Framework) -> Bool {
        guard !framework.isBuiltIn, let url = Self.fileURL(for: framework.id) else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(framework).write(to: url)
            reload()
            return true
        } catch {
            return false
        }
    }

    func delete(_ framework: Framework) {
        guard !framework.isBuiltIn, let url = Self.fileURL(for: framework.id) else { return }
        try? FileManager.default.removeItem(at: url)
        reload()
    }

    // MARK: - Loading

    static func loadAll() -> [Framework] {
        // Built-ins first and never shadowed by a user file.
        var byID: [String: Framework] = [Framework.bloom.id: .bloom]
        var order: [String] = [Framework.bloom.id]
        for framework in loadUserFrameworks() where byID[framework.id] == nil {
            byID[framework.id] = framework
            order.append(framework.id)
        }
        return order.compactMap { byID[$0] }
    }

    static func directory() -> URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return nil }
        return support.appendingPathComponent("QuizEditor/Frameworks", isDirectory: true)
    }

    static func loadUserFrameworks() -> [Framework] {
        guard
            let directory = directory(),
            let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }

        let decoder = JSONDecoder()
        return urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(Framework.self, from: data)
            }
    }

    static func fileURL(for id: String) -> URL? {
        guard let directory = directory() else { return nil }
        let safe = id.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" ? $0 : "_" }
        let name = String(safe).isEmpty ? "framework" : String(safe)
        return directory.appendingPathComponent("\(name).json")
    }
}
