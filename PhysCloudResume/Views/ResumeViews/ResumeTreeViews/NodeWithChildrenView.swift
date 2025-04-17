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
    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM

    var body: some View {
        VStack(alignment: .leading) {
            // Header combines the chevron, title, add button, and status badge.
                NodeHeaderView(
                    node: node,
                    isExpanded: $isExpanded,
                    isWide: Binding(get: { vm.isWide }, set: { vm.isWide = $0 }),
                    refresher: Binding(get: { vm.refresher }, set: { vm.refresher = $0 }),
                    addChildAction: { vm.addChild(to: node) }
                )

            // Show child nodes when expanded.
            if isExpanded,
               let children = node.children?.sorted(by: { $0.myIndex < $1.myIndex })
            {
                NodeChildrenListView(children: children)
            }
        }
    }
}
