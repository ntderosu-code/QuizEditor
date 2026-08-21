import SwiftUI
import QuizEditorCore

/// The panes of the Settings window (⌘,). The selection is persisted so the
/// window reopens where the user left it, and so a caller like the AI panel's
/// "Configure…" can steer `openSettings()` — which has no tab parameter — by
/// writing the tab it wants before opening the window.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case ai

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .ai: "AI"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .ai: "sparkles"
        }
    }
}

/// The app's Settings window. Holds preferences that belong to the app rather
/// than to a document: the review profile new quizzes start with, and the AI
/// provider credentials. Per-quiz choices (this quiz's review profile, its
/// competency links) stay in the document's own UI.
struct AppSettingsView: View {
    @AppStorage("settingsTab") private var selectedTab = SettingsTab.general

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(SettingsTab.allCases) { tab in
                Group {
                    switch tab {
                    case .general: GeneralSettingsView()
                    case .ai: AISettingsView()
                    }
                }
                .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                .tag(tab)
            }
        }
        .frame(width: 520)
    }
}

/// General preferences: which review profile new quizzes start with.
struct GeneralSettingsView: View {
    @EnvironmentObject private var personaStore: PersonaStore
    @AppStorage("personaID") private var appDefaultPersonaID = Persona.generalID

    var body: some View {
        Form {
            Section {
                Picker("Review profile", selection: $appDefaultPersonaID) {
                    ForEach(personaStore.personas) { persona in
                        Text(persona.displayName).tag(persona.id)
                    }
                }
            } header: {
                Text("New quizzes")
            } footer: {
                Text("The review profile a new quiz starts with. Any quiz can override it from the Quiz menu, and changing this never alters questions you have already written.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

/// AI preferences: the provider and, for the API-backed provider, its
/// credentials. These are the same `@AppStorage` keys the AI panel reads, so a
/// change here takes effect immediately in every open document.
struct AISettingsView: View {
    @AppStorage("aiProvider") private var provider = AIProvider.openAICompatible
    @AppStorage("aiAPIKey") private var apiKey = ""
    @AppStorage("aiEndpoint") private var endpoint = "https://api.openai.com/v1/chat/completions"
    @AppStorage("aiModel") private var model = "gpt-4o-mini"

    var body: some View {
        Form {
            Picker("Provider", selection: $provider) {
                ForEach(AIProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }

            switch provider {
            case .openAICompatible:
                Section("API credentials") {
                    SecureField("API key", text: $apiKey, prompt: Text("sk-…"))
                    TextField("Endpoint", text: $endpoint, prompt: Text("https://api.openai.com/v1/chat/completions"))
                    TextField("Model", text: $model, prompt: Text("gpt-4o-mini"))
                }
                Section {
                    Text("Requests go only to the endpoint you enter here. The app makes no other network connections.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .copyPaste:
                Section {
                    Text("Copies a model-ready prompt to your clipboard. Paste the response back into the AI Suggestions panel. No API key needed, and nothing leaves your Mac on its own.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .foundationModels:
                Section {
                    Text("Uses Apple Foundation Models on-device when Apple Intelligence is available on this Mac. No API key needed, and nothing leaves your Mac.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
    }
}
