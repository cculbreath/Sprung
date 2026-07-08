//
//  TintedPillButtonStyle.swift
//  Sprung
//
//  Tinted, bordered capsule button style — the "action pill" primitive for
//  compact row actions (Enrich / Merge / Ingest / New / Approve, and their
//  peers across modules). Promoted from the private `KCToolbarButtonStyle`
//  in KnowledgeCardsBrowserTab.swift so every module shares one action-pill
//  look instead of re-deriving it (see plans/ux-consistency-plan-2026-07-08.md
//  §4, §8).
//

import SwiftUI

/// Tinted, bordered capsule button style for compact row actions. Gives a
/// clear button affordance and legible size instead of bare colored caption
/// text — the opposite role of `StatusTag`, which must never wear this
/// chrome.
struct TintedPillButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        TintedPillButtonBody(tint: tint, configuration: configuration)
    }
}

private struct TintedPillButtonBody: View {
    let tint: Color
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(tint.opacity(configuration.isPressed ? 0.24 : (isHovering ? 0.18 : 0.12)))
            )
            .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 1))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { isHovering = $0 }
            .animation(.easeInOut(duration: 0.12), value: isHovering)
    }
}

extension ButtonStyle where Self == TintedPillButtonStyle {
    /// `.buttonStyle(.tintedPill(tint: .purple))`
    static func tintedPill(tint: Color) -> TintedPillButtonStyle {
        TintedPillButtonStyle(tint: tint)
    }
}
