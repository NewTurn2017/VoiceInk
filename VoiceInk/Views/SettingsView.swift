import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var updaterManager: UpdaterManager

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .environmentObject(updaterManager)
                .tabItem { Label("General", systemImage: "gear") }

            ModelSettingsTab()
                .tabItem { Label("Model", systemImage: "cpu") }

            APIKeysSettingsTab()
                .tabItem { Label("API Key", systemImage: "key") }
        }
        .frame(width: 480, height: 320)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @EnvironmentObject var updaterManager: UpdaterManager
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in setLaunchAtLogin(newValue) }
            } header: { Text("Startup") }

            Section {
                LabeledContent("Clean up dictation", value: "⌥ Space")
                LabeledContent("Translate to English", value: "⇧ ⌥ Space")
                Text("Press once to start recording, press again to stop and process.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Hotkeys") }

            Section {
                LabeledContent("Version",
                    value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")
                Toggle("Automatically check for updates",
                       isOn: Binding(get: { updaterManager.automaticallyChecksForUpdates },
                                     set: { updaterManager.automaticallyChecksForUpdates = $0 }))
                Button("Check for Updates...") { updaterManager.checkForUpdates() }
                    .disabled(!updaterManager.canCheckForUpdates)
            } header: { Text("About") }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { print("Failed to set launch at login: \(error)") }
    }
}

// MARK: - Model

struct ModelSettingsTab: View {
    @AppStorage("geminiModel") private var geminiModelRaw = GeminiModel.flash.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Gemini Model", selection: $geminiModelRaw) {
                    ForEach(GeminiModel.allCases, id: \.rawValue) { model in
                        Text(model.displayName).tag(model.rawValue)
                    }
                }
                Text("Audio is transcribed, cleaned up, and (optionally) translated in a single Gemini call. Korean is the primary language.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Transcription Model") }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - API Key

struct APIKeysSettingsTab: View {
    @State private var apiKey: String = ""
    @State private var hasKey: Bool = false
    @State private var showKey: Bool = false
    @State private var statusMessage: String?

    private let keychainManager = KeychainManager.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    if showKey {
                        TextField("Gemini API Key", text: $apiKey).textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Gemini API Key", text: $apiKey).textFieldStyle(.roundedBorder)
                    }
                    Button { showKey.toggle() } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                    }.buttonStyle(.borderless)
                }
                HStack {
                    Button("Save") { saveAPIKey() }
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if hasKey {
                        Button("Delete", role: .destructive) { deleteAPIKey() }
                    }
                    Spacer()
                    if let message = statusMessage {
                        Text(message).font(.caption)
                            .foregroundStyle(message.contains("Error") ? .red : .green)
                    }
                }
            } header: { Text("Google AI (Gemini)") } footer: {
                Text("Get a free key at aistudio.google.com → API keys.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { loadAPIKey() }
    }

    private func loadAPIKey() {
        hasKey = keychainManager.hasAPIKey(for: .gemini)
        if hasKey, let key = keychainManager.getAPIKey(for: .gemini) { apiKey = key }
    }

    private func saveAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try keychainManager.saveAPIKey(trimmed, for: .gemini)
            hasKey = true
            statusMessage = "Saved"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { statusMessage = nil }
        } catch { statusMessage = "Error: \(error.localizedDescription)" }
    }

    private func deleteAPIKey() {
        do {
            try keychainManager.deleteAPIKey(for: .gemini)
            apiKey = ""; hasKey = false; statusMessage = "Deleted"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { statusMessage = nil }
        } catch { statusMessage = "Error: \(error.localizedDescription)" }
    }
}
