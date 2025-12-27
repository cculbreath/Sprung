//
//  NodeHeaderView.swift
//  Sprung
//
//
import SwiftUI

/// Header row for a parent node. Displays node label, AI mode indicator, and controls.
///
/// AI Review Modes (for collection nodes like skills, work):
/// - **Bundle** (purple): All entries combined into 1 RevNode for holistic review
/// - **Iterate** (cyan): Each entry becomes separate RevNode for individual review
/// - **Off**: No AI review for this attribute
///
/// Click sparkle to toggle AI on/off. Right-click for mode options.
struct NodeHeaderView: View {
    let node: TreeNode
    var depthOffset: Int = 0
    let addChildAction: () -> Void
    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM

    @State private var isHoveringAdd = false
    @State private var isHoveringHeader = false

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { vm.isExpanded(node) },
            set: { _ in vm.toggleExpansion(for: node) }
        )
    }

    // MARK: - AI Mode Detection

    /// Current AI review mode for this node
    private var aiMode: AIReviewMode {
        if node.bundledAttributes?.isEmpty == false {
            return .bundle
        } else if node.enumeratedAttributes?.isEmpty == false {
            return .iterate
        } else if node.status == .aiToReplace {
            return .iterate // Default for simple AI-enabled nodes
        }
        return .off
    }

    /// Whether this is a collection node that supports bundle/iterate modes
    private var isCollectionNode: Bool {
        node.isCollectionNode
    }

    /// Whether this node is an attribute under a collection entry (e.g., "keywords" under a skill)
    /// These are the nodes where bundle/iterate mode is configured
    private var isAttributeOfCollectionEntry: Bool {
        guard let parent = node.parent,
              let grandparent = parent.parent else { return false }
        return grandparent.isCollectionNode
    }

    /// The collection node (grandparent) when this is an attribute of a collection entry
    private var collectionNode: TreeNode? {
        guard isAttributeOfCollectionEntry else { return nil }
        return node.parent?.parent
    }

    /// The attribute name for bundle/iterate configuration
    private var attributeName: String {
        node.name.isEmpty ? node.displayLabel : node.name
    }

    /// Current mode for this specific attribute across the collection
    private var attributeMode: AIReviewMode {
        guard let collection = collectionNode else { return .off }
        if collection.bundledAttributes?.contains(attributeName) == true {
            return .bundle
        } else if collection.enumeratedAttributes?.contains(attributeName) == true {
            return .iterate
        } else if node.status == .aiToReplace {
            return .solo  // Just this single node marked for review
        }
        return .off
    }

    /// Whether to show the AI mode indicator
    private var showAIModeIndicator: Bool {
        node.parent != nil && (
            node.status == .aiToReplace ||
            node.aiStatusChildren > 0 ||
            node.hasAttributeReviewModes ||
            isAttributeOfCollectionEntry ||  // Show for attribute nodes
            isHoveringHeader
        )
    }

    /// The mode to display for this node
    private var displayMode: AIReviewMode {
        if isAttributeOfCollectionEntry {
            return attributeMode
        }
        return aiMode
    }

    var body: some View {
        HStack {
            ToggleChevronView(isExpanded: isExpanded)

            // Node label
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

            // AI mode indicator with sparkle
            if showAIModeIndicator {
                AIModeIndicator(mode: displayMode, isCollection: isCollectionNode || isAttributeOfCollectionEntry)
                    .onTapGesture {
                        if isAttributeOfCollectionEntry {
                            toggleAttributeMode()
                        } else {
                            toggleAIStatus()
                        }
                    }
            }

            // Expanded controls
            if vm.isExpanded(node) && node.parent != nil && !node.orderedChildren.isEmpty {
                expandedControls
            }

            StatusBadgeView(node: node, isExpanded: vm.isExpanded(node))
        }
        .padding(.horizontal, 10)
        .padding(.leading, CGFloat(max(0, node.depth - depthOffset) * 20))
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture {
            vm.toggleExpansion(for: node)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHoveringHeader = hovering
            }
        }
        .contextMenu {
            if isAttributeOfCollectionEntry {
                attributeModeContextMenu
            } else if node.parent != nil {
                aiModeContextMenu
            }
        }
    }

    // MARK: - Context Menu

    /// Context menu for attribute nodes under collection entries
    @ViewBuilder
    private var attributeModeContextMenu: some View {
        Text("AI Review: \(attributeName)").font(.headline)
        Divider()

        Button {
            setAttributeMode(.bundle)
        } label: {
            Label("Bundle (All Together)", systemImage: "square.stack.3d.up.fill")
            if attributeMode == .bundle { Image(systemName: "checkmark") }
        }

        Button {
            setAttributeMode(.iterate)
        } label: {
            Label("Iterate (Each Separately)", systemImage: "list.bullet")
            if attributeMode == .iterate { Image(systemName: "checkmark") }
        }

        Button {
            setAttributeMode(.solo)
        } label: {
            Label("Solo (Just This One)", systemImage: "scope")
            if attributeMode == .solo { Image(systemName: "checkmark") }
        }

        Divider()

        Button {
            setAttributeMode(.off)
        } label: {
            Label("Off", systemImage: "xmark.circle")
            if attributeMode == .off { Image(systemName: "checkmark") }
        }
    }

    @ViewBuilder
    private var aiModeContextMenu: some View {
        // Simple nodes: just on/off
        Button {
            toggleAIStatus()
        } label: {
            if node.status == .aiToReplace {
                Label("Disable AI Review", systemImage: "sparkles.slash")
            } else {
                Label("Enable AI Review", systemImage: "sparkles")
            }
        }
    }

    // MARK: - Expanded Controls

    @ViewBuilder
    private var expandedControls: some View {
        // Add child button
        if node.allowsChildAddition {
            Button(action: addChildAction) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(isHoveringAdd ? .green : .secondary)
                    .font(.system(size: 14))
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { isHoveringAdd = $0 }
            .help("Add child")
        }
    }

    // MARK: - Actions

    private func toggleAIStatus() {
        if node.status == .aiToReplace {
            node.status = .saved
            node.bundledAttributes = nil
            node.enumeratedAttributes = nil
        } else {
            node.status = .aiToReplace
        }
    }

    /// Toggle through attribute modes: off → bundle → iterate → solo → off
    private func toggleAttributeMode() {
        switch attributeMode {
        case .off:
            setAttributeMode(.bundle)
        case .bundle:
            setAttributeMode(.iterate)
        case .iterate:
            setAttributeMode(.solo)
        case .solo:
            setAttributeMode(.off)
        }
    }

    /// Set the AI review mode for this attribute across the collection
    private func setAttributeMode(_ mode: AIReviewMode) {
        guard let collection = collectionNode else { return }
        let attr = attributeName

        // Clear this attribute from any existing mode
        collection.bundledAttributes?.removeAll { $0 == attr }
        collection.enumeratedAttributes?.removeAll { $0 == attr }

        switch mode {
        case .bundle:
            // Add to bundled attributes on collection node
            if collection.bundledAttributes == nil {
                collection.bundledAttributes = []
            }
            collection.bundledAttributes?.append(attr)
            collection.status = .aiToReplace
            // Clear solo status from individual nodes
            clearSoloStatusForAttribute(attr, in: collection)

        case .iterate:
            // Add to enumerated attributes on collection node
            if collection.enumeratedAttributes == nil {
                collection.enumeratedAttributes = []
            }
            collection.enumeratedAttributes?.append(attr)
            collection.status = .aiToReplace
            // Mark each entry for iteration
            for entry in collection.orderedChildren {
                entry.status = .aiToReplace
            }
            // Clear solo status from individual nodes
            clearSoloStatusForAttribute(attr, in: collection)

        case .solo:
            // Just mark this specific node
            node.status = .aiToReplace

        case .off:
            // Clear this node's status
            node.status = .saved
            // Clear solo status from all matching attribute nodes
            clearSoloStatusForAttribute(attr, in: collection)
        }

        // Clean up empty arrays
        if collection.bundledAttributes?.isEmpty == true {
            collection.bundledAttributes = nil
        }
        if collection.enumeratedAttributes?.isEmpty == true {
            collection.enumeratedAttributes = nil
        }

        // Update collection status if no attributes remain
        if collection.bundledAttributes == nil && collection.enumeratedAttributes == nil {
            let hasAnyMarkedChildren = collection.orderedChildren.contains { entry in
                entry.status == .aiToReplace ||
                entry.orderedChildren.contains { $0.status == .aiToReplace }
            }
            if !hasAnyMarkedChildren {
                collection.status = .saved
            }
        }
    }

    /// Clear solo (aiToReplace) status from all nodes matching this attribute name
    private func clearSoloStatusForAttribute(_ attr: String, in collection: TreeNode) {
        for entry in collection.orderedChildren {
            for attrNode in entry.orderedChildren {
                let nodeName = attrNode.name.isEmpty ? attrNode.displayLabel : attrNode.name
                if nodeName == attr && attrNode.status == .aiToReplace {
                    attrNode.status = .saved
                }
            }
        }
    }
}

