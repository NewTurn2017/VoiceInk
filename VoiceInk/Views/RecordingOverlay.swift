import SwiftUI

struct RecordingOverlayView: View {
    @ObservedObject var appState: AppState

    // Map raw audio energy to a visual scale (1.0 to 1.6)
    private var energyScale: CGFloat {
        guard appState.isRecording else { return 1.0 }
        // Clamp energy to 0...0.15 range and map to 1.0...1.6
        let clamped = min(max(appState.audioLevel, 0), 0.15)
        return 1.0 + CGFloat(clamped / 0.15) * 0.6
    }

    private var energyOpacity: Double {
        guard appState.isRecording else { return 0.2 }
        let clamped = min(max(appState.audioLevel, 0), 0.15)
        return 0.15 + Double(clamped / 0.15) * 0.35
    }

    var body: some View {
        HStack(spacing: 12) {
            // Audio energy halo
            ZStack {
                Circle()
                    .fill(.red.opacity(energyOpacity))
                    .frame(width: 36, height: 36)
                    .scaleEffect(energyScale)
                    .animation(.easeOut(duration: 0.1), value: appState.audioLevel)

                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(statusLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(engineLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Stop button
            Button {
                appState.toggleRecording()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 280)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    private var statusLabel: String {
        switch appState.currentStatus {
        case .connecting: return "Loading model..."
        case .recording: return "Listening..."
        case .error(let msg): return "Error: \(msg ?? "Unknown")"
        default: return "Ready"
        }
    }

    private var engineLabel: String {
        if appState.engineType == .local {
            return "Local — \(appState.modelSize.displayName)"
        } else {
            return "Cloud — ElevenLabs"
        }
    }
}

// MARK: - Overlay Window Controller

final class RecordingOverlayController {
    private var window: NSWindow?

    func show(appState: AppState) {
        guard window == nil else { return }

        let view = RecordingOverlayView(appState: appState)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 280, height: 60)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 60),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Position: top-center of main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 140
            let y = screenFrame.maxY - 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFront(nil)
        self.window = panel
    }

    func dismiss() {
        window?.close()
        window = nil
    }
}
