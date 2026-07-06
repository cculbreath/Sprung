//
//  FilterChip.swift
//  Sprung
//
//  Small selectable chip used for category filter bars (EventsView).
//

import SwiftUI

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}
