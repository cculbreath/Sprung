//
//  SparkleButton.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/31/25.
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
        }
        .buttonStyle( .automatic )
        .disabled(node.status == LeafStatus.saved)
    }
}
