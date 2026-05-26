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

    func body(content: Content) -> some View {
        // `glassEffect` only exists in the macOS 26 SDK (Xcode 26 / Swift 6.2+). The
        // `#if compiler` guard keeps this file compiling on older toolchains (e.g. an
        // older CI Xcode), where it falls back to a frosted material. When built with
        // Xcode 26, the `#available` check picks real Liquid Glass at runtime.
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            return AnyView(
                content
                    .glassEffect(.regular.tint(MetalPalette.tint.opacity(0.42)), in: shape)
                    .overlay(shape.stroke(sheen, lineWidth: 1))
            )
        }
        #endif
        return AnyView(
            content
                .background(.ultraThinMaterial, in: shape)
                .background(MetalPalette.tint.opacity(0.16), in: shape)
                .overlay(shape.stroke(sheen, lineWidth: 1))
        )
    }
}
