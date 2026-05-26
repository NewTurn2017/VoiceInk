import SwiftUI
import ServiceManagement
import AVFoundation

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

            UsageSettingsTab()
                .tabItem { Label("Usage", systemImage: "dollarsign.circle") }
        }
        .frame(width: 480, height: 320)
    }
}

// MARK: - Usage

struct UsageSettingsTab: View {
    @ObservedObject private var tracker = CostTracker.shared
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Estimated cost") {
                    Text(String(format: "$%.4f", tracker.totalCostUSD))
                        .font(.system(.body, design: .monospaced)).bold()
                }
                LabeledContent("Dictations", value: "\(tracker.callCount)")
            } header: { Text("API Usage") } footer: {
                Text("Estimated from Gemini's reported token usage and listed pricing (thinking off). Actual billing may differ.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Audio input tokens", value: tracker.audioInputTokens.formatted())
                LabeledContent("Text input tokens", value: tracker.textInputTokens.formatted())
                LabeledContent("Output tokens", value: tracker.outputTokens.formatted())
            } header: { Text("Tokens") }
            Section {
                Button("Reset usage", role: .destructive) { confirmReset = true }
                    .confirmationDialog("Reset the usage counter?", isPresented: $confirmReset) {
                        Button("Reset", role: .destructive) { tracker.reset() }
                        Button("Cancel", role: .cancel) {}
                    }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @EnvironmentObject var updaterManager: UpdaterManager
    @EnvironmentObject var appState: AppState
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in setLaunchAtLogin(newValue) }
            } header: { Text("Startup") }

            Section {
                LabeledContent("Accessibility") {
                    Label(appState.accessibilityGranted ? "Granted" : "Not granted",
                          systemImage: appState.accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(appState.accessibilityGranted ? .green : .orange)
                        .labelStyle(.titleAndIcon)
                }
                LabeledContent("Microphone") {
                    Label(appState.microphoneGranted ? "Granted" : "Not granted",
                          systemImage: appState.microphoneGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(appState.microphoneGranted ? .green : .orange)
                        .labelStyle(.titleAndIcon)
                }
                if !appState.accessibilityGranted {
                    Button("Open Accessibility Settings…") { AccessibilityHelper.openAccessibilitySettings() }
                }
                if !appState.microphoneGranted {
                    Button("Request Microphone Access") { appState.requestMicrophone() }
                    Button("Open Microphone Settings…") { appState.openMicrophoneSettings() }
                }
                Button("Restart VoiceInk") { appState.relaunch() }
                Text("Accessibility lets VoiceInk type at the cursor; Microphone lets it record. Status updates automatically; after changing a permission you may need to Restart VoiceInk.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Permissions") }

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