// MARK: - AI Review Mode

enum AIReviewMode {
    case bundle   // Purple - all together across entries
    case iterate  // Cyan - each entry separately
    case solo     // Orange - just this single node
    case off      // Gray - disabled

    var color: Color {
        switch self {
        case .bundle: return .purple
        case .iterate: return .cyan
        case .solo: return .orange
        case .off: return .gray
        }
    }

    var icon: String {
        switch self {
        case .bundle: return "square.stack.3d.up.fill"
        case .iterate: return "list.bullet"
        case .solo: return "scope"
        case .off: return "sparkles"
        }
    }
}

// MARK: - AI Mode Indicator

struct AIModeIndicator: View {
    let mode: AIReviewMode
    let isCollection: Bool

    var body: some View {
        Image(systemName: mode == .off ? "sparkles" : mode.icon)
            .foregroundColor(mode.color)
            .font(.system(size: 12))
            .padding(4)
            .background(mode.color.opacity(0.15))
            .cornerRadius(4)
            .help(helpText)
    }

    private var helpText: String {
        switch mode {
        case .bundle: return "Bundle: All items reviewed together"
        case .iterate: return "Iterate: Each item reviewed separately"
        case .solo: return "Solo: Just this one item"
        case .off: return "Click to enable AI review"
        }
    }
}
