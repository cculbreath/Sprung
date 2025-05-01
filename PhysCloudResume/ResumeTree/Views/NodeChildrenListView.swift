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
            ForEach(children, id: \.id) { child in
                if child.includeInEditor {
                    Divider()
                    if child.hasChildren {
                        NodeWithChildrenView(node: child)
                    } else {
                        ReorderableLeafRow(
                            node: child,
                            siblings: children,
                            currentIndex: child.myIndex
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
