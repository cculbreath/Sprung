//
//  StatusBadgeView.swift
//  Sprung
//
//
import SwiftUI
struct StatusBadgeView: View {
    let node: TreeNode
    let isExpanded: Bool

    /// Use smart operations count for meaningful badge display
    private var badgeText: String {
        // Use descriptive label if available (e.g., "3 categories")
        if let label = node.reviewOperationsLabel {
            return label
        }
        // Fallback to simple count
        return "\(node.reviewOperationsCount)"
    }

    /// Whether to show the badge
    private var shouldShowBadge: Bool {
        // Must have operations to show
        guard node.reviewOperationsCount > 0 else { return false }
        // Show when collapsed, or at root/top-level nodes
        return !isExpanded || node.parent == nil || node.parent?.parent == nil
    }

    var body: some View {
        if shouldShowBadge {
            Text(badgeText)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.2))
                .foregroundColor(.blue)
                .cornerRadius(10)
        } else {
            EmptyView()
        }
    }
}
