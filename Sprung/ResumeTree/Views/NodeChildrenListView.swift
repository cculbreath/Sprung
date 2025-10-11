//
//  NodeChildrenListView.swift
//  Sprung
//
//  Created by Christopher Culbreath on 2/27/25.
//

import SwiftUI

struct NodeChildrenListView: View {
    let children: [TreeNode]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(children, id: \.id) { child in
                if child.includeInEditor {
                    Divider()
                    if child.hasChildren {
                        NodeWithChildrenView(node: child)
                    } else {
                        ReorderableLeafRow(
                            node: child,
                            siblings: children
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
