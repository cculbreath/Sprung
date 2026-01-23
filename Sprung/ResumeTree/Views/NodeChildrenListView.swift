//
//  NodeChildrenListView.swift
//  Sprung
//
//
import SwiftUI
struct NodeChildrenListView: View {
    let children: [TreeNode]
    /// Depth offset to subtract when calculating indentation (for flattened container children)
    var depthOffset: Int = 0
    /// Display children as horizontal chips instead of vertical list
    var displayAsChips: Bool = false
    /// Parent node (required for chip mode to enable add/browse)
    var parentNode: TreeNode?
    /// Source key for browsing (e.g., "skillBank")
    var sourceKey: String?
    /// Matched skill IDs for highlighting (from job context)
    var matchedSkillIds: Set<UUID> = []

    var body: some View {
        if displayAsChips, let parent = parentNode {
            ChipChildrenView(
                children: children,
                parent: parent,
                matchedSkillIds: matchedSkillIds,
                sourceKey: sourceKey
            )
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(children, id: \.id) { child in
                    Divider()
                    let isContainer = child.allowsChildAddition || child.orderedChildren.isEmpty == false
                    if isContainer {
                        NodeWithChildrenView(node: child, depthOffset: depthOffset)
                    } else {
                        ReorderableLeafRow(
                            node: child,
                            siblings: child.parent?.orderedChildren ?? [],
                            depthOffset: depthOffset
                        )
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
}
