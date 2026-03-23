import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack {
            Text(statusText)

            if let progress = appState.modelDownloadProgress {
                ProgressView(value: progress)
                    .padding(.horizontal)
                Text("Downloading model: \(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button(appState.isRecording ? "Stop Recording" : "Start Recording") {
                appState.toggleRecording()
            }
            .keyboardShortcut(.space, modifiers: .option)

            Divider()

            // Engine selection
            Menu("Engine: \(appState.engineType.displayName)") {
                ForEach(STTEngineType.allCases, id: \.self) { type in
                    Button {
                        appState.switchEngine(to: type)
                    } label: {
                        HStack {
                            Text(type.displayName)
                            if type == appState.engineType {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            // Model selection (only for local engine)
            if appState.engineType == .local {
                Menu("Model: \(appState.modelSize.displayName)") {
                    ForEach(STTModelSize.allCases, id: \.self) { size in
                        Button {
                            appState.switchModel(to: size)
                        } label: {
                            HStack {
                                Text(size.displayName)
                                if size == appState.modelSize {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }

            Divider()

            Text("⌥ Space to toggle")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private var statusText: String {
        switch appState.currentStatus {
        case .idle:
            return "VoiceInk — Idle"
        case .connecting:
            return "VoiceInk — Loading..."
        case .recording:
            return "VoiceInk — Recording"
        case .error(let message):
            return "VoiceInk — Error: \(message ?? "Unknown")"
        }
    }
}
