import SwiftUI

extension View {
    /// iOS-style Liquid Glass on macOS 26+, frosted-material fallback below.
    @ViewBuilder
    func liquidGlass(in shape: some Shape) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.18), lineWidth: 1))
        }
    }
}
