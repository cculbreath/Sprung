//
//  StatusTag.swift
//  Sprung
//
//  Passive status capsule — communicates state (Discovered, Planned,
//  Complete, ...) without any button chrome. Per the affordance grammar
//  (plans/ux-consistency-plan-2026-07-08.md §4, §8), a passive status must
//  never look tappable: no border, no hover, no `Button` wrapper. The
//  active counterpart is `TintedPillButtonStyle`.
//

import SwiftUI

/// A passive, non-interactive status capsule. Not a button — just a label.
struct StatusTag: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
    }
}
