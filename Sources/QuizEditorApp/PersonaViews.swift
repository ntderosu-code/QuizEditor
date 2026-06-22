import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuizEditorCore

/// Humanizes a persona's `family` string for display.
func personaFamilyName(_ family: String) -> String {
    switch family {
    case "general": "General"
    case "health": "Health professions"
    case "science": "Natural sciences"
    case "stem": "STEM"
    case "social-science": "Social sciences"
    case "humanities": "Humanities"
    default: family.capitalized
    }
}

/// The `.qepersona` document type, matched by filename extension so no Info.plist
/// declaration is needed for the import/export panels.
private var personaFileType: UTType { UTType(filenameExtension: "qepersona") ?? .json }

/// Lists the available personas, lets the user set the app-wide default and this
/// quiz's persona, and create/fork/edit/import/export their own. Selecting a
/// persona changes no question content and is fully reversible.
struct PersonaManagementSheet: View {
    @ObservedObject var store: PersonaStore
    @Binding var quizPersonaID: String?
    @AppStorage("personaID") private var appDefaultPersonaID = Persona.generalID
    @Environment(\.dismiss) private var dismiss

    @State private var editingPersona: Persona?
    @State private var notice: String?

    private var personas: [Persona] { store.personas }

    private var defaultDisplayName: String {
        personas.first { $0.id == appDefaultPersonaID }?.displayName ?? "General"
    }

    /// The persona actually in effect for this quiz: its own override, else the app default.
    private var effectiveID: String { quizPersonaID ?? appDefaultPersonaID }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Personas", systemImage: "person.crop.rectangle.stack")
                    .font(.title2.bold())
                Spacer()
                Button {
                    importPersona()
                } label: {
                    Label("Import…", systemImage: "square.and.arrow.down")
                }
                Button {
                    editingPersona = newPersona()
                } label: {
                    Label("New", systemImage: "plus")
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("A persona bakes a discipline's quiz-writing best practices into the editor. Choosing one is reversible and never changes the questions you've written.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    LabeledField("Default for new quizzes") {
                        Picker("Default for new quizzes", selection: $appDefaultPersonaID) {
                            ForEach(personas) { persona in
                                Text(persona.displayName).tag(persona.id)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }

                    LabeledField("This quiz") {
                        Picker("This quiz's persona", selection: $quizPersonaID) {
                            Text("Use default (\(defaultDisplayName))").tag(String?.none)
                            ForEach(personas) { persona in
                                Text(persona.displayName).tag(Optional(persona.id))
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }

                    if let notice {
                        Label(notice, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()

                    Text("Available personas")
                        .font(.subheadline.weight(.semibold))
                    VStack(spacing: 10) {
                        ForEach(personas) { persona in
                            PersonaRow(
                                persona: persona,
                                isActive: persona.id == effectiveID,
                                onEdit: persona.isBuiltIn ? nil : { editingPersona = persona },
                                onDuplicate: { editingPersona = persona.fork() },
                                onExport: { export(persona) },
                                onDelete: persona.isBuiltIn ? nil : { delete(persona) }
                            )
                        }
                    }

                    Text("Built-in personas are read-only — duplicate one to make your own. User personas live locally in Application Support/QuizEditor/Personas and never touch the network.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 520, minHeight: 560)
        .sheet(item: $editingPersona) { persona in
            PersonaEditorSheet(persona: persona) { saved in
                store.save(saved)
                notice = "Saved “\(saved.displayName).”"
            }
        }
    }

    // MARK: - Actions

    private func newPersona() -> Persona {
        Persona(id: "user.\(UUID().uuidString.lowercased())", displayName: "New Persona", isBuiltIn: false)
    }

    private func delete(_ persona: Persona) {
        store.delete(persona)
        if appDefaultPersonaID == persona.id { appDefaultPersonaID = Persona.generalID }
        if quizPersonaID == persona.id { quizPersonaID = nil }
        notice = "Deleted “\(persona.displayName).”"
    }

    private func export(_ persona: Persona) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [personaFileType]
        let safeName = persona.displayName.filter { $0.isLetter || $0.isNumber || $0 == " " }.trimmingCharacters(in: .whitespaces)
        panel.nameFieldStringValue = (safeName.isEmpty ? "persona" : safeName) + ".qepersona"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(persona) {
            try? data.write(to: url)
            notice = "Exported “\(persona.displayName).”"
        }
    }

    private func importPersona() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [personaFileType, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }

        do {
            let result = try Persona.importResult(fromJSON: data)
            var persona = result.persona
            // A user import can never shadow a built-in id; re-home it if it collides.
            if persona.isBuiltIn || personas.contains(where: { $0.isBuiltIn && $0.id == persona.id }) {
                persona.isBuiltIn = false
                persona.id = "user.\(UUID().uuidString.lowercased())"
            }
            store.save(persona)
            let warning = result.warnings.isEmpty ? "" : " " + result.warnings.joined(separator: " ")
            notice = "Imported “\(persona.displayName).”" + warning
        } catch {
            notice = "Couldn't import that file — it isn't a valid persona."
        }
    }
}

/// One persona in the management list. The active persona is marked with a filled
/// check, a border, and an accessibility note, so its state is never color-only.
/// Trailing actions are offered in an ellipsis menu.
struct PersonaRow: View {
    let persona: Persona
    let isActive: Bool
    var onEdit: (() -> Void)?
    var onDuplicate: (() -> Void)?
    var onExport: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(persona.displayName)
                        .font(.headline)
                    Text(personaFamilyName(persona.family))
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(.capsule)
                    if persona.isBuiltIn {
                        Text("Built-in")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if !persona.summary.isEmpty {
                    Text(persona.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            actionsMenu
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.18))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(persona.displayName), \(personaFamilyName(persona.family))\(isActive ? ", active for this quiz" : "")\(persona.summary.isEmpty ? "" : ". \(persona.summary)")")
    }

    @ViewBuilder
    private var actionsMenu: some View {
        Menu {
            if let onEdit {
                Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
            }
            if let onDuplicate {
                Button { onDuplicate() } label: { Label(persona.isBuiltIn ? "Duplicate & Edit" : "Duplicate", systemImage: "doc.on.doc") }
            }
            if let onExport {
                Button { onExport() } label: { Label("Export…", systemImage: "square.and.arrow.up") }
            }
            if let onDelete {
                Divider()
                Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Actions for \(persona.displayName)")
    }
}
