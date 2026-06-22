import SwiftUI
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

/// Lists the available personas, lets the user set the app-wide default and this
/// quiz's persona, and explains how to add their own. Selecting a persona changes
/// no question content and is fully reversible.
struct PersonaManagementSheet: View {
    let personas: [Persona]
    @Binding var quizPersonaID: String?
    @AppStorage("personaID") private var appDefaultPersonaID = Persona.generalID
    @Environment(\.dismiss) private var dismiss

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

                    Divider()

                    Text("Available personas")
                        .font(.subheadline.weight(.semibold))
                    VStack(spacing: 10) {
                        ForEach(personas) { persona in
                            PersonaRow(persona: persona, isActive: persona.id == effectiveID)
                        }
                    }

                    Text("Custom personas can be added as JSON files in Application Support/QuizEditor/Personas. A guided editor for creating and forking personas is on the roadmap.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 520, minHeight: 540)
    }
}

/// One persona in the management list. The active persona is marked with a filled
/// check, a border, and an accessibility note, so its state is never color-only.
struct PersonaRow: View {
    let persona: Persona
    let isActive: Bool

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
            Spacer(minLength: 0)
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
}
