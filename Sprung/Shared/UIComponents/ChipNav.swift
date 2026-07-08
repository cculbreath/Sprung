//
//  ChipNav.swift
//  Sprung
//
//  L2 navigation chip — a peer-level "switch between sections" control with
//  selected-fill and an optional count badge. Extracted from References'
//  private `TabPill` (ReferencesModuleView.swift) so any module's tab row
//  can share the same nav-chip look. Deliberately reads as a *different
//  level* than `FilterChip` (L3, tinted-outline) per the affordance grammar
//  (plans/ux-consistency-plan-2026-07-08.md §5, §8).
//

import SwiftUI

/// Selected-fill navigation chip for switching between peer sections (e.g.
/// References' Knowledge/Writing/Skills/Titles/Dossier tabs). Accepts an
/// identity tint so each destination keeps its own color when selected.
struct ChipNav: View {
    let label: String
    var count: Int? = nil
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                if let count, count > 0 {
                    Text("(\(count))")
                        .font(.caption)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? tint : Color.clear)
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
