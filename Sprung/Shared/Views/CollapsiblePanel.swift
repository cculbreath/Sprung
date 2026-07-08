//
//  CollapsiblePanel.swift
//  Sprung
//
//  Panel chrome for drawer behavior: chevron toggle, collapsed drag handle,
//  and a vertical resize handle. Uses Adobe-style double chevrons for expand/collapse.
//

import SwiftUI

/// Edge from which the panel extends
enum PanelEdge {
    case leading
    case trailing
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

// MARK: - Resize Handles

/// Vertical resize handle for adjusting panel width (drag left/right)
struct VerticalResizeHandle: View {
    @Binding var width: Double
    let minWidth: CGFloat
    let maxWidth: CGFloat
    var inverted: Bool = false  // If true, dragging left increases width (for trailing panels)
    /// The pane's actual laid-out width when the layout may compress it below
    /// the stored `width`. Drags start from here, so the divider responds
    /// immediately — otherwise a stored width far above the displayed one
    /// leaves hundreds of points of dead travel before anything moves.
    var displayedWidth: Double? = nil

    @State private var isHovered = false
    @State private var isDragging = false
    @State private var dragStartWidth: Double = 0

    /// Real interactive width the gesture owns. A thin separator line is drawn
    /// centered inside it. This must be a genuine layout width (not a negative
    /// `contentShape` overhang) so the drag region never overlaps an adjacent
    /// AppKit view such as the PDF preview's `PDFView`, which would otherwise
    /// swallow the `mouseDown` and prevent the drag from ever starting.
    private let hitWidth: CGFloat = 9

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor.opacity(0.3) : (isHovered ? Color.primary.opacity(0.1) : Color(.separatorColor)))
            .frame(width: isDragging ? 3 : 1)
            .frame(width: hitWidth)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
                // Cursor is pushed exactly once per hover-in and popped on
                // hover-out (or at drag end, if the pointer left mid-drag).
                guard !isDragging else { return }
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            // The drag MUST be tracked in a stable coordinate space. The handle
            // moves as a consequence of its own drag; in the default .local
            // space each layout pass shifts the space the translation is
            // measured in, so the reading collapses back toward zero and the
            // width snaps between two states (visible as violent jitter, or as
            // a divider that refuses to move under slow drags).
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragStartWidth = displayedWidth ?? width
                        }
                        let delta = inverted ? -value.translation.width : value.translation.width
                        let newWidth = dragStartWidth + delta
                        width = min(max(newWidth, Double(minWidth)), Double(maxWidth))
                    }
                    .onEnded { _ in
                        isDragging = false
                        if !isHovered {
                            NSCursor.pop()
                        }
                    }
            )
    }
}
