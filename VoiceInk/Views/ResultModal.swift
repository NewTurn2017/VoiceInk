import SwiftUI

struct ResultModalView: View {
    let text: String
    let note: String?
    let onClose: () -> Void

    @State private var shown = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            transcript
            footer
        }
        .padding(18)
        .frame(width: 400)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.30), radius: 26, y: 12)
        .padding(24)
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown ? 1 : 0.96, anchor: .center)
        .offset(y: shown ? 0 : 12)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { shown = true }
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.18)).frame(width: 34, height: 34)
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Copied to clipboard")
                    .font(.system(size: 14, weight: .semibold))
                if let note {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var transcript: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 200)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                withAnimation(.easeOut(duration: 0.15)) { copied = true }
            } label: {
                Label(copied ? "Copied" : "Copy again", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)

            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.18)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onClose() }
    }
}

// MARK: - Controller

@MainActor
final class ResultModalController {
    private var window: NSWindow?

    func show(text: String, note: String? = nil) {
        dismiss()

        let view = ResultModalView(text: text, note: note) { [weak self] in self?.dismiss() }
        let size = NSSize(width: 448, height: 460) // generous; card hugs content and centers
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.contentView = hosting

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.midY - size.height / 2))
        }
        panel.orderFrontRegardless()
        self.window = panel
    }

    func dismiss() {
        window?.close()
        window = nil
    }
}
