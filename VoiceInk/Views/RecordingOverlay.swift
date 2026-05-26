import SwiftUI

struct RecordingOverlayView: View {
    @ObservedObject var appState: AppState
    @State private var shown = false

    var body: some View {
        capsuleContent
            .fixedSize()                       // size to content — never truncate
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.4), .white.opacity(0.08)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.9, anchor: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity)   // center in the panel
            .onAppear {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) { shown = true }
            }
    }

    @ViewBuilder
    private var capsuleContent: some View {
        switch appState.currentStatus {
        case .recording:
            HStack(spacing: 10) {
                PulsingDot()
                Waveform(level: appState.audioLevel)
                    .frame(width: 92, height: 20)
            }
        case .processing:
            HStack(spacing: 9) {
                ThinkingDots()
                Text("Thinking")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
            }
        default:
            EmptyView()
        }
    }
}

// MARK: - Pieces

/// Gentle pulsing record indicator.
private struct PulsingDot: View {
    @State private var pulse = false
    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 9, height: 9)
            .overlay(
                Circle().stroke(.red.opacity(0.5), lineWidth: 2)
                    .scaleEffect(pulse ? 2.1 : 1)
                    .opacity(pulse ? 0 : 0.8)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) { pulse = true }
            }
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
                    .fill(
                        LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 3, height: barHeight(i))
                    .animation(.easeOut(duration: 0.12), value: level)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let clamped = min(max(CGFloat(level), 0), 0.15) / 0.15            // 0...1
        let center = 1 - abs(CGFloat(index) - CGFloat(bars - 1) / 2) / CGFloat(bars)
        let base: CGFloat = 4
        return base + clamped * 16 * (0.5 + 0.5 * center)
    }
}

/// Three dots pulsing in sequence for the processing state.
private struct ThinkingDots: View {
    @State private var animating = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.primary.opacity(0.75))
                    .frame(width: 5, height: 5)
                    .scaleEffect(animating ? 1 : 0.5)
                    .opacity(animating ? 1 : 0.35)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.18),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

// MARK: - Overlay Window Controller

@MainActor
final class RecordingOverlayController {
    private var window: NSWindow?

    func show(appState: AppState) {
        guard window == nil else { return }

        let size = NSSize(width: 280, height: 56)   // generous; capsule hugs content, centered
        let hostingView = NSHostingView(rootView: RecordingOverlayView(appState: appState))
        hostingView.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
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
            panel.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.maxY - 76))
        }
        panel.orderFront(nil)
        self.window = panel
    }

    func dismiss() {
        window?.close()
        window = nil
    }
}
