//
//  SparkleButton.swift
//  Sprung
//
//
import SwiftUI

/// Selection state for AI revision
enum AISelectionState {
    case notSelected      // Gray sparkle
    case directlySelected // Solid accent sparkle
    case inherited        // Dimmed/outlined sparkle (via parent selection)
}

struct SparkleButton: View {
    @Binding var node: TreeNode
    @Binding var isHovering: Bool
    var toggleNodeStatus: () -> Void

    /// Compute the selection state based on node's direct status and inheritance
    private var selectionState: AISelectionState {
        if node.status == .aiToReplace {
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
        case .inherited:
            return .accentColor.opacity(0.5)
        case .notSelected:
            return isHovering ? .accentColor.opacity(0.6) : .gray
        }
    }

    /// Icon name based on selection state
    private var iconName: String {
        switch selectionState {
        case .directlySelected:
            return "sparkles"
        case .inherited:
            return "sparkles"  // Could use different icon if desired
        case .notSelected:
            return "sparkles"
        }
    }

    /// Help text for the button
    private var helpText: String {
        switch selectionState {
        case .directlySelected:
            return "Click to remove from AI revision"
        case .inherited:
            return "Included via parent selection (click to exclude)"
        case .notSelected:
            return "Click to include in AI revision"
        }
    }

    var body: some View {
        Button(action: toggleNodeStatus) {
            ZStack {
                // For inherited state, show outline effect
                if selectionState == .inherited {
                    Image(systemName: iconName)
                        .foregroundColor(.accentColor.opacity(0.3))
                        .font(.system(size: 14))
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
