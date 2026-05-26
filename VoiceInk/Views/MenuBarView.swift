import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack {
            Label(statusText, systemImage: statusIcon)

            if !appState.accessibilityGranted {
                Divider()
                Text("⚠️ Accessibility required to type at the cursor")
                    .font(.caption).foregroundStyle(.orange)
                Button("Open Accessibility Settings…") { AccessibilityHelper.openAccessibilitySettings() }
                Text("After enabling, restart VoiceInk.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Divider()

            Button(appState.isRecording ? "Stop" : "Clean Up Dictation") {
                appState.toggle(mode: .cleanup)
            }
            .keyboardShortcut(.space, modifiers: .option)

            Button("Translate to English") {
                appState.toggle(mode: .translateToEnglish)
            }
            .keyboardShortcut(.space, modifiers: [.option, .shift])

            Text("⌥Space clean up · ⇧⌥Space translate")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            if !appState.historyManager.entries.isEmpty {
                Text("Recent")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(appState.historyManager.entries.prefix(5)) { entry in
                    Button {
                        appState.historyManager.copyToClipboard(entry)
                    } label: {
                        HStack {
                            Text(entry.preview).lineLimit(1)
                            Spacer()
                            Text(entry.timeAgo).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                Button("Clear History") { appState.historyManager.clear() }
                    .foregroundStyle(.secondary)

                Divider()
            }

            Text("Model: \(appState.geminiModel.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button("Settings...") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            .keyboardShortcut(",")

            Divider()

            Button("Restart VoiceInk") { appState.relaunch() }

            Button("Quit VoiceInk") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private var statusText: String {
        switch appState.currentStatus {
        case .idle: return "Idle"
        case .recording: return "Recording"
        case .processing: return "Thinking…"
        case .error(let msg): return "Error: \(msg ?? "Unknown")"
        }
    }

    private var statusIcon: String {
        switch appState.currentStatus {
        case .idle: return "mic.slash"
        case .recording: return "mic.fill"
        case .processing: return "ellipsis.circle"
        case .error: return "exclamationmark.triangle"
        }
    }
}
