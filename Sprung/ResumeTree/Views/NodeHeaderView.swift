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

            // Parent sparkle button - show when hovering or when node/children are selected
            if node.parent != nil && (isHoveringHeader || node.status == .aiToReplace || node.aiStatusChildren > 0) {
                SparkleButton(
                    node: nodeBinding,
                    isHovering: $isHoveringSparkle,
                    toggleNodeStatus: {
                        // Toggle parent and propagate to all children
                        node.toggleAISelection(propagateToChildren: true)
                    }
                )
                .transition(.opacity)
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
        .padding(.leading, CGFloat(node.depth * 20))
        .padding(.vertical, 5)
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
