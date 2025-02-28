//
//  NodeLeafView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 2/2/25.
//

import SwiftData
import SwiftUI

struct NodeLeafView: View {
    @Environment(\.modelContext) private var context
    @State var node: TreeNode
    @Binding var refresher: Bool

    // State variables for editing and hover actions.
    @State private var isEditing: Bool = false
    @State private var tempValue: String = ""
    @State private var tempName: String = ""
    @State private var isHoveringEdit: Bool = false
    @State private var isHoveringSparkles: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if node.value.isEmpty {
                Spacer().frame(width: 50)
                Text(node.name)
                    .foregroundColor(.gray)
            } else {
                if node.status != LeafStatus.disabled {
                    SparkleButton(
                        node: $node,
                        isHovering: $isHoveringSparkles,
                        toggleNodeStatus: toggleNodeStatus
                    )
                }
                if node.status == LeafStatus.disabled {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.gray)
                        .font(.system(size: 12))
                }
                if isEditing {
                    EditingControls(
                        isEditing: $isEditing,
                        tempName: $tempName,
                        tempValue: $tempValue,
                        saveChanges: saveChanges,
                        cancelChanges: cancelChanges,
                        deleteNode: { deleteNode(node: node) }
                    )
                } else {
                    if !node.name.isEmpty && !node.value.isEmpty {
                        StackedTextRow(
                            title: node.name,
                            description: node.value,
                            nodeStatus: node.status
                        )
                        Spacer()
                    } else {
                        AlignedTextRow(
                            leadingText: node.name,
                            trailingText: node.value,
                            nodeStatus: node.status
                        )
                        Spacer()
                    }

                    if node.status != LeafStatus.disabled {
                        Button(action: startEditing) {
                            Image(systemName: "square.and.pencil")
                                .foregroundColor(
                                    isHoveringEdit
                                        ? (node.status == LeafStatus.aiToReplace ? .primary : .accentColor)
                                        : (node.status == LeafStatus.aiToReplace ? .accentColor : .secondary)
                                )
                                .font(.system(size: 14))
                                .padding(5)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .onHover { hovering in
                            isHoveringEdit = hovering
                        }
                    }
                }
            }
        }
        .onChange(of: node.value) { _ in
            node.resume.debounceExport()
        }
        .onChange(of: node.name) { _ in
            node.resume.debounceExport()
        }
        .padding(.vertical, 4)
        .background(
            node.status == LeafStatus.aiToReplace
                ? Color.accentColor.opacity(0.3)
                : Color.clear
        )
        .cornerRadius(5)
    }

    // MARK: - Actions

    private func toggleNodeStatus() {
        if node.status == LeafStatus.saved {
            node.status = .aiToReplace
        } else if node.status == LeafStatus.aiToReplace {
            node.status = .saved
        }
    }

    private func startEditing() {
        tempValue = node.value
        tempName = node.name
        isEditing = true
    }

    private func saveChanges() {
        node.value = tempValue
        node.name = tempName
        node.status = .saved
        isEditing = false
        try? context.save()
    }

    private func cancelChanges() {
        isEditing = false
    }

    private func deleteNode(node: TreeNode) {
        let resume = node.resume
        TreeNode.deleteTreeNode(node: node, context: context)
        resume.debounceExport()
        refresher.toggle()
    }
}
