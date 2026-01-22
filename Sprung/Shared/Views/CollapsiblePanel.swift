//
//  CollapsiblePanel.swift
//  Sprung
//
//  Unified collapsible panel component for consistent drawer behavior.
//  Used by IconBar, job app sidebar, and inspector panels.
//

import SwiftUI

/// Edge from which the panel extends
enum PanelEdge {
    case leading
    case trailing
}

/// Collapsible panel with animated width transitions
struct CollapsiblePanel<Content: View>: View {
    let edge: PanelEdge
    let collapsedWidth: CGFloat
    let expandedWidth: CGFloat
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    /// Optional toggle button configuration
    var showToggle: Bool = true
    var toggleIcon: String? = nil

    private var currentWidth: CGFloat {
        isExpanded ? expandedWidth : collapsedWidth
    }

    var body: some View {
        HStack(spacing: 0) {
            if edge == .trailing {
                separator
            }

            content()
                .frame(width: currentWidth)
                .clipped()

            if edge == .leading {
                separator
            }
        }
        .frame(width: currentWidth + 1) // +1 for separator
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color(.separatorColor))
            .frame(width: 1)
    }
}

/// Panel that can fully hide (width goes to 0)
struct HideablePanel<Content: View>: View {
    let edge: PanelEdge
    let width: CGFloat
    @Binding var isVisible: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isVisible {
            HStack(spacing: 0) {
                if edge == .trailing {
                    Divider()
                }

                content()
                    .frame(width: width)

                if edge == .leading {
                    Divider()
                }
            }
            .transition(.move(edge: edge == .leading ? .leading : .trailing).combined(with: .opacity))
        }
    }
}

/// Toggle button for panel expansion (matches IconBar style)
struct PanelToggleButton: View {
    let edge: PanelEdge
    @Binding var isExpanded: Bool
    var collapsedIcon: String = "sidebar.right"
    var expandedIcon: String = "sidebar.left"

    @State private var isHovered = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: currentIcon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(isExpanded ? "Collapse" : "Expand")
    }

    private var currentIcon: String {
        if edge == .leading {
            return isExpanded ? expandedIcon : collapsedIcon
        } else {
            return isExpanded ? collapsedIcon : expandedIcon
        }
    }
}

// MARK: - Convenience Modifiers

extension View {
    /// Wraps content in a collapsible leading panel
    func leadingPanel(
        isExpanded: Binding<Bool>,
        collapsedWidth: CGFloat,
        expandedWidth: CGFloat
    ) -> some View {
        CollapsiblePanel(
            edge: .leading,
            collapsedWidth: collapsedWidth,
            expandedWidth: expandedWidth,
            isExpanded: isExpanded
        ) {
            self
        }
    }

    /// Wraps content in a hideable trailing panel
    func trailingPanel(
        isVisible: Binding<Bool>,
        width: CGFloat
    ) -> some View {
        HideablePanel(
            edge: .trailing,
            width: width,
            isVisible: isVisible
        ) {
            self
        }
    }
}
