//
//  NodeLeafView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 2/27/25.
//

import SwiftData
import SwiftUI

struct NodeLeafView: View {
    @Environment(\.modelContext) private var context
    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM

    @State var node: TreeNode

    // Local UI state (hover effects)
    @State private var isHoveringEdit: Bool = false
    @State private var isHoveringSparkles: Bool = false

    // Derived editing bindings
    private var isEditing: Bool { vm.editingNodeID == node.id }

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
                        isEditing: Binding(
                            get: { isEditing },
                            set: { newVal in if !newVal { vm.cancelEditing() } }
                        ),
                        tempName: Binding(get: { vm.tempName }, set: { vm.tempName = $0 }),
                        tempValue: Binding(get: { vm.tempValue }, set: { vm.tempValue = $0 }),
                        saveChanges: { vm.saveEdits() },
                        cancelChanges: { vm.cancelEditing() },
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
                        Button(action: { vm.startEditing(node: node) }) {
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
        .onChange(of: node.value) { _, _ in vm.refreshPDF() }
        .onChange(of: node.name) { _, _ in vm.refreshPDF() }
        .padding(.vertical, 4)
        .padding(.trailing, 12) // ← new: 24-pt right margin
        .background(
            node.status == .aiToReplace
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

    // startEditing/save/cancel logic handled by ResumeDetailVM

    private func deleteNode(node: TreeNode) {
        let resume = node.resume
        TreeNode.deleteTreeNode(node: node, context: context)
        resume.debounceExport()
    }
}
