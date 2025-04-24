//
//  NodeChildrenListView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 2/27/25.
//

import SwiftUI

struct NodeChildrenListView: View {
    let children: [TreeNode]
    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(children.enumerated()), id: \.1.id) { index, child in
                if child.includeInEditor {
                    Divider()
                    if child.hasChildren {
                        NodeWithChildrenView(node: child)
                    } else {
                        ReorderableLeafRow(
                            node: child,
                            siblings: children,
                            currentIndex: index,
                            refresher: Binding(get: { vm.refresher }, set: { vm.refresher = $0 })
                        )
                        .padding(.vertical, 4)
                    }
                } else {
                    EmptyView()
                }
            }
        }
    }
}
