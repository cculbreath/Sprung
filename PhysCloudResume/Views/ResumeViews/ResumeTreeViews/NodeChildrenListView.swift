//
//  NodeChildrenListView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 2/2/25.
//

import SwiftUI

struct NodeChildrenListView: View {
    let children: [TreeNode]
    @Binding var isWide: Bool
    @Binding var refresher: Bool

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(children.enumerated()), id: \.1.id) { index, child in
                if child.includeInEditor {
                    Divider()
                    if child.hasChildren {
                        NodeWithChildrenView(
                            node: child,
                            isExpanded: false,
                            isWide: $isWide,
                            refresher: $refresher
                        )
                    } else {
                        ReorderableLeafRow(
                            node: child,
                            siblings: children,
                            currentIndex: index,
                            refresher: $refresher
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
