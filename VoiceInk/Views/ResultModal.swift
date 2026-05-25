import SwiftUI

struct ResultModalView: View {
    let text: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard")
                Text("Copied to clipboard")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(.secondary)

            ScrollView {
                Text(text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)

            HStack {
                Spacer()
                Button("Copy again") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Button("Close", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 380)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 18, y: 6)
    }
}

@MainActor
final class ResultModalController {
    private var window: NSWindow?

    func show(text: String) {
        dismiss()
        let view = ResultModalView(text: text) { [weak self] in self?.dismiss() }
        let hosting = NSHostingView(rootView: view)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 280),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.contentView = hosting
        panel.collectionBehavior = [.canJoinAllSpaces]

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - 190, y: f.midY - 140))
        }
        panel.orderFrontRegardless()
        self.window = panel
    }

    func dismiss() {
        window?.close()
        window = nil
    }
}
