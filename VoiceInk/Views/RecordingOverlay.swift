import SwiftUI

struct RecordingOverlayView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            switch appState.currentStatus {
            case .recording:
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Waveform(level: appState.audioLevel)
                    .frame(width: 90, height: 18)
            case .processing:
                Text("Thinking…")
                    .font(.system(size: 12, weight: .medium))
                ProgressBarShimmer()
                    .frame(width: 70, height: 4)
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .overlay(
            Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1)
        )
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
    }
}

/// Audio-reactive bars.
private struct Waveform: View {
    var level: Float
    private let bars = 7

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<bars, id: \.self) { i in
                Capsule()
                    .fill(.primary.opacity(0.8))
                    .frame(width: 3, height: barHeight(i))
                    .animation(.easeOut(duration: 0.12), value: level)
            }
        }
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let clamped = min(max(CGFloat(level), 0), 0.15) / 0.15      // 0...1
        // Center bars taller; edges shorter, plus a per-bar phase wobble.
        let center = 1 - abs(CGFloat(index) - CGFloat(bars - 1) / 2) / CGFloat(bars)
        let base: CGFloat = 4
        return base + clamped * 14 * (0.5 + 0.5 * center)
    }
}

/// Indeterminate shimmer bar for the processing state.
private struct ProgressBarShimmer: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            Capsule().fill(.primary.opacity(0.15))
                .overlay(
                    Capsule()
                        .fill(.primary.opacity(0.6))
                        .frame(width: geo.size.width * 0.4)
                        .offset(x: phase * geo.size.width)
                )
                .clipShape(Capsule())
        }
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                phase = 1.2
            }
        }
    }
}

// MARK: - Overlay Window Controller

@MainActor
final class RecordingOverlayController {
    private var window: NSWindow?

    func show(appState: AppState) {
        guard window == nil else { return }

        let hostingView = NSHostingView(rootView: RecordingOverlayView(appState: appState))
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 44)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 44),
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

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - 100, y: f.maxY - 70))
        }
        panel.orderFront(nil)
        self.window = panel
    }

    func dismiss() {
        window?.close()
        window = nil
    }
}
