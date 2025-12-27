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

    /// Whether this collection has BOTH bundle and iterate modes (mixed mode)
    private var hasMixedModes: Bool {
        node.bundledAttributes?.isEmpty == false && node.enumeratedAttributes?.isEmpty == false
    }

    /// Current AI review mode for this node (primary mode if mixed)
    private var aiMode: AIReviewMode {
        if node.bundledAttributes?.isEmpty == false {
            return .bundle
        } else if node.enumeratedAttributes?.isEmpty == false {
            return .iterate
        } else if node.status == .aiToReplace {
            return .solo  // Solo mode for directly marked nodes
        } else if node.aiStatusChildren > 0 {
            return .solo  // Show solo indicator when children have AI status
        }
        return .off
    }

    /// Whether this is a collection node that supports bundle/iterate modes
    private var isCollectionNode: Bool {
        node.isCollectionNode
    }

    /// The grandparent node (collection level) if this node is an attribute under an entry
    private var grandparentNode: TreeNode? {
        node.parent?.parent
    }

    /// The attribute name for bundle/iterate configuration
    private var attributeName: String {
        node.name.isEmpty ? node.displayLabel : node.name
    }

    /// Whether this node is an attribute under a collection entry (e.g., "keywords" under a skill)
    /// True if grandparent is a collection node OR has bundle/iterate settings for this attribute
    private var isAttributeOfCollectionEntry: Bool {
        guard let grandparent = grandparentNode else { return false }
        // Check if grandparent has AI review settings for this attribute
        let attr = attributeName
        if grandparent.bundledAttributes?.contains(attr) == true { return true }
        if grandparent.enumeratedAttributes?.contains(attr) == true { return true }
        // Fall back to structural check - but exclude root (grandparent must have a parent)
        guard grandparent.parent != nil else { return false }
        return grandparent.isCollectionNode
    }

    /// The collection node (grandparent) when this is an attribute of a collection entry
    private var collectionNode: TreeNode? {
        guard isAttributeOfCollectionEntry else { return nil }
        return grandparentNode
    }

    /// Current mode for this specific attribute across the collection
    private var attributeMode: AIReviewMode {
        guard let grandparent = grandparentNode else { return .off }
        let attr = attributeName
        if grandparent.bundledAttributes?.contains(attr) == true {
            return .bundle  // Purple - 1 revnode total (all entries combined)
        } else if grandparent.enumeratedAttributes?.contains(attr) == true {
            return .iterate  // Cyan - N revnodes (1 per entry)
        } else if node.status == .aiToReplace {
            return .solo  // Orange - just this single node
        }
        return .off
    }

    /// Whether this attribute is extracted per-entry (vs all-combined)
    private var isPerEntryExtraction: Bool {
        guard let grandparent = grandparentNode else { return false }
        return grandparent.enumeratedAttributes?.contains(attributeName) == true
    }

    /// Generate the path pattern for this node's review configuration
    private var pathPattern: String? {
        guard let grandparent = grandparentNode else { return nil }
        let attr = attributeName
        let collectionName = grandparent.name.isEmpty ? grandparent.displayLabel : grandparent.name

        if grandparent.bundledAttributes?.contains(attr) == true {
            return "\(collectionName.lowercased()).*.\(attr)"  // e.g., skills.*.name
        } else if grandparent.enumeratedAttributes?.contains(attr) == true {
            return "\(collectionName.lowercased())[].\(attr)"  // e.g., skills[].keywords
        }
        return nil
    }

    /// Whether this node is a child of a container being reviewed (bundle/iterate)
    /// e.g., "Swift" is a child of "keywords" which is set to iterate
    private var isChildOfReviewedContainer: Bool {
        guard let parent = node.parent,
              let grandparent = parent.parent,
              let greatGrandparent = grandparent.parent else { return false }

        let parentName = parent.name.isEmpty ? parent.displayLabel : parent.name

        // Check if great-grandparent has parent's name in bundle/iterate
        if greatGrandparent.bundledAttributes?.contains(parentName) == true { return true }
        if greatGrandparent.enumeratedAttributes?.contains(parentName) == true { return true }

        return false
    }

    /// Whether this node is an entry under a collection with review config
    /// e.g., "Software Engineering" is an entry under "Skills" which has enumeratedAttributes
    private var isEntryUnderReviewedCollection: Bool {
        guard let parent = node.parent else { return false }
        // Exclude container enumerate children - they get icon + background, not outline
        if parent.enumeratedAttributes?.contains("*") == true { return false }
        return parent.bundledAttributes?.isEmpty == false || parent.enumeratedAttributes?.isEmpty == false
    }

    /// Whether this node is a child of a container enumerate pattern (parent has enumeratedAttributes: ["*"])
    /// e.g., "Physicist" under "Job Titles" where jobTitles[] is configured
    private var isContainerEnumerateChild: Bool {
        guard let parent = node.parent else { return false }
        return parent.enumeratedAttributes?.contains("*") == true
    }

    /// Whether to show the AI mode indicator (icon badge)
    private var showAIModeIndicator: Bool {
        // Entry nodes get outline instead of icon - never show icon
        if isEntryUnderReviewedCollection { return false }

        return node.parent != nil && (
            node.status == .aiToReplace ||
            node.aiStatusChildren > 0 ||
            node.hasAttributeReviewModes ||
            isContainerEnumerateNode ||
            isAttributeOfCollectionEntry ||
            isChildOfReviewedContainer ||
            isContainerEnumerateChild ||
            isHoveringHeader
        )
    }

    /// Whether clicking the AI mode indicator should toggle mode
    /// Only interactive on attribute nodes - collection nodes show read-only summary
    private var isAIModeInteractive: Bool {
        isAttributeOfCollectionEntry && !isChildOfReviewedContainer
    }

    /// Whether this node is itself a container enumerate node (has enumeratedAttributes["*"])
    private var isContainerEnumerateNode: Bool {
        node.enumeratedAttributes?.contains("*") == true
    }

    /// The mode to display for this node
    private var displayMode: AIReviewMode {
        // Container enumerate node (e.g., jobTitles with enumeratedAttributes["*"])
        // Shows cyan iterate icon (the container itself, not children)
        if isContainerEnumerateNode {
            return .iterate
        }
        // Container enumerate children get iterate mode (cyan icon + background)
        if isContainerEnumerateChild {
            return .iterate
        }
        // Check if this is a child of a reviewed container first
        if isChildOfReviewedContainer {
            return .included
        }
        // Entry under reviewed collection (e.g., Software Engineering under Skills)
        if isEntryUnderReviewedCollection {
            return .included  // Show included indicator (but no icon, just outline)
        }
        if isAttributeOfCollectionEntry {
            return attributeMode
        }
        return aiMode
    }

    /// Background color for the entire row based on AI review mode
    private var rowBackgroundColor: Color {
        // Entry nodes under mixed mode collections get purple background (checked before showAIModeIndicator)
        if isEntryUnderReviewedCollection {
            if let parent = node.parent,
               parent.bundledAttributes?.isEmpty == false,
               parent.enumeratedAttributes?.isEmpty == false {
                return .purple.opacity(0.15)  // Mixed mode: purple background
            }
            return .clear  // Single mode: outline only
        }

        guard showAIModeIndicator else { return .clear }

        // Container enumerate nodes get icon only, no background (children are the revnodes)
        if isContainerEnumerateNode {
            return .clear
        }

        // Collection nodes with mixed mode get purple background
        if isCollectionNode && hasMixedModes {
            return .purple.opacity(0.15)
        }
        // Collection nodes with single mode get no background (icon only)
        if isCollectionNode && (node.bundledAttributes?.isEmpty == false || node.enumeratedAttributes?.isEmpty == false) {
            return .clear
        }

        let mode = displayMode
        guard mode != .off else { return .clear }
        return mode.color.opacity(0.15)
    }

    /// Outline color for entry nodes
    private var entryOutlineColor: Color {
        guard isEntryUnderReviewedCollection, let parent = node.parent else { return .clear }
        let hasBundled = parent.bundledAttributes?.isEmpty == false
        let hasEnumerated = parent.enumeratedAttributes?.isEmpty == false

        // Mixed mode: cyan outline (purple shown via background)
        if hasBundled && hasEnumerated {
            return .cyan.opacity(0.5)
        }
        // Single mode: outline matches the mode
        if hasBundled {
            return .purple.opacity(0.5)
        } else if hasEnumerated {
            return .cyan.opacity(0.5)
        }
        return .clear
    }

    var body: some View {
        HStack {
            ToggleChevronView(isExpanded: isExpanded)

            // Node label - use .saved for parent nodes since background color shows AI status
            if node.parent == nil {
                HeaderTextRow()
            } else {
                AlignedTextRow(
                    leadingText: node.isTitleNode && !node.name.isEmpty ? node.name : node.displayLabel,
                    trailingText: nil
                )
            }

            Spacer()

            // AI mode indicator(s)
            if showAIModeIndicator {
                HStack(spacing: 4) {
                    // Show both icons for mixed mode collections (bundle + iterate)
                    if hasMixedModes && isCollectionNode {
                        AIModeIndicator(
                            mode: .bundle,
                            isCollection: true,
                            pathPattern: nil,
                            isPerEntry: false
                        )
                        AIModeIndicator(
                            mode: .iterate,
                            isCollection: true,
                            pathPattern: nil,
                            isPerEntry: true
                        )
                    } else {
                        AIModeIndicator(
                            mode: displayMode,
                            isCollection: isCollectionNode || isAttributeOfCollectionEntry,
                            pathPattern: pathPattern,
                            isPerEntry: isPerEntryExtraction
                        )
                        .onTapGesture {
                            guard isAIModeInteractive else { return }
                            toggleAttributeMode()
                        }
                        .opacity(isAIModeInteractive ? 1.0 : 0.6)
                    }
                }
            }

            // Expanded controls
            if vm.isExpanded(node) && node.parent != nil && !node.orderedChildren.isEmpty {
                expandedControls
            }
        }
        .padding(.leading, CGFloat(max(0, node.depth - depthOffset) * 20) + 10)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .background(rowBackgroundColor)
        .cornerRadius(6)
        .overlay(
            // Outline for entry nodes under reviewed collection
            RoundedRectangle(cornerRadius: 6)
                .stroke(entryOutlineColor, lineWidth: 1.5)
        )
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
            HStack {
                Label("Review once (all combined)", systemImage: "square.stack.3d.up.fill")
                if attributeMode == .bundle { Image(systemName: "checkmark") }
            }
        }

        Button {
            setAttributeMode(.iterate)
        } label: {
            HStack {
                Label("Review per entry (N reviews)", systemImage: "list.bullet")
                if attributeMode == .iterate { Image(systemName: "checkmark") }
            }
        }

        Button {
            setAttributeMode(.solo)
        } label: {
            HStack {
                Label("Just this entry", systemImage: "scope")
                if attributeMode == .solo { Image(systemName: "checkmark") }
            }
        }

        Divider()

        Button {
            setAttributeMode(.off)
        } label: {
            HStack {
                Label("Off", systemImage: "xmark.circle")
                if attributeMode == .off { Image(systemName: "checkmark") }
            }
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
        case .included:
            break  // Children of reviewed containers can't be toggled directly
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
            // Don't set collection.status - the collection itself isn't reviewed
            // Clear solo status from individual nodes
            clearSoloStatusForAttribute(attr, in: collection)

        case .iterate:
            // Add to enumerated attributes on collection node
            if collection.enumeratedAttributes == nil {
                collection.enumeratedAttributes = []
            }
            collection.enumeratedAttributes?.append(attr)
            // Don't set collection.status - the collection itself isn't reviewed
            // Don't mark entries - the attribute nodes within entries are what's reviewed
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

        case .included:
            break  // Not a valid mode to set directly - it's derived from parent state
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
    case included // Cyan - child of a reviewed container (uses same color as iterate)
    case off      // Gray - disabled

    var color: Color {
        switch self {
        case .bundle: return .purple
        case .iterate: return .cyan
        case .solo: return .orange
        case .included: return .cyan  // Same as iterate - children inherit parent's color
        case .off: return .gray
        }
    }

    var icon: String {
        switch self {
        case .bundle: return "square.stack.3d.up.fill"
        case .iterate: return "list.bullet"
        case .solo: return "sparkles"  // Use sparkles for solo - consistent with SparkleButton
        case .included: return "sparkles"
        case .off: return "sparkles"
        }
    }
}

// MARK: - AI Mode Indicator

struct AIModeIndicator: View {
    let mode: AIReviewMode
    let isCollection: Bool
    var pathPattern: String?
    var isPerEntry: Bool = false

    var body: some View {
        Image(systemName: mode == .off ? "sparkles" : mode.icon)
            .foregroundColor(mode == .off ? .gray : .white)  // White icon for contrast
            .font(.system(size: 12))
            .fontWeight(.semibold)
            .padding(4)
            .background(mode == .off ? Color.gray.opacity(0.15) : mode.color.opacity(0.85))
            .cornerRadius(4)
            .help(helpText)
    }

    private var helpText: String {
        var text: String
        switch mode {
        case .bundle:
            if isPerEntry {
                text = "Extracted per entry (bundled within each)"
            } else {
                text = "Bundle: All entries combined into 1 review"
            }
        case .iterate:
            text = "Iterate: N reviews (one per entry)"
        case .solo:
            text = "Solo: Just this one item"
        case .included:
            text = "Included in parent's review"
        case .off:
            text = "Click to enable AI review"
        }

        if let pattern = pathPattern {
            text += "\nPath: \(pattern)"
        }
        return text
    }
}
