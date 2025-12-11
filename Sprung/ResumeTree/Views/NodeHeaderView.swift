//
//  NodeHeaderView.swift
//  Sprung
//
//
import SwiftUI
/// Header row for a parent node.  No state lives here; it queries and mutates
/// expansion state through `ResumeDetailVM`.
struct NodeHeaderView: View {
    let node: TreeNode
    /// Depth offset to subtract when calculating indentation (for flattened container children)
    var depthOffset: Int = 0
    let addChildAction: () -> Void
    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM
    // Bindings that forward to the view‑model properties.
    private var isExpanded: Binding<Bool> {
        Binding(
            get: { vm.isExpanded(node) },
            set: { _ in vm.toggleExpansion(for: node) }
        )
    }
    // Accessors kept for future controls if needed.
    @State private var isHoveringAdd = false
    @State private var isHoveringAll = false
    @State private var isHoveringNone = false
    @State private var isHoveringSparkle = false
    @State private var isHoveringHeader = false
    @State private var showAttributePicker = false

    /// Binding wrapper to make TreeNode work with SparkleButton
    private var nodeBinding: Binding<TreeNode> {
        Binding(
            get: { node },
            set: { _ in }  // TreeNode is a class, mutations happen directly
        )
    }

    var body: some View {
        HStack {
            ToggleChevronView(isExpanded: isExpanded, )
            if node.parent == nil {
                HeaderTextRow()
            } else {
                AlignedTextRow(
                    leadingText: node.isTitleNode && !node.name.isEmpty ? node.name : node.displayLabel,
                    trailingText: nil,
                    nodeStatus: node.status
                )
            }
            Spacer()

            // Parent sparkle button - always rendered to prevent layout shifts
            // Opacity controlled by hover/selection state
            if node.parent != nil {
                let showSparkle = isHoveringHeader || isHoveringSparkle || node.status == .aiToReplace || node.aiStatusChildren > 0 || node.isGroupInheritedSelection
                SparkleButton(
                    node: nodeBinding,
                    isHovering: $isHoveringSparkle,
                    toggleNodeStatus: {
                        // Toggle parent and propagate to all children
                        node.toggleAISelection(propagateToChildren: true)
                    },
                    onShowAttributePicker: {
                        showAttributePicker = true
                    }
                )
                .opacity(showSparkle ? 1.0 : 0.0)
                .allowsHitTesting(true)  // Ensure button is always clickable even when faded
                .popover(isPresented: $showAttributePicker) {
                    AttributePickerView(
                        collectionNode: node,
                        onApply: { selections in
                            // Clear previous group selection from this node
                            node.clearGroupSelection()
                            // Apply new group selection with modes
                            node.applyGroupSelection(selections: selections, sourceId: node.id)
                            showAttributePicker = false
                        },
                        onCancel: {
                            showAttributePicker = false
                        }
                    )
                }
            }

            // Show controls when node is expanded and has children
            if vm.isExpanded(node) && node.parent != nil {
                // All/None buttons for bulk operations if there are children
                if !node.orderedChildren.isEmpty {
                    // All button
                    Button(action: { vm.setAllChildrenToAI(for: node) }) {
                        Text("All")
                            .font(.caption)
                            .foregroundColor(isHoveringAll ? .blue : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(isHoveringAll ? Color.white.opacity(0.4) : Color.clear)
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { hovering in isHoveringAll = hovering }
                    .help("Mark all children for AI processing")
                    // None button
                    Button(action: { vm.setAllChildrenToNone(for: node) }) {
                        Text("None")
                            .font(.caption)
                            .foregroundColor(isHoveringNone ? .orange : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(isHoveringNone ? Color.white.opacity(0.4) : Color.clear)
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { hovering in isHoveringNone = hovering }
                    .help("Clear AI processing for all children")
                }
                // Add child button when manifest allows manual mutations.
                if node.allowsChildAddition {
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
                    .onHover { hovering in isHoveringAdd = hovering }
                }
            }
            StatusBadgeView(node: node, isExpanded: vm.isExpanded(node))
        }
        .padding(.horizontal, 10)
        .padding(.leading, CGFloat(max(0, node.depth - depthOffset) * 20))
        .padding(.vertical, 5)
        .contentShape(Rectangle())  // Make entire row respond to hover/tap
        .onTapGesture {
            vm.toggleExpansion(for: node)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHoveringHeader = hovering
            }
        }
    }
}
