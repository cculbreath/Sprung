//
//  NodeHeaderView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 2/2/25.
//
import SwiftData
import SwiftUI

struct NodeHeaderView: View {
    let node: TreeNode
    @Binding var isExpanded: Bool
    @Binding var isWide: Bool
    @Binding var refresher: Bool
    let addChildAction: () -> Void

    @State private var isHoveringAdd: Bool = false

    var body: some View {
        HStack {
            ToggleChevronView(isExpanded: $isExpanded, toggleAction: {
                withAnimation {
                    isExpanded.toggle()
                    if !isExpanded {
                        refresher.toggle()
                    }
                }
            })

            if node.parent == nil {
                HeaderTextRow()
            } else {
                AlignedTextRow(
                    leadingText: "\(node.label)",
                    trailingText: nil,
                    nodeStatus: node.status
                )
            }

            Spacer()

            if isExpanded && node.parent != nil {
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
                .onHover { hovering in
                    isHoveringAdd = hovering
                }
            }

            StatusBadgeView(node: node, isExpanded: isExpanded)
        }
        .padding(.horizontal, 10)
        .padding(.leading, CGFloat(node.depth * 20))
        .padding(.vertical, 5)
        .background(Color.clear)
        .cornerRadius(5)
    }
}
