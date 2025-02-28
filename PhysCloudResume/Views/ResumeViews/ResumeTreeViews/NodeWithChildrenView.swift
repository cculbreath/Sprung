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
    @State var isExpanded: Bool
    @Binding var isWide: Bool
    @Binding var refresher: Bool

    var body: some View {
        VStack(alignment: .leading) {
            // Header combines the chevron, title, add button, and status badge.
            NodeHeaderView(
                node: node,
                isExpanded: $isExpanded,
                isWide: $isWide,
                refresher: $refresher,
                addChildAction: { addChild(to: node) }
            )

            // Show child nodes when expanded.
            if isExpanded,
               let children = node.children?.sorted(by: { $0.myIndex < $1.myIndex })
            {
                NodeChildrenListView(children: children, isWide: $isWide, refresher: $refresher)
            }
        }
    }

    private func addChild(to parent: TreeNode) {
        let newNode = TreeNode(
            name: "",
            value: "New Child",
            inEditor: true,
            status: .saved,
            resume: parent.resume
        )
        newNode.isEditing = true
        parent.addChild(newNode)
        DispatchQueue.main.async {
            refresher.toggle()
        }
    }
}
