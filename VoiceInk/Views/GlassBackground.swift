import SwiftUI

/// Shared "은갈색" (silver-brown) metallic palette for the floating glass UI.
enum MetalPalette {
    static let tint   = Color(red: 0.64, green: 0.58, blue: 0.50)  // warm silver-brown body
    static let silver = Color(red: 0.88, green: 0.85, blue: 0.79)  // light edge highlight
    static let bronze = Color(red: 0.45, green: 0.39, blue: 0.31)  // dark edge / shadow
}

extension View {
    /// Metallic silver-brown liquid glass on macOS 26+, frosted-material fallback below.
    func liquidGlass(in shape: some Shape) -> some View {
        modifier(MetallicGlass(shape: AnyShape(shape)))
    }
}

private struct MetallicGlass: ViewModifier {
    let shape: AnyShape

    /// Brushed-metal edge: bright silver top-left fading to dark bronze bottom-right.
    private var sheen: LinearGradient {
        LinearGradient(
            colors: [MetalPalette.silver.opacity(0.9), MetalPalette.bronze.opacity(0.55)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.tint(MetalPalette.tint.opacity(0.42)), in: shape)
                .overlay(shape.stroke(sheen, lineWidth: 1))
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(MetalPalette.tint.opacity(0.16), in: shape)
                .overlay(shape.stroke(sheen, lineWidth: 1))
        }
    }
}
