//
//  SparkleButton.swift
//  Sprung
//
//
import SwiftUI

/// Selection state for AI revision
enum AISelectionState {
    case notSelected       // Gray sparkle
    case directlySelected  // Solid accent sparkle (purple/blue)
    case inherited         // Dimmed/outlined sparkle (via parent selection)
    case groupInherited    // Orange sparkle (via parent's attribute picker)
}

struct SparkleButton: View {
    @Binding var node: TreeNode
    @Binding var isHovering: Bool
    var toggleNodeStatus: () -> Void
    var onShowAttributePicker: (() -> Void)?

    /// Compute the selection state based on node's direct status and inheritance
    private var selectionState: AISelectionState {
        if node.isGroupInheritedSelection {
            return .groupInherited
        } else if node.status == .aiToReplace {
            return .directlySelected
        } else if node.isInheritedAISelection {
            return .inherited
        } else {
            return .notSelected
        }
    }

    /// Foreground color based on selection state
    private var foregroundColor: Color {
        switch selectionState {
        case .directlySelected:
            return .accentColor
        case .groupInherited:
            return .orange  // Different color for group-inherited
        case .inherited:
            return .accentColor.opacity(0.5)
        case .notSelected:
            return isHovering ? .accentColor.opacity(0.6) : .gray
        }
    }

    /// Icon name based on selection state
    private var iconName: String {
        switch selectionState {
        case .directlySelected, .groupInherited:
            return "sparkles"
        case .inherited:
            return "sparkles"
        case .notSelected:
            return "sparkles"
        }
    }

    /// Help text for the button
    private var helpText: String {
        switch selectionState {
        case .directlySelected:
            if node.isCollectionNode {
                return "Click to modify attribute selection"
            }
            return "Click to remove from AI revision"
        case .groupInherited:
            return "Selected via parent - click parent to modify"
        case .inherited:
            return "Included via parent selection (click to exclude)"
        case .notSelected:
            if node.isCollectionNode {
                return "Click to select attributes for AI revision"
            }
            return "Click to include in AI revision"
        }
    }

    /// Handle button click - either show picker or toggle directly
    private func handleClick() {
        if node.isCollectionNode {
            // Collection node - show attribute picker
            onShowAttributePicker?()
        } else if selectionState == .groupInherited {
            // Group-inherited nodes shouldn't toggle individually
            // Could show a message or do nothing
            return
        } else {
            // Regular toggle
            toggleNodeStatus()
        }
    }

    var body: some View {
        Button(action: handleClick) {
            ZStack {
                // For inherited state, show outline effect
                if selectionState == .inherited {
                    Image(systemName: iconName)
                        .foregroundColor(.accentColor.opacity(0.3))
                        .font(.system(size: 14))
                }

                // For group-inherited, show subtle glow
                if selectionState == .groupInherited {
                    Image(systemName: iconName)
                        .foregroundColor(.orange.opacity(0.3))
                        .font(.system(size: 16))
                        .blur(radius: 2)
                }

                Image(systemName: iconName)
                    .foregroundColor(foregroundColor)
                    .font(.system(size: 14))
                    .opacity(selectionState == .inherited ? 0.7 : 1.0)
            }
            .padding(5)
            .background(
                isHovering && selectionState == .notSelected ?
                    Color.gray.opacity(0.1) :
                    Color.clear
            )
            .clipShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
        .help(helpText)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
