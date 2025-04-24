//
//  NodeHeaderView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 2/27/25.
//

import SwiftUI

/// Header row for a parent node.  No state lives here; it queries and mutates
/// expansion state through `ResumeDetailVM`.
struct NodeHeaderView: View {
    let node: TreeNode
    let addChildAction: () -> Void

    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM

    // Bindings that forward to the view‑model properties.
    private var isExpanded: Binding<Bool> {
        Binding(
            get: { vm.isExpanded(node) },
            set: { _ in vm.toggleExpansion(for: node) }
        )
    }

    // Accessors kept for future controls if needed.

    @State private var isHoveringAdd = false

    var body: some View {
        HStack {
            ToggleChevronView(isExpanded: isExpanded, toggleAction: {
                vm.toggleExpansion(for: node)
            })

            if node.parent == nil {
                HeaderTextRow()
            } else {
                AlignedTextRow(
                    leadingText: node.label,
                    trailingText: nil,
                    nodeStatus: node.status
                )
            }

            Spacer()

            if vm.isExpanded(node) && node.parent != nil {
                Button(action: addChildAction) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(isHoveringAdd ? .green : .secondary)
                            .font(.system(size: 14))
                        Text("Add child")
                            .font(.caption)
                            .foregroundColor(isHoveringAdd ? .green : .secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(isHoveringAdd ? Color.white.opacity(0.4) : Color.clear)
                    .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { hovering in isHoveringAdd = hovering }
            }

            StatusBadgeView(node: node, isExpanded: vm.isExpanded(node))
        }
        .padding(.horizontal, 10)
        .padding(.leading, CGFloat(node.depth * 20))
        .padding(.vertical, 5)
    }
}
