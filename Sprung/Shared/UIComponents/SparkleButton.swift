//
//  SparkleButton.swift
//  Sprung
//
//
import SwiftUI

/// Selection state for AI revision - color indicates mode
enum AISelectionState {
    case notSelected        // Gray
    case directlySelected   // Orange (solo mode)
    case bundleIncluded     // Purple (bundle mode)
    case iterateIncluded    // Cyan (iterate mode)
}

struct SparkleButton: View {
    @Binding var node: TreeNode
    @Binding var isHovering: Bool
    var toggleNodeStatus: () -> Void

    /// Compute the selection state based on node's status
    private var selectionState: AISelectionState {
        if node.isIncludedInBundleReview {
            return .bundleIncluded
        } else if node.isIncludedInIterateReview {
            return .iterateIncluded
        } else if node.status == .aiToReplace {
            return .directlySelected
        } else {
            return .notSelected
        }
    }

    /// Foreground color based on selection state
    private var foregroundColor: Color {
        switch selectionState {
        case .directlySelected:
            return .orange  // Solo mode = orange
        case .bundleIncluded:
            return .purple  // Bundle mode = purple
        case .iterateIncluded:
            return .cyan  // Iterate mode = cyan
        case .notSelected:
            return isHovering ? .gray : .gray.opacity(0.5)
        }
    }

    /// Help text for the button
    private var helpText: String {
        switch selectionState {
        case .directlySelected:
            return "Click to remove from AI revision"
        case .bundleIncluded:
            return "Included in bundle review (all combined)"
        case .iterateIncluded:
            return "Included in iterate review (per entry)"
        case .notSelected:
            return "Click to include in AI revision"
        }
    }

    /// Handle button click
    private func handleClick() {
        if selectionState == .bundleIncluded || selectionState == .iterateIncluded {
            // Container children can't be toggled individually
            return
        }
        toggleNodeStatus()
    }

    var body: some View {
        Button(action: handleClick) {
            Image(systemName: "sparkles")
                .foregroundColor(foregroundColor)
                .font(.system(size: 14))
                .padding(5)
        }
        .buttonStyle(PlainButtonStyle())
        .help(helpText)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
