import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack {
            // Status
            Label(statusText, systemImage: statusIcon)

            if let progress = appState.modelDownloadProgress {
                ProgressView(value: progress)
                    .padding(.horizontal)
                Text("Downloading model: \(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Record toggle
            Button(appState.isRecording ? "Stop Recording" : "Start Recording") {
                appState.toggleRecording()
            }
            .keyboardShortcut(.space, modifiers: .option)

            Divider()

            // Engine info
            Text("Engine: \(appState.engineType.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if appState.engineType == .local {
                Text("Model: \(appState.modelSize.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Settings
            SettingsLink {
                Text("Settings...")
            }
            .keyboardShortcut(",")

            Divider()

            Button("Quit VoiceInk") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private var statusText: String {
        switch appState.currentStatus {
        case .idle: return "Idle"
        case .connecting: return "Loading..."
        case .recording: return "Recording"
        case .error(let msg): return "Error: \(msg ?? "Unknown")"
        }
    }

    private var statusIcon: String {
        switch appState.currentStatus {
        case .idle: return "mic.slash"
        case .connecting: return "ellipsis.circle"
        case .recording: return "mic.fill"
        case .error: return "exclamationmark.triangle"
        }
    }
}
