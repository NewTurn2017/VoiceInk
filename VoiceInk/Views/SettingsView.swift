import SwiftUI
import ServiceManagement
import Qwen3ASR

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            EngineSettingsTab()
                .tabItem {
                    Label("Engine", systemImage: "cpu")
                }

            APIKeysSettingsTab()
                .tabItem {
                    Label("API Keys", systemImage: "key")
                }
        }
        .frame(width: 480, height: 320)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("holdToTalk") private var holdToTalk = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            } header: {
                Text("Startup")
            }

            Section {
                HStack {
                    Text(holdToTalk ? "Hold to Record" : "Toggle Recording")
                    Spacer()
                    Text("⌥ Space")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Toggle("Hold-to-Talk Mode", isOn: $holdToTalk)

                Text(holdToTalk
                    ? "Hold ⌥ Space to record, release to stop and transcribe."
                    : "Press ⌥ Space to start/stop recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Hotkey")
            }

            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to set launch at login: \(error)")
        }
    }
}

// MARK: - Engine Tab

struct EngineSettingsTab: View {
    @AppStorage("sttEngineType") private var engineTypeRaw = STTEngineType.local.rawValue
    @AppStorage("sttModelSize") private var modelSizeRaw = STTModelSize.small.rawValue
    @State private var downloadProgress: Double?
    @State private var downloadStatus: String?
    @State private var isDownloading = false
    @State private var modelCacheCheck = UUID() // triggers view refresh

    private var engineType: STTEngineType {
        STTEngineType(rawValue: engineTypeRaw) ?? .local
    }

    private var modelSize: STTModelSize {
        STTModelSize(rawValue: modelSizeRaw) ?? .small
    }

    private func isModelCached(_ size: STTModelSize) -> Bool {
        let cacheBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/qwen3-speech/models")
        let orgName = size.rawValue.components(separatedBy: "/").first ?? ""
        let orgPath = cacheBase.appendingPathComponent(orgName)
        return FileManager.default.fileExists(atPath: orgPath.path)
    }

    var body: some View {
        Form {
            Section {
                Picker("STT Engine", selection: $engineTypeRaw) {
                    ForEach(STTEngineType.allCases, id: \.rawValue) { type in
                        Text(type.displayName).tag(type.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                if engineType == .local {
                    Text("Runs on-device using Apple Silicon. No internet required.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Uses ElevenLabs cloud API. Requires internet and API key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Engine")
            }

            if engineType == .local {
                Section {
                    Picker("Model", selection: $modelSizeRaw) {
                        ForEach(STTModelSize.allCases, id: \.rawValue) { size in
                            Text(size.displayName).tag(size.rawValue)
                        }
                    }

                    HStack {
                        Text("Status")
                        Spacer()
                        let _ = modelCacheCheck // observe refresh trigger
                        if isModelCached(modelSize) {
                            Label("Ready", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        } else if isDownloading {
                            Label(downloadStatus ?? "Downloading...", systemImage: "arrow.down.circle")
                                .foregroundStyle(.blue)
                                .font(.caption)
                        } else {
                            Label("Not downloaded", systemImage: "arrow.down.circle")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                    }

                    if isDownloading, let progress = downloadProgress {
                        ProgressView(value: progress)
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    if !isModelCached(modelSize) && !isDownloading {
                        Button("Download Model Now") {
                            downloadModel()
                        }
                    }
                } header: {
                    Text("Local Model")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func downloadModel() {
        isDownloading = true
        downloadProgress = 0
        downloadStatus = "Preparing..."

        Task {
            do {
                let _ = try await Qwen3ASRModel.fromPretrained(
                    modelId: modelSize.rawValue
                ) { progress, status in
                    DispatchQueue.main.async {
                        self.downloadProgress = progress
                        self.downloadStatus = status
                    }
                }
                await MainActor.run {
                    isDownloading = false
                    downloadProgress = nil
                    downloadStatus = nil
                    modelCacheCheck = UUID()
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    downloadProgress = nil
                    downloadStatus = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - API Keys Tab

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
                        TextField("ElevenLabs API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("ElevenLabs API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button {
                        showKey.toggle()
                    } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                HStack {
                    Button("Save") {
                        saveAPIKey()
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if hasKey {
                        Button("Delete", role: .destructive) {
                            deleteAPIKey()
                        }
                    }

                    Spacer()

                    if let message = statusMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(message.contains("Error") ? .red : .green)
                    }
                }
            } header: {
                Text("ElevenLabs")
            } footer: {
                Text("Required for Cloud engine. Get your key at elevenlabs.io")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadAPIKey()
        }
    }

    private func loadAPIKey() {
        hasKey = keychainManager.hasAPIKey(for: .elevenLabs)
        if hasKey, let key = keychainManager.getAPIKey(for: .elevenLabs) {
            apiKey = key
        }
    }

    private func saveAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try keychainManager.saveAPIKey(trimmed, for: .elevenLabs)
            hasKey = true
            statusMessage = "Saved"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                statusMessage = nil
            }
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func deleteAPIKey() {
        do {
            try keychainManager.deleteAPIKey(for: .elevenLabs)
            apiKey = ""
            hasKey = false
            statusMessage = "Deleted"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                statusMessage = nil
            }
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }
}
