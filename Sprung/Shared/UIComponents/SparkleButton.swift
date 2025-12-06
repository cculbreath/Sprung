//
//  SparkleButton.swift
//  Sprung
//
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
                    node.status == LeafStatus.saved ?
                        (isHovering ? .accentColor.opacity(0.6) : .gray) :
                        .accentColor
                )
                .font(.system(size: 14))
                .padding(5)
                .background(
                    isHovering && node.status != LeafStatus.aiToReplace ?
                        Color.gray.opacity(0.1) :
                        Color.clear
                )
                .clipShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
