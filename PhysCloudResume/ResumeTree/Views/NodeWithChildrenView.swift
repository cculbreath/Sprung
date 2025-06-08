//
//  NodeWithChildrenView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 2/27/25.
//

import SwiftData
import SwiftUI

struct NodeWithChildrenView: View {
    let node: TreeNode
    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM

    var body: some View {
        DraggableNodeWrapper(node: node, siblings: getSiblings()) {
            VStack(alignment: .leading) {
                // Header combines the chevron, title, add button, and status badge.
                NodeHeaderView(
                    node: node,
                    addChildAction: { vm.addChild(to: node) }
                )

                // Show child nodes when expanded.
                if vm.isExpanded(node) {
                    // one stable array identity -> zero diff-engine churn
                    NodeChildrenListView(children: node.orderedChildren)
                }
            }
        }
    }
    
    private func getSiblings() -> [TreeNode] {
        return node.parent?.orderedChildren ?? []
    }
}
