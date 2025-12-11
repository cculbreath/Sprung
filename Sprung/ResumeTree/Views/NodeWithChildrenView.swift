//
//  NodeWithChildrenView.swift
//  Sprung
//
//
import SwiftData
import SwiftUI
struct NodeWithChildrenView: View {
    let node: TreeNode
    /// Depth offset to subtract when calculating indentation (for flattened container children)
    var depthOffset: Int = 0
    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM
    var body: some View {
        DraggableNodeWrapper(node: node, siblings: getSiblings()) {
            VStack(alignment: .leading) {
                // Header combines the chevron, title, add button, and status badge.
                NodeHeaderView(
                    node: node,
                    depthOffset: depthOffset,
                    addChildAction: { vm.addChild(to: node) }
                )
                // Show child nodes when expanded.
                if vm.isExpanded(node) {
                    NodeChildrenListView(children: node.orderedChildren, depthOffset: depthOffset)
                }
            }
        }
    }
    private func getSiblings() -> [TreeNode] {
        return node.parent?.orderedChildren ?? []
    }
}
