//
//  IconBarExpandToggle.swift
//  Sprung
//
//  Toggle button to expand/collapse the icon bar.
//

import SwiftUI

/// Toggle button to expand/collapse the icon bar
struct IconBarExpandToggle: View {
    let isExpanded: Bool

    @Environment(ModuleNavigationService.self) private var navigation
    @State private var isHovered: Bool = false

    var body: some View {
        Button {
            navigation.toggleIconBarExpansion()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isExpanded ? "sidebar.left" : "sidebar.right")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)

                if isExpanded {
                    Text("Collapse")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\\")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(isExpanded ? "Collapse sidebar (\\)" : "Expand sidebar (\\)")
        .accessibilityLabel(isExpanded ? "Collapse sidebar" : "Expand sidebar")
    }
}
