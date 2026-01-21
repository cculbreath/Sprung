//
//  IconBarItem.swift
//  Sprung
//
//  Individual item in the icon bar.
//

import SwiftUI

/// Individual item in the icon bar
struct IconBarItem: View {
    let module: AppModule
    let isSelected: Bool
    let isExpanded: Bool

    @Environment(ModuleNavigationService.self) private var navigation
    @State private var isHovered: Bool = false

    var body: some View {
        Button {
            navigation.selectModule(module)
        } label: {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: module.icon)
                    .font(.system(size: 18))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)

                // Label (when expanded)
                if isExpanded {
                    Text(module.label)
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                        .lineLimit(1)

                    Spacer()

                    // Shortcut hint
                    Text("\(module.shortcutNumber)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("\(module.label) (\(module.shortcutNumber))\n\(module.description)")
        .accessibilityLabel(module.label)
        .accessibilityHint(module.description)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.15)
        } else if isHovered {
            return Color.primary.opacity(0.05)
        } else {
            return Color.clear
        }
    }
}
