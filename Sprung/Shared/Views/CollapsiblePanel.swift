//
//  CollapsiblePanel.swift
//  Sprung
//
//  Unified collapsible panel component for consistent drawer behavior.
//  Uses Adobe-style double chevrons for expand/collapse.
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
        .frame(width: currentWidth + 1)
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

/// Chevron toggle button for panel expansion using SF Symbols
struct PanelChevronToggle: View {
    let edge: PanelEdge
    @Binding var isExpanded: Bool

    @State private var isHovered = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: chevronSymbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(isExpanded ? "Collapse" : "Expand")
    }

    private var chevronSymbol: String {
        switch edge {
        case .leading:
            return isExpanded ? "chevron.left.2" : "chevron.compact.right"
        case .trailing:
            return isExpanded ? "chevron.right.2" : "chevron.compact.left"
        }
    }
}

/// Skinny drag handle for collapsed sidebar - just a vertical chevron strip
struct CollapsedPanelHandle: View {
    let edge: PanelEdge
    @Binding var isExpanded: Bool

    @State private var isHovered = false

    private let handleWidth: CGFloat = 24

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded = true
            }
        } label: {
            VStack(spacing: 0) {
                Spacer()
                Image(systemName: edge == .leading ? "chevron.compact.right" : "chevron.compact.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isHovered ? .primary : .tertiary)
                Spacer()
            }
            .frame(width: handleWidth)
            .background(isHovered ? Color.primary.opacity(0.03) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("Show sidebar")
        .overlay(alignment: edge == .leading ? .trailing : .leading) {
            Rectangle()
                .fill(Color(.separatorColor))
                .frame(width: 1)
        }
    }
}

/// Legacy toggle button (keeping for backwards compatibility)
struct PanelToggleButton: View {
    let edge: PanelEdge
    @Binding var isExpanded: Bool
    var collapsedIcon: String = "sidebar.right"
    var expandedIcon: String = "sidebar.left"

    var body: some View {
        PanelChevronToggle(edge: edge, isExpanded: $isExpanded)
    }
}

// MARK: - Resize Handles

/// Vertical resize handle for adjusting panel width (drag left/right)
struct VerticalResizeHandle: View {
    @Binding var width: Double
    let minWidth: CGFloat
    let maxWidth: CGFloat
    var inverted: Bool = false  // If true, dragging left increases width (for trailing panels)

    @State private var isHovered = false
    @State private var isDragging = false
    @State private var dragStartWidth: Double = 0

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor.opacity(0.3) : (isHovered ? Color.primary.opacity(0.1) : Color(.separatorColor)))
            .frame(width: isDragging ? 3 : 1)
            .contentShape(Rectangle().inset(by: -3))
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else if !isDragging {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragStartWidth = width
                            NSCursor.resizeLeftRight.push()
                        }
                        let delta = inverted ? -value.translation.width : value.translation.width
                        let newWidth = dragStartWidth + delta
                        width = min(max(newWidth, Double(minWidth)), Double(maxWidth))
                    }
                    .onEnded { _ in
                        isDragging = false
                        NSCursor.pop()
                    }
            )
    }
}

/// Horizontal resize handle for adjusting panel height (drag up/down)
struct HorizontalResizeHandle: View {
    @Binding var height: Double
    let minHeight: CGFloat
    let maxHeight: CGFloat
    var inverted: Bool = false  // If true, dragging up increases height

    @State private var isHovered = false
    @State private var isDragging = false
    @State private var dragStartHeight: Double = 0

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor.opacity(0.3) : (isHovered ? Color.primary.opacity(0.1) : Color(.separatorColor)))
            .frame(height: isDragging ? 3 : 1)
            .contentShape(Rectangle().inset(by: -3))
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else if !isDragging {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragStartHeight = height
                            NSCursor.resizeUpDown.push()
                        }
                        let delta = inverted ? -value.translation.height : value.translation.height
                        let newHeight = dragStartHeight + delta
                        height = min(max(newHeight, Double(minHeight)), Double(maxHeight))
                    }
                    .onEnded { _ in
                        isDragging = false
                        NSCursor.pop()
                    }
            )
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
