import Foundation
import QuizEditorCore

/// Loads the available personas (the built-in General plus any user personas) and
/// resolves an id to a concrete persona. In this foundation phase nothing consumes
/// the resolved persona's profiles yet, so selecting a persona changes no behavior.
@MainActor
final class PersonaStore: ObservableObject {
    @Published private(set) var personas: [Persona]

    /// `personas` is injectable for tests/previews; otherwise loaded from disk.
    init(personas: [Persona]? = nil) {
        self.personas = personas ?? Self.loadAll()
    }

    var resolver: PersonaResolver { PersonaResolver(personas: personas) }

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

    // MARK: - Loading

    static func loadAll() -> [Persona] {
        // General is always first and always present. User personas follow, and a
        // user file can never shadow a built-in id.
        var byID: [String: Persona] = [Persona.generalID: .general]
        var order: [String] = [Persona.generalID]
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
