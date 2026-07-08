//
//  ViewModeToggle.swift
//  Sprung
//
//  Compact icon-pair toggle for an L3-right view-mode switch (List/Calendar,
//  Board/Summary, ...). Generic over any Hashable mode value so each module
//  supplies its own modes/symbols/labels; renders a segmented icon control
//  rather than a native `.pickerStyle(.segmented)` picker, matching the
//  app's pill/segment chrome (plans/ux-consistency-plan-2026-07-08.md §5, §8).
//

import SwiftUI

/// One selectable mode in a `ViewModeToggle` — a display-mode value plus its
/// SF Symbol and accessible label.
struct ViewModeOption<Value: Hashable>: Identifiable {
    let value: Value
    let symbol: String
    let label: String

    var id: Value { value }

    init(_ value: Value, symbol: String, label: String) {
        self.value = value
        self.symbol = symbol
        self.label = label
    }
}

/// Compact icon-pair (or icon-N-tuple) segmented toggle. Generic over any
/// `Hashable` mode value — pass an ordered set of `ViewModeOption`s and a
/// selection binding.
struct ViewModeToggle<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [ViewModeOption<Value>]
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                Button {
                    selection = option.value
                } label: {
                    Image(systemName: option.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == option.value ? .white : .secondary)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(selection == option.value ? tint : Color.clear)
                )
                .help(option.label)
                .accessibilityLabel(option.label)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}
