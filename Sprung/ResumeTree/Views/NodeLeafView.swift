//
//  NodeLeafView.swift
//  Sprung
//
//
import SwiftData
import SwiftUI

struct NodeLeafView: View {
    @Environment(\.modelContext) private var context
    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM
    @State var node: TreeNode

    // Derived editing bindings
    private var isEditing: Bool { vm.editingNodeID == node.id }

    /// Get the icon mode for this leaf node
    private var iconMode: AIIconMode {
        AIIconModeResolver.detectSingleMode(for: node)
    }

    var body: some View {
        let isSectionLabelEntry = node.parent?.name == "sectionLabels"
        HStack(spacing: 5) {
            if node.value.isEmpty && !isSectionLabelEntry && !isEditing {
                Spacer().frame(width: 50)
                Button(action: { vm.startEditing(node: node) }) {
                    Text(node.name.isEmpty ? "Empty" : node.name.titleCased)
                        .foregroundColor(.gray)
                        .italic()
                }
                .buttonStyle(.plain)
            } else {
                // AI status menu for all non-disabled nodes
                if node.status != LeafStatus.disabled {
                    Menu {
                        nodeAIMenu
                    } label: {
                        AIIconImage(mode: iconMode)
                            .padding(4)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .help(iconMode.helpText)
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
                        node: node,
                        validationError: vm.validationError,
                        allowNameEditing: node.allowsInlineNameEditing,
                        saveChanges: { vm.saveEdits() },
                        cancelChanges: { vm.cancelEditing() },
                        deleteNode: { deleteNode(node: node) },
                        clearValidation: { vm.validationError = nil }
                    )
                } else {
                    if isSectionLabelEntry {
                        SectionLabelRow(node: node, startEditing: { vm.startEditing(node: node) })
                    } else {
                        Button(action: { vm.startEditing(node: node) }) {
                            Group {
                                if !node.name.isEmpty && !node.value.isEmpty {
                                    StackedTextRow(
                                        title: node.name.titleCased,
                                        description: node.value
                                    )
                                } else if node.name.isEmpty && !node.value.isEmpty {
                                    AlignedTextRow(
                                        leadingText: node.value,
                                        trailingText: nil
                                    )
                                } else {
                                    AlignedTextRow(
                                        leadingText: node.name.titleCased,
                                        trailingText: node.value
                                    )
                                }
                            }
                            Spacer()
                        }
                        .buttonStyle(.plain)
                        .disabled(node.status == LeafStatus.disabled)
                    }
                }
            }
        }
        .onChange(of: node.value) { _, _ in vm.refreshPDF() }
        .onChange(of: node.name) { _, _ in vm.refreshPDF() }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
        .cornerRadius(5)
    }

    // MARK: - AI Menu

    @ViewBuilder
    private var nodeAIMenu: some View {
        let isSolo = node.status == .aiToReplace

        Text("AI Review")

        Divider()

        Button {
            toggleNodeStatus()
        } label: {
            HStack {
                Image(systemName: "target")
                    .foregroundColor(.teal)
                Text("Solo - this field only")
                if isSolo { Image(systemName: "checkmark") }
            }
        }

        if isSolo {
            Divider()

            Button(role: .destructive) {
                node.status = .saved
            } label: {
                Label("Disable AI Review", systemImage: "xmark.circle")
            }
        }
    }

    // MARK: - Actions
    private func toggleNodeStatus() {
        if node.status == LeafStatus.saved {
            node.status = .aiToReplace
        } else if node.status == LeafStatus.aiToReplace {
            node.status = .saved
        }
    }

    private func deleteNode(node: TreeNode) {
        vm.deleteNode(node, context: context)
    }
}

// MARK: - Section Label Row

/// Click-to-edit row for section labels - shows key name above, editable label below
private struct SectionLabelRow: View {
    let node: TreeNode
    let startEditing: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: startEditing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name.titleCased)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(node.label)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isHovering ? Color.primary.opacity(0.05) : Color.clear)
            .cornerRadius(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
