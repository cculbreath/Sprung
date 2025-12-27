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
    // Local UI state (hover effects)
    @State private var isHoveringEdit: Bool = false
    @State private var isHoveringSparkles: Bool = false
    // Derived editing bindings
    private var isEditing: Bool { vm.editingNodeID == node.id }

    /// Background color based on whether this node is part of a container review
    private var containerReviewBackgroundColor: Color? {
        guard let parent = node.parent else { return nil }

        // Check for container enumerate (parent has enumeratedAttributes: ["*"])
        // e.g., Physicist under Job Titles where jobTitles[] is configured
        if parent.enumeratedAttributes?.contains("*") == true {
            return .cyan.opacity(0.15)  // Cyan for container enumerate
        }

        // Check if THIS node is an iterate attribute target
        // e.g., description when projects[].description is configured
        if let collection = parent.parent {
            let nodeName = node.name.isEmpty ? node.displayLabel : node.name
            if collection.enumeratedAttributes?.contains(nodeName) == true {
                return .cyan.opacity(0.15)  // Cyan for iterate attribute target
            }
        }

        // Check if parent is being reviewed as part of bundle/iterate attribute
        // e.g., Swift under keywords when skills.*.keywords is configured
        guard let entry = parent.parent,
              let collection = entry.parent else { return nil }

        let containerName = parent.name.isEmpty ? parent.displayLabel : parent.name

        if collection.bundledAttributes?.contains(containerName) == true {
            return .purple.opacity(0.15)  // Purple for bundle children
        } else if collection.enumeratedAttributes?.contains(containerName) == true {
            return .cyan.opacity(0.15)  // Cyan for children of iterate container
        }
        return nil
    }

    /// Whether this is a container enumerate child (should show icon + background)
    private var isContainerEnumerateChild: Bool {
        guard let parent = node.parent else { return false }
        return parent.enumeratedAttributes?.contains("*") == true
    }

    /// Whether this leaf is a child OF an iterate container (bg only, no icon)
    /// e.g., bullet points under highlights when work[].highlights is configured
    private var isChildOfIterateContainer: Bool {
        guard let parent = node.parent,
              let entry = parent.parent,
              let collection = entry.parent else { return false }
        let containerName = parent.name.isEmpty ? parent.displayLabel : parent.name
        return collection.enumeratedAttributes?.contains(containerName) == true
    }

    /// Whether this leaf IS an iterate attribute target (icon + bg)
    /// e.g., description leaf when projects[].description is configured
    private var isIterateAttributeTarget: Bool {
        guard let parent = node.parent,
              let collection = parent.parent else { return false }
        let nodeName = node.name.isEmpty ? node.displayLabel : node.name
        return collection.enumeratedAttributes?.contains(nodeName) == true
    }

    /// Whether this leaf produces a revnode (should show icon)
    /// Container enumerate children and iterate attribute targets get icons
    /// Children OF iterate containers only get background (no icon)
    private var isRevnodeLeaf: Bool {
        isContainerEnumerateChild || isIterateAttributeTarget
    }
    var body: some View {
        let isSectionLabelEntry = node.parent?.name == "section-labels"
        HStack(spacing: 5) {
            if node.value.isEmpty && !isSectionLabelEntry {
                Spacer().frame(width: 50)
                Text(node.name)
                    .foregroundColor(.gray)
            } else {
                // Show SparkleButton for: normal nodes, solo nodes, and revnode leaves (container enum + iterate attr)
                // Hide for: bundle attribute children (background is sufficient)
                let shouldShowSparkle = node.status != LeafStatus.disabled &&
                    (containerReviewBackgroundColor == nil || isRevnodeLeaf)
                if shouldShowSparkle {
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
                        Text(node.label)
                            .foregroundColor(.primary)
                        Spacer()
                    } else if !node.name.isEmpty && !node.value.isEmpty {
                        StackedTextRow(
                            title: node.name,
                            description: node.value
                        )
                        Spacer()
                    } else if node.name.isEmpty && !node.value.isEmpty {
                        AlignedTextRow(
                            leadingText: node.value,
                            trailingText: nil
                        )
                        Spacer()
                    } else {
                        AlignedTextRow(
                            leadingText: node.name,
                            trailingText: node.value
                        )
                        Spacer()
                    }
                    if node.status != LeafStatus.disabled {
                        Button(action: { vm.startEditing(node: node) }) {
                            Image(systemName: "square.and.pencil")
                                .foregroundColor(isHoveringEdit ? .primary : .secondary)
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
        .padding(.horizontal, 12) // ← new: 24-pt right margin
        .background(leafBackgroundColor)
        .cornerRadius(5)
    }

    /// Computed background color for the leaf node
    private var leafBackgroundColor: Color {
        // Priority 1: Container review (bundle/iterate children)
        if let containerColor = containerReviewBackgroundColor {
            return containerColor
        }
        // Priority 2: Solo mode - directly selected (orange)
        if node.status == .aiToReplace {
            return Color.orange.opacity(0.15)
        }
        return Color.clear
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
        vm.deleteNode(node, context: context)
    }
}
