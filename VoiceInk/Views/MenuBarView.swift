import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack {
            Text(statusText)

            Divider()

            Button(appState.isRecording ? "Stop Recording" : "Start Recording") {
                appState.toggleRecording()
            }
            .keyboardShortcut(.space, modifiers: .option)

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
            return "VoiceInk — Connecting..."
        case .recording:
            return "VoiceInk — Recording"
        case .error(let message):
            return "VoiceInk — Error: \(message ?? "Unknown")"
        }
    }
}
