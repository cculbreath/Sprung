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
    /// Key: suffix determines color - no suffix = purple (bundled), [] suffix = cyan (each separate)
    private var containerReviewBackgroundColor: Color? {
        guard let parent = node.parent else { return nil }

        // Check for container bundle (parent has bundledAttributes: ["*"])
        // e.g., Physicist under Job Titles where jobTitles is bundled
        if parent.bundledAttributes?.contains("*") == true {
            return .purple.opacity(0.15)  // Purple for container bundle
        }

        // Check for container enumerate (parent has enumeratedAttributes: ["*"])
        // e.g., Physicist under Job Titles where jobTitles[] is configured
        if parent.enumeratedAttributes?.contains("*") == true {
            return .cyan.opacity(0.15)  // Cyan for container enumerate
        }

        // Check if THIS node is a scalar attribute directly under an entry
        // e.g., "name" leaf when skills[].name or skills.*.name is configured
        // For scalars: enumeratedAttributes = cyan (each separate), bundledAttributes = purple (all combined)
        if let collection = parent.parent {
            let nodeName = node.name.isEmpty ? node.displayLabel : node.name
            // enumeratedAttributes["name"] = each entry's name is separate → cyan
            if collection.enumeratedAttributes?.contains(nodeName) == true {
                return .cyan.opacity(0.15)  // Cyan - iterate, each entry's value separate
            }
            // bundledAttributes["name"] = all names combined → purple
            if collection.bundledAttributes?.contains(nodeName) == true {
                return .purple.opacity(0.15)  // Purple - bundled together
            }
        }

        // Check if parent is being reviewed as part of bundle/iterate attribute
        // e.g., Swift under keywords when skills.*.keywords is configured
        guard let entry = parent.parent,
              let collection = entry.parent else { return nil }

        let containerName = parent.name.isEmpty ? parent.displayLabel : parent.name
        let containerNameWithSuffix = containerName + "[]"

        // Check for each-separate patterns first (cyan) - has [] suffix
        if collection.bundledAttributes?.contains(containerNameWithSuffix) == true ||
           collection.enumeratedAttributes?.contains(containerNameWithSuffix) == true {
            return .cyan.opacity(0.15)  // Cyan - each item separate
        }

        // Check for bundled patterns (purple) - no [] suffix
        if collection.bundledAttributes?.contains(containerName) == true ||
           collection.enumeratedAttributes?.contains(containerName) == true {
            return .purple.opacity(0.15)  // Purple - bundled together
        }

        return nil
    }

    /// Whether this is a container enumerate child (should show icon + background)
    /// Only true when parent has enumeratedAttributes["*"] - each scalar value is separate
    private var isContainerEnumerateChild: Bool {
        guard let parent = node.parent else { return false }
        return parent.enumeratedAttributes?.contains("*") == true
    }

    /// Whether this leaf is a child of an "each item separate" container (icon + cyan bg)
    /// e.g., each bullet under highlights when work[].highlights[] is configured
    private var isEachItemSeparateChild: Bool {
        guard let parent = node.parent,
              let entry = parent.parent,
              let collection = entry.parent else { return false }
        let containerName = parent.name.isEmpty ? parent.displayLabel : parent.name
        let containerNameWithSuffix = containerName + "[]"
        // Has [] suffix = each item is separate = show icon
        return collection.enumeratedAttributes?.contains(containerNameWithSuffix) == true ||
               collection.bundledAttributes?.contains(containerNameWithSuffix) == true
    }

    /// Whether this leaf IS an iterate attribute target (icon + cyan bg)
    /// e.g., "name" leaf when skills[].name is configured - each name is a separate revnode
    private var isIterateAttributeTarget: Bool {
        guard let parent = node.parent,
              let collection = parent.parent else { return false }
        let nodeName = node.name.isEmpty ? node.displayLabel : node.name
        // Scalar attributes in enumeratedAttributes get icons (each is separate revnode)
        return collection.enumeratedAttributes?.contains(nodeName) == true
    }

    /// Whether this leaf produces a revnode (should show icon)
    /// Icons shown when: container enumerate children, or items marked as "each separate" with [] suffix
    /// No icon when: bundled together (no [] suffix)
    private var isRevnodeLeaf: Bool {
        isContainerEnumerateChild || isEachItemSeparateChild || isIterateAttributeTarget
    }
    var body: some View {
        let isSectionLabelEntry = node.parent?.name == "section-labels"
        HStack(spacing: 5) {
            if node.value.isEmpty && !isSectionLabelEntry && !isEditing {
                Spacer().frame(width: 50)
                Text(node.name.isEmpty ? "Empty" : node.name)
                    .foregroundColor(.gray)
                    .italic()
                // Allow editing empty nodes
                Button(action: { vm.startEditing(node: node) }) {
                    Image(systemName: "square.and.pencil")
                        .foregroundColor(isHoveringEdit ? .primary : .secondary)
                        .font(.system(size: 14))
                        .padding(5)
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { hovering in isHoveringEdit = hovering }
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
