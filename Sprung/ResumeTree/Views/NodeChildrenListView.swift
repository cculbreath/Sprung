//
//  NodeChildrenListView.swift
//  Sprung
//
//
import SwiftUI
struct NodeChildrenListView: View {
    let children: [TreeNode]
    /// Depth offset to subtract when calculating indentation (for flattened container children)
    var depthOffset: Int = 0
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(children, id: \.id) { child in
                Divider()
                let isContainer = child.allowsChildAddition || child.orderedChildren.isEmpty == false
                if isContainer {
                    NodeWithChildrenView(node: child, depthOffset: depthOffset)
                } else {
                    ReorderableLeafRow(
                        node: child,
                        siblings: child.parent?.orderedChildren ?? [],
                        depthOffset: depthOffset
                    )
                    .padding(.vertical, 4)
                }
            }
        }
    }
}
