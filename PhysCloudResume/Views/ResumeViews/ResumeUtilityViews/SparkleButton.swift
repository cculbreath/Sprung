//
//  SparkleButton.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/29/25.
//

import SwiftUI

struct SparkleButton: View {
    @Binding var node: TreeNode
    @Binding var isHovering: Bool
    var toggleNodeStatus: () -> Void

    var body: some View {
        Button(action: toggleNodeStatus) {
            Image(systemName: "sparkles")
                .foregroundColor(
                    node.status == LeafStatus.saved ? .gray : .accentColor
                )
                .font(.system(size: 14))
                .padding(2)
                .background(
                    isHovering
                        ? (node.status == LeafStatus.saved
                            ? Color.gray.opacity(0.3)
                            : Color.accentColor.opacity(0.3))
                        : Color.clear
                )
                .cornerRadius(5)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
