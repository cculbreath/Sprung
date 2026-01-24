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
            return .containsSolo  // Container has solo children (show outline only)
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
    /// For scalar attributes (no children):
    /// - bundledAttributes["name"] → purple (all combined)
    /// - enumeratedAttributes["name"] → cyan (each separate)
    /// For array attributes (has children):
    /// - *Attributes["keywords"] → purple (bundled together)
    /// - *Attributes["keywords[]"] → cyan (each item separate)
    private var attributeMode: AIReviewMode {
        guard let grandparent = grandparentNode else { return .off }
        let attr = attributeName
        let attrWithSuffix = attr + "[]"
        let isArrayAttribute = !node.orderedChildren.isEmpty

        if isArrayAttribute {
            // Array attribute: check for [] suffix to determine mode
            // With [] suffix = each item separate (cyan)
            if grandparent.bundledAttributes?.contains(attrWithSuffix) == true ||
               grandparent.enumeratedAttributes?.contains(attrWithSuffix) == true {
                return .iterate  // Cyan - each item is separate
            }
            // Without [] suffix = bundled together (purple)
            if grandparent.bundledAttributes?.contains(attr) == true ||
               grandparent.enumeratedAttributes?.contains(attr) == true {
                return .bundle  // Purple - items bundled together
            }
        } else {
            // Scalar attribute: enumeratedAttributes = cyan, bundledAttributes = purple
            if grandparent.enumeratedAttributes?.contains(attr) == true {
                return .iterate  // Cyan - each entry's value separate
            }
            if grandparent.bundledAttributes?.contains(attr) == true {
                return .bundle  // Purple - all values combined
            }
        }

        if node.status == .aiToReplace {
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

        // Containers of solo items get outline, not icon
        if aiMode == .containsSolo { return false }

        // Always show if node has actual AI configuration
        if node.parent != nil && (
            node.status == .aiToReplace ||
            node.hasAttributeReviewModes ||
            isContainerEnumerateNode ||
            isAttributeOfCollectionEntry ||
            isChildOfReviewedContainer ||
            isContainerEnumerateChild
        ) {
            return true
        }

        // Only show hover indicator for interactive nodes (attribute nodes that can be clicked)
        // or collection nodes (right-click menu available)
        if isHoveringHeader && node.parent != nil {
            return isAIModeInteractive || supportsCollectionModes
        }

        return false
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

    // MARK: - Collection Context Menu Helpers

    /// Whether this collection contains scalar values (no nested attributes)
    private var isScalarArrayCollection: Bool {
        guard !node.orderedChildren.isEmpty else { return false }
        guard let firstChild = node.orderedChildren.first else { return false }
        return firstChild.orderedChildren.isEmpty
    }

    /// Whether this node supports collection modes (bundle/iterate)
    /// True for any non-root node with children (both object arrays and scalar arrays)
    private var supportsCollectionModes: Bool {
        node.parent != nil && !node.orderedChildren.isEmpty
    }

    /// Get attribute names available in this collection's entries
    private var availableAttributes: [String] {
        guard let firstChild = node.orderedChildren.first else { return [] }
        return firstChild.orderedChildren.compactMap {
            let name = $0.name.isEmpty ? $0.displayLabel : $0.name
            return name.isEmpty ? nil : name
        }
    }

    /// Check if an attribute is itself an array (has children)
    private func isNestedArray(_ attrName: String) -> Bool {
        guard let firstChild = node.orderedChildren.first,
              let attr = firstChild.orderedChildren.first(where: {
                  ($0.name.isEmpty ? $0.displayLabel : $0.name) == attrName
              }) else { return false }
        return !attr.orderedChildren.isEmpty
    }

    /// Check if an attribute is currently in bundle mode
    private func isAttributeBundled(_ attr: String) -> Bool {
        node.bundledAttributes?.contains(attr) == true
    }

    /// Check if an attribute is currently in iterate mode
    private func isAttributeIterated(_ attr: String) -> Bool {
        node.enumeratedAttributes?.contains(attr) == true
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
                return .purple.opacity(0.075)  // Mixed mode: purple background (reduced opacity)
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
            return .purple.opacity(0.075)  // Reduced opacity
        }
        // Collection nodes with single mode get no background (icon only)
        if isCollectionNode && (node.bundledAttributes?.isEmpty == false || node.enumeratedAttributes?.isEmpty == false) {
            return .clear
        }

        // Array attribute nodes with [] suffix get icon only, no background (children are the revnodes)
        // e.g., highlights when work[].highlights[] is configured
        if isAttributeOfCollectionEntry && isIterateArrayAttribute {
            return .clear
        }

        let mode = displayMode
        guard mode != .off else { return .clear }
        return mode.color.opacity(0.075)  // Reduced opacity
    }

    /// Whether this is an array attribute marked with [] suffix (each item separate)
    private var isIterateArrayAttribute: Bool {
        guard let grandparent = grandparentNode else { return false }
        let attr = attributeName
        let attrWithSuffix = attr + "[]"
        // Only true for array attributes (has children) with [] suffix
        guard !node.orderedChildren.isEmpty else { return false }
        return grandparent.bundledAttributes?.contains(attrWithSuffix) == true ||
               grandparent.enumeratedAttributes?.contains(attrWithSuffix) == true
    }

    /// Outer outline color (containsSolo - orange)
    /// Checks aiStatusChildren directly since aiMode may return bundle/iterate first
    private var outerOutlineColor: Color {
        if node.aiStatusChildren > 0 {
            return .orange.opacity(0.5)
        }
        return .clear
    }

    /// Inner outline color (entry under reviewed collection - purple/cyan)
    private var innerOutlineColor: Color {
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

    /// Whether this node has any outline (for external padding)
    private var hasAnyOutline: Bool {
        outerOutlineColor != .clear || innerOutlineColor != .clear
    }

    var body: some View {
        HStack {
            ToggleChevronView(isExpanded: isExpanded)

            // Node label - use .saved for parent nodes since background color shows AI status
            if node.parent == nil {
                HeaderTextRow()
            } else {
                AlignedTextRow(
                    leadingText: node.isTitleNode && !node.name.isEmpty ? node.name : node.computedTitle,
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
                            pathPattern: nil,
                            isPerEntry: false
                        )
                        AIModeIndicator(
                            mode: .iterate,
                            pathPattern: nil,
                            isPerEntry: true
                        )
                    } else {
                        AIModeIndicator(
                            mode: displayMode,
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
            // Inner outline (entry under reviewed collection - purple/cyan)
            RoundedRectangle(cornerRadius: 6)
                .stroke(innerOutlineColor, lineWidth: 1.5)
        )
        .overlay(
            // Outer outline (containsSolo - orange), slightly larger
            RoundedRectangle(cornerRadius: 8)
                .stroke(outerOutlineColor, lineWidth: 1.5)
                .padding(-2)
        )
        .padding(.horizontal, hasAnyOutline ? 5 : 0)  // External padding for outline visibility
        .padding(.vertical, hasAnyOutline ? 3 : 0)
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
            } else if supportsCollectionModes {
                collectionModeContextMenu
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

    // MARK: - Collection Mode Context Menu

    /// Context menu for collection nodes (skills, work, etc.)
    @ViewBuilder
    private var collectionModeContextMenu: some View {
        if isScalarArrayCollection {
            scalarArrayContextMenu
        } else {
            objectArrayContextMenu
        }
    }

    /// Menu for scalar array collections (e.g., jobTitles - list of strings)
    @ViewBuilder
    private var scalarArrayContextMenu: some View {
        let isBundled = node.bundledAttributes?.contains("*") == true
        let isIterated = node.enumeratedAttributes?.contains("*") == true

        Button {
            setScalarCollectionMode(.bundle)
        } label: {
            HStack {
                Label("Bundle (1 review)", systemImage: "square.stack.3d.up.fill")
                if isBundled { Image(systemName: "checkmark") }
            }
        }

        Button {
            setScalarCollectionMode(.iterate)
        } label: {
            HStack {
                Label("Iterate (N reviews)", systemImage: "list.bullet")
                if isIterated { Image(systemName: "checkmark") }
            }
        }

        if isBundled || isIterated {
            Divider()
            Button {
                setScalarCollectionMode(.off)
            } label: {
                Label("Disable", systemImage: "xmark.circle")
            }
        }
    }

    /// Menu for object array collections (e.g., skills - entries with attributes)
    @ViewBuilder
    private var objectArrayContextMenu: some View {
        let hasAnyConfig = node.bundledAttributes?.isEmpty == false ||
                           node.enumeratedAttributes?.isEmpty == false

        Menu {
            ForEach(availableAttributes, id: \.self) { attr in
                if isNestedArray(attr) {
                    // Nested array attribute - show submenu
                    Menu(attr) {
                        nestedArraySubmenu(attr: attr, parentMode: .bundle)
                    }
                } else {
                    // Simple attribute - toggle button
                    attributeToggleButton(attr: attr, mode: .bundle)
                }
            }
        } label: {
            Label("Bundle", systemImage: "square.stack.3d.up.fill")
        }

        Menu {
            ForEach(availableAttributes, id: \.self) { attr in
                if isNestedArray(attr) {
                    // Nested array attribute - show submenu
                    Menu(attr) {
                        nestedArraySubmenu(attr: attr, parentMode: .iterate)
                    }
                } else {
                    // Simple attribute - toggle button
                    attributeToggleButton(attr: attr, mode: .iterate)
                }
            }
        } label: {
            Label("Iterate", systemImage: "list.bullet")
        }

        if hasAnyConfig {
            Divider()
            Button {
                clearAllCollectionModes()
            } label: {
                Label("Clear All", systemImage: "xmark.circle")
            }
        }
    }

    /// Toggle button for a simple attribute
    @ViewBuilder
    private func attributeToggleButton(attr: String, mode: AIReviewMode) -> some View {
        let isActive = mode == .bundle ? isAttributeBundled(attr) : isAttributeIterated(attr)

        Button {
            toggleCollectionAttribute(attr, mode: mode)
        } label: {
            HStack {
                Text(attr)
                if isActive { Image(systemName: "checkmark") }
            }
        }
    }

    /// Submenu for nested array attributes (e.g., keywords under skills)
    /// From Bundle menu: only Bundle option (no [] suffix - all items combined)
    /// From Iterate menu: Bundle (per entry) or Iterate (each item separate)
    @ViewBuilder
    private func nestedArraySubmenu(attr: String, parentMode: AIReviewMode) -> some View {
        let attrWithSuffix = attr + "[]"
        let isBundledBase = isAttributeBundled(attr)
        let isIteratedBase = isAttributeIterated(attr)
        let isIteratedEach = isAttributeIterated(attrWithSuffix)

        let isBundleActive = parentMode == .bundle ? isBundledBase : isIteratedBase
        let isIterateActive = isIteratedEach  // Only valid in iterate mode

        if parentMode == .bundle {
            // Bundle menu: only offer Bundle (all items combined across all entries)
            Button {
                Logger.info("🎯 Nested submenu BUNDLE clicked: attr='\(attr)' parentMode=\(parentMode)")
                removeCollectionAttribute(attr)
                removeCollectionAttribute(attrWithSuffix)
                toggleCollectionAttribute(attr, mode: .bundle)
            } label: {
                HStack {
                    Image(systemName: "square.stack.3d.up.fill")
                    Text("Bundle (all combined)")
                    if isBundleActive { Image(systemName: "checkmark") }
                }
            }

            if isBundleActive {
                Divider()
                Button {
                    removeCollectionAttribute(attr)
                } label: {
                    Label("Off", systemImage: "xmark.circle")
                }
            }
        } else {
            // Iterate menu: offer Bundle (per entry) or Iterate (each item separate)
            Button {
                Logger.info("🎯 Nested submenu BUNDLE clicked: attr='\(attr)' parentMode=\(parentMode)")
                removeCollectionAttribute(attr)
                removeCollectionAttribute(attrWithSuffix)
                toggleCollectionAttribute(attr, mode: .iterate)
            } label: {
                HStack {
                    Image(systemName: "square.stack.3d.up.fill")
                    Text("Bundle (per entry)")
                    if isBundleActive { Image(systemName: "checkmark") }
                }
            }

            Button {
                Logger.info("🎯 Nested submenu ITERATE clicked: attr='\(attr)' suffix='\(attrWithSuffix)' parentMode=\(parentMode)")
                removeCollectionAttribute(attr)
                removeCollectionAttribute(attrWithSuffix)
                toggleCollectionAttribute(attrWithSuffix, mode: .iterate)
            } label: {
                HStack {
                    Image(systemName: "list.bullet")
                    Text("Iterate (each item)")
                    if isIterateActive { Image(systemName: "checkmark") }
                }
            }

            if isBundleActive || isIterateActive {
                Divider()
                Button {
                    removeCollectionAttribute(attr)
                    removeCollectionAttribute(attrWithSuffix)
                } label: {
                    Label("Off", systemImage: "xmark.circle")
                }
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
        vm.refreshRevnodeCount()
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
        case .included, .containsSolo:
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

        case .included, .containsSolo:
            break  // Not valid modes to set directly - derived from parent state
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
        vm.refreshRevnodeCount()
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

    // MARK: - Collection Mode Actions

    /// Set mode for scalar array collections (uses "*" as attribute name)
    private func setScalarCollectionMode(_ mode: AIReviewMode) {
        node.bundledAttributes = nil
        node.enumeratedAttributes = nil

        switch mode {
        case .bundle:
            node.bundledAttributes = ["*"]
        case .iterate:
            node.enumeratedAttributes = ["*"]
        default:
            break
        }
        vm.refreshRevnodeCount()
    }

    /// Toggle an attribute in a collection's bundle or iterate list
    private func toggleCollectionAttribute(_ attr: String, mode: AIReviewMode) {
        Logger.info("🎯 toggleCollectionAttribute: attr='\(attr)' mode=\(mode) on node '\(node.name)'")

        // Remove from both lists first
        node.bundledAttributes?.removeAll { $0 == attr }
        node.enumeratedAttributes?.removeAll { $0 == attr }

        // Add to the appropriate list
        switch mode {
        case .bundle:
            if node.bundledAttributes == nil {
                node.bundledAttributes = []
            }
            node.bundledAttributes?.append(attr)
            Logger.info("🎯 Added '\(attr)' to bundledAttributes: \(node.bundledAttributes ?? [])")
        case .iterate:
            if node.enumeratedAttributes == nil {
                node.enumeratedAttributes = []
            }
            node.enumeratedAttributes?.append(attr)
            Logger.info("🎯 Added '\(attr)' to enumeratedAttributes: \(node.enumeratedAttributes ?? [])")
        default:
            break
        }

        // Clean up empty arrays
        if node.bundledAttributes?.isEmpty == true {
            node.bundledAttributes = nil
        }
        if node.enumeratedAttributes?.isEmpty == true {
            node.enumeratedAttributes = nil
        }
        vm.refreshRevnodeCount()
    }

    /// Remove an attribute from both bundle and iterate lists
    private func removeCollectionAttribute(_ attr: String) {
        node.bundledAttributes?.removeAll { $0 == attr }
        node.enumeratedAttributes?.removeAll { $0 == attr }

        // Clean up empty arrays
        if node.bundledAttributes?.isEmpty == true {
            node.bundledAttributes = nil
        }
        if node.enumeratedAttributes?.isEmpty == true {
            node.enumeratedAttributes = nil
        }
        vm.refreshRevnodeCount()
    }

    /// Clear all bundle/iterate configuration from this collection
    private func clearAllCollectionModes() {
        node.bundledAttributes = nil
        node.enumeratedAttributes = nil
        vm.refreshRevnodeCount()
    }
}

// MARK: - AI Review Mode

enum AIReviewMode {
    case bundle       // Purple - all together across entries
    case iterate      // Cyan - each entry separately
    case solo         // Orange - just this single node (bg + icon)
    case containsSolo // Orange - contains a solo child (outline only, no icon)
    case included     // Cyan - child of a reviewed container (uses same color as iterate)
    case off          // Gray - disabled

    var color: Color {
        switch self {
        case .bundle: return .purple
        case .iterate: return .cyan
        case .solo: return .orange
        case .containsSolo: return .orange  // Same color for outline
        case .included: return .cyan  // Same as iterate - children inherit parent's color
        case .off: return .gray
        }
    }

    var icon: String {
        switch self {
        case .bundle: return "square.on.square.squareshape.controlhandles"
        case .iterate: return "flowchart"
        case .solo: return "sparkles"  // Use sparkles for solo - consistent with SparkleButton
        case .containsSolo: return "sparkles"  // Not shown, but needed for completeness
        case .included: return "sparkles"
        case .off: return "sparkles"
        }
    }
}

// MARK: - AI Mode Indicator

struct AIModeIndicator: View {
    let mode: AIReviewMode
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
        case .containsSolo:
            text = "Contains solo item(s)"
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
