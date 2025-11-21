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
                Divider()
                if child.orderedViewChildren.isEmpty {
                    ReorderableLeafRow(
                        node: child,
                        siblings: child.parent?.orderedChildren ?? []
                    )
                    .padding(.vertical, 4)
                } else {
                    NodeWithChildrenView(node: child)
                }
            }
        }
    }
}
