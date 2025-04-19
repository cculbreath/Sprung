//
//  NodeWithChildrenView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 2/2/25.
//

import SwiftData
import SwiftUI

struct NodeWithChildrenView: View {
    let node: TreeNode
    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM

    var body: some View {
        VStack(alignment: .leading) {
            // Header combines the chevron, title, add button, and status badge.
            NodeHeaderView(
                node: node,
                addChildAction: { vm.addChild(to: node) }
            )

            // Show child nodes when expanded.
            if vm.isExpanded(node),
               let children = node.children?.sorted(by: { $0.myIndex < $1.myIndex })
            {
                NodeChildrenListView(children: children)
            }
        }
    }
}
