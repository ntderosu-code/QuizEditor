import Foundation
import QuizEditorCore

/// Loads the available personas (the built-in General plus any user personas) and
/// resolves an id to a concrete persona. In this foundation phase nothing consumes
/// the resolved persona's profiles yet, so selecting a persona changes no behavior.
@MainActor
final class PersonaStore: ObservableObject {
    @Published private(set) var personas: [Persona] {
        didSet { resolver = PersonaResolver(personas: personas) }
    }

    /// Built once whenever `personas` changes, rather than rebuilt on every
    /// `resolve(_:)` — which runs often (per render, per lint pass).
    private(set) var resolver: PersonaResolver

    /// `personas` is injectable for tests/previews; otherwise loaded from disk.
    init(personas: [Persona]? = nil) {
        let loaded = personas ?? Self.loadAll()
        self.personas = loaded
        self.resolver = PersonaResolver(personas: loaded)
    }

    /// The fully merged persona for an id, falling back to General.
    func resolve(_ id: String?) -> Persona { resolver.resolve(id) }

    /// The unmerged persona record for an id, if it is one we know about.
    func persona(withID id: String?) -> Persona? {
        guard let id else { return nil }
        return personas.first { $0.id == id }
    }

    /// Reloads user personas from disk (e.g. after the user drops in a new file).
    func reload() {
        personas = Self.loadAll()
    }

    // MARK: - Saving (user personas)

    /// Writes a user persona to `Application Support/QuizEditor/Personas/<id>.json`
    /// (overwriting the same id) and refreshes `personas`. Built-in personas are
    /// read-only and never written. Local only; no network.
    @discardableResult
    func save(_ persona: Persona) -> Bool {
        guard !persona.isBuiltIn, let url = Self.fileURL(for: persona.id) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(persona).write(to: url)
            reload()
            return true
        } catch {
            return false
        }
    }

    /// Removes a user persona's file and refreshes `personas`. Built-ins are ignored.
    func delete(_ persona: Persona) {
        guard !persona.isBuiltIn, let url = Self.fileURL(for: persona.id) else { return }
        try? FileManager.default.removeItem(at: url)
        reload()
    }

    /// The on-disk file for a persona id. The filename is derived from the id so
    /// editing the same persona overwrites its file rather than duplicating it.
    static func fileURL(for id: String) -> URL? {
        guard let directory = userPersonasDirectory() else { return nil }
        let safe = id.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" ? $0 : "_" }
        let name = String(safe).isEmpty ? "persona" : String(safe)
        return directory.appendingPathComponent("\(name).json")
    }

    // MARK: - Loading

    static func loadAll() -> [Persona] {
        // General is always first, followed by the built-in discipline packs. User
        // personas follow, and a user file can never shadow a built-in id.
        var byID: [String: Persona] = [Persona.generalID: .general]
        var order: [String] = [Persona.generalID]
        for pack in Persona.builtInDisciplines where byID[pack.id] == nil {
            byID[pack.id] = pack
            order.append(pack.id)
        }
        for persona in loadUserPersonas() where byID[persona.id] == nil {
            byID[persona.id] = persona
            order.append(persona.id)
        }
        return order.compactMap { byID[$0] }
    }

    /// `~/Library/Application Support/QuizEditor/Personas`. Personas stay on disk,
    /// local and private; nothing here touches the network.
    static func userPersonasDirectory() -> URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return nil }
        return support.appendingPathComponent("QuizEditor/Personas", isDirectory: true)
    }

    /// Each `*.json` file is decoded independently; an unreadable or invalid file is
    /// skipped rather than failing the whole load.
    static func loadUserPersonas() -> [Persona] {
        guard
            let directory = userPersonasDirectory(),
            let urls = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            )
        else { return [] }

        let decoder = JSONDecoder()
        return urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(Persona.self, from: data)
            }
    }
}
