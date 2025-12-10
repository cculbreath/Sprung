//
//  NodeChildrenListView.swift
//  Sprung
//
//
import SwiftUI
struct NodeChildrenListView: View {
    let children: [TreeNode]
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(children, id: \.id) { child in
                Divider()
                let isContainer = child.allowsChildAddition || child.orderedViewChildren.isEmpty == false
                if isContainer {
                    NodeWithChildrenView(node: child)
                } else {
                    ReorderableLeafRow(
                        node: child,
                        siblings: child.parent?.orderedChildren ?? []
                    )
                    .padding(.vertical, 4)
                }
            }
        }
    }
}
