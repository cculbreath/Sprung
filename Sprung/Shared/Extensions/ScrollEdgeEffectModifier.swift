//
//  ScrollEdgeEffectModifier.swift
//  Sprung
//
//  ViewModifier for macOS 26 Liquid Glass scroll edge effect.
//  Applies soft scroll edge styling to prevent content from
//  scrolling behind toolbars without proper blur.
//

import SwiftUI

/// Applies scroll edge effect styling for macOS 26+ Liquid Glass design.
/// On older macOS versions, this modifier has no effect.
struct ScrollEdgeEffectModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

extension View {
    /// Applies the macOS 26 scroll edge effect for proper toolbar/content interaction.
    func scrollEdgeEffect() -> some View {
        modifier(ScrollEdgeEffectModifier())
    }
}
