//
//  StatusBadgeView.swift
//  Sprung
//
//  Created by Christopher Culbreath on 2/27/25.
//
import SwiftUI
struct StatusBadgeView: View {
    let node: TreeNode
    let isExpanded: Bool
    var body: some View {
        if node.aiStatusChildren > 0 && (!isExpanded || node.parent == nil || node.parent?.parent == nil) {
            Text("\(node.aiStatusChildren)")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.2))
                .foregroundColor(.blue)
                .cornerRadius(10)
        } else {
            EmptyView()
        }
    }
}
