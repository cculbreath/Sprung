//
//  FilterChip.swift
//  Sprung
//
//  Small selectable chip for category filter bars (L3 filter role) — reads
//  as a lighter, tinted-outline level distinct from `ChipNav`'s filled L2
//  nav chips (plans/ux-consistency-plan-2026-07-08.md §5, §8). Promoted
//  from Discovery/Views/Events/FilterChip.swift to Shared/UIComponents so
//  any module's filter bar can share one definition; the original
//  accent-only look is preserved when no `tint` is supplied.
//

import SwiftUI

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let tint {
                Text(label)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(isSelected ? tint : .secondary)
                    .background(
                        Capsule().fill(tint.opacity(isSelected ? 0.18 : 0.05))
                    )
                    .overlay(
                        Capsule().strokeBorder(tint.opacity(isSelected ? 0.5 : 0.25), lineWidth: 1)
                    )
            } else {
                Text(label)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .cornerRadius(6)
            }
        }
        .buttonStyle(.plain)
    }
}
