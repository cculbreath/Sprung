//
//  NodeHeaderView.swift
//  Sprung
//
//
import SwiftUI

/// Header row for a parent node. Displays node label, AI status icon, and controls.
///
/// AI Review Modes (for collection nodes like skills, work):
/// - **Bundle** (purple): All entries combined into 1 RevNode for holistic review
/// - **Iterate** (indigo): Each entry becomes separate RevNode for individual review
/// - **Solo** (teal): Just this single node
///
/// Click icon to toggle AI modes. Right-click for detailed options.
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
    private var isAttributeOfCollectionEntry: Bool {
        guard let grandparent = grandparentNode else { return false }
        let attr = attributeName
        if grandparent.bundledAttributes?.contains(attr) == true { return true }
        if grandparent.enumeratedAttributes?.contains(attr) == true { return true }
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
        let attrWithSuffix = attr + "[]"
        let isArrayAttribute = !node.orderedChildren.isEmpty

        if isArrayAttribute {
            if grandparent.bundledAttributes?.contains(attrWithSuffix) == true ||
               grandparent.enumeratedAttributes?.contains(attrWithSuffix) == true {
                return .iterate
            }
            if grandparent.bundledAttributes?.contains(attr) == true ||
               grandparent.enumeratedAttributes?.contains(attr) == true {
                return .bundle
            }
        } else {
            if grandparent.enumeratedAttributes?.contains(attr) == true {
                return .iterate
            }
            if grandparent.bundledAttributes?.contains(attr) == true {
                return .bundle
            }
        }

        if node.status == .aiToReplace {
            return .solo
        }
        return .off
    }

    /// Whether clicking the AI mode indicator should toggle mode
    private var isAIModeInteractive: Bool {
        isAttributeOfCollectionEntry && !isChildOfReviewedContainer
    }

    /// Whether this node is a child of a container being reviewed
    private var isChildOfReviewedContainer: Bool {
        guard let parent = node.parent,
              let grandparent = parent.parent,
              let greatGrandparent = grandparent.parent else { return false }

        let parentName = parent.name.isEmpty ? parent.displayLabel : parent.name
        if greatGrandparent.bundledAttributes?.contains(parentName) == true { return true }
        if greatGrandparent.enumeratedAttributes?.contains(parentName) == true { return true }
        return false
    }

    /// Whether this node supports collection modes (bundle/iterate)
    private var supportsCollectionModes: Bool {
        node.parent != nil && !node.orderedChildren.isEmpty
    }

    // MARK: - Collection Context Menu Helpers

    private var isScalarArrayCollection: Bool {
        guard !node.orderedChildren.isEmpty else { return false }
        guard let firstChild = node.orderedChildren.first else { return false }
        return firstChild.orderedChildren.isEmpty
    }

    private var availableAttributes: [String] {
        guard let firstChild = node.orderedChildren.first else { return [] }
        return firstChild.orderedChildren.compactMap {
            let name = $0.name.isEmpty ? $0.displayLabel : $0.name
            return name.isEmpty ? nil : name
        }
    }

    private func isNestedArray(_ attrName: String) -> Bool {
        guard let firstChild = node.orderedChildren.first,
              let attr = firstChild.orderedChildren.first(where: {
                  ($0.name.isEmpty ? $0.displayLabel : $0.name) == attrName
              }) else { return false }
        return !attr.orderedChildren.isEmpty
    }

    private func isAttributeBundled(_ attr: String) -> Bool {
        node.bundledAttributes?.contains(attr) == true
    }

    private func isAttributeIterated(_ attr: String) -> Bool {
        node.enumeratedAttributes?.contains(attr) == true
    }

    // MARK: - Icon Mode Resolution

    /// Full icon resolution for this node (may be single or dual)
    private var iconResolution: AIIconResolution {
        AIIconModeResolver.resolve(for: node)
    }

    var body: some View {
        HStack {
            ToggleChevronView(isExpanded: isExpanded)

            // Node label
            if node.parent == nil {
                HeaderTextRow()
            } else {
                AlignedTextRow(
                    leadingText: node.isTitleNode && !node.name.isEmpty ? node.name : node.computedTitle,
                    trailingText: nil
                )
            }

            Spacer()

            // AI status icon(s) - show for all non-root nodes
            if node.parent != nil {
                Button { handleIconTap() } label: {
                    ResolvedAIIcon(resolution: iconResolution)
                }
                .buttonStyle(.plain)
            }

            // Expanded controls
            if vm.isExpanded(node) && node.parent != nil && !node.orderedChildren.isEmpty {
                expandedControls
            }
        }
        .padding(.leading, CGFloat(max(0, node.depth - depthOffset) * 20) + 10)
        .padding(.trailing, 10)
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
            } else if supportsCollectionModes {
                collectionModeContextMenu
            } else if node.parent != nil {
                aiModeContextMenu
            }
        }
    }

    // MARK: - Icon Tap Handler

    private func handleIconTap() {
        if isAIModeInteractive {
            toggleAttributeMode()
        } else if supportsCollectionModes {
            // Collection nodes - the menu handles this via context menu
            // Could open a menu programmatically here if desired
        } else if node.parent != nil {
            // Simple toggle for leaf/solo nodes
            toggleAIStatus()
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var attributeModeContextMenu: some View {
        Text("AI Review: \(attributeName)").font(.headline)
        Divider()

        Button {
            setAttributeMode(.bundle)
        } label: {
            HStack {
                Label("Review once (all combined)", systemImage: "circle.hexagongrid.circle")
                if attributeMode == .bundle { Image(systemName: "checkmark") }
            }
        }

        Button {
            setAttributeMode(.iterate)
        } label: {
            HStack {
                Label("Review per entry (N reviews)", systemImage: "film.stack")
                if attributeMode == .iterate { Image(systemName: "checkmark") }
            }
        }

        Button {
            setAttributeMode(.solo)
        } label: {
            HStack {
                Label("Just this entry", systemImage: "target")
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

    @ViewBuilder
    private var collectionModeContextMenu: some View {
        if isScalarArrayCollection {
            scalarArrayContextMenu
        } else {
            objectArrayContextMenu
        }
    }

    @ViewBuilder
    private var scalarArrayContextMenu: some View {
        let isBundled = node.bundledAttributes?.contains("*") == true
        let isIterated = node.enumeratedAttributes?.contains("*") == true

        Button {
            setScalarCollectionMode(.bundle)
        } label: {
            HStack {
                Label("Bundle (1 review)", systemImage: "circle.hexagongrid.circle")
                if isBundled { Image(systemName: "checkmark") }
            }
        }

        Button {
            setScalarCollectionMode(.iterate)
        } label: {
            HStack {
                Label("Iterate (N reviews)", systemImage: "film.stack")
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

    @ViewBuilder
    private var objectArrayContextMenu: some View {
        let hasAnyConfig = node.bundledAttributes?.isEmpty == false ||
                           node.enumeratedAttributes?.isEmpty == false

        Menu {
            ForEach(availableAttributes, id: \.self) { attr in
                if isNestedArray(attr) {
                    Menu(attr) {
                        nestedArraySubmenu(attr: attr, parentMode: .bundle)
                    }
                } else {
                    attributeToggleButton(attr: attr, mode: .bundle)
                }
            }
        } label: {
            Label("Bundle", systemImage: "circle.hexagongrid.circle")
        }

        Menu {
            ForEach(availableAttributes, id: \.self) { attr in
                if isNestedArray(attr) {
                    Menu(attr) {
                        nestedArraySubmenu(attr: attr, parentMode: .iterate)
                    }
                } else {
                    attributeToggleButton(attr: attr, mode: .iterate)
                }
            }
        } label: {
            Label("Iterate", systemImage: "film.stack")
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

    @ViewBuilder
    private func nestedArraySubmenu(attr: String, parentMode: AIReviewMode) -> some View {
        let attrWithSuffix = attr + "[]"
        let isBundledBase = isAttributeBundled(attr)
        let isIteratedBase = isAttributeIterated(attr)
        let isIteratedEach = isAttributeIterated(attrWithSuffix)

        let isBundleActive = parentMode == .bundle ? isBundledBase : isIteratedBase
        let isIterateActive = isIteratedEach

        if parentMode == .bundle {
            Button {
                removeCollectionAttribute(attr)
                removeCollectionAttribute(attrWithSuffix)
                toggleCollectionAttribute(attr, mode: .bundle)
            } label: {
                HStack {
                    Image(systemName: "circle.hexagongrid.circle")
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
            Button {
                removeCollectionAttribute(attr)
                removeCollectionAttribute(attrWithSuffix)
                toggleCollectionAttribute(attr, mode: .iterate)
            } label: {
                HStack {
                    Image(systemName: "circle.hexagongrid.circle")
                    Text("Bundle (per entry)")
                    if isBundleActive { Image(systemName: "checkmark") }
                }
            }

            Button {
                removeCollectionAttribute(attr)
                removeCollectionAttribute(attrWithSuffix)
                toggleCollectionAttribute(attrWithSuffix, mode: .iterate)
            } label: {
                HStack {
                    Image(systemName: "film.stack")
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
            break
        }
    }

    private func setAttributeMode(_ mode: AIReviewMode) {
        guard let collection = collectionNode else { return }
        let attr = attributeName

        collection.bundledAttributes?.removeAll { $0 == attr }
        collection.enumeratedAttributes?.removeAll { $0 == attr }

        switch mode {
        case .bundle:
            if collection.bundledAttributes == nil {
                collection.bundledAttributes = []
            }
            collection.bundledAttributes?.append(attr)
            clearSoloStatusForAttribute(attr, in: collection)

        case .iterate:
            if collection.enumeratedAttributes == nil {
                collection.enumeratedAttributes = []
            }
            collection.enumeratedAttributes?.append(attr)
            clearSoloStatusForAttribute(attr, in: collection)

        case .solo:
            node.status = .aiToReplace

        case .off:
            node.status = .saved
            clearSoloStatusForAttribute(attr, in: collection)

        case .included, .containsSolo:
            break
        }

        if collection.bundledAttributes?.isEmpty == true {
            collection.bundledAttributes = nil
        }
        if collection.enumeratedAttributes?.isEmpty == true {
            collection.enumeratedAttributes = nil
        }

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

    private func toggleCollectionAttribute(_ attr: String, mode: AIReviewMode) {
        node.bundledAttributes?.removeAll { $0 == attr }
        node.enumeratedAttributes?.removeAll { $0 == attr }

        switch mode {
        case .bundle:
            if node.bundledAttributes == nil {
                node.bundledAttributes = []
            }
            node.bundledAttributes?.append(attr)
        case .iterate:
            if node.enumeratedAttributes == nil {
                node.enumeratedAttributes = []
            }
            node.enumeratedAttributes?.append(attr)
        default:
            break
        }

        if node.bundledAttributes?.isEmpty == true {
            node.bundledAttributes = nil
        }
        if node.enumeratedAttributes?.isEmpty == true {
            node.enumeratedAttributes = nil
        }
        vm.refreshRevnodeCount()
    }

    private func removeCollectionAttribute(_ attr: String) {
        node.bundledAttributes?.removeAll { $0 == attr }
        node.enumeratedAttributes?.removeAll { $0 == attr }

        if node.bundledAttributes?.isEmpty == true {
            node.bundledAttributes = nil
        }
        if node.enumeratedAttributes?.isEmpty == true {
            node.enumeratedAttributes = nil
        }
        vm.refreshRevnodeCount()
    }

    private func clearAllCollectionModes() {
        node.bundledAttributes = nil
        node.enumeratedAttributes = nil
        vm.refreshRevnodeCount()
    }
}

// MARK: - AI Review Mode

enum AIReviewMode {
    case bundle       // Purple - all together across entries
    case iterate      // Indigo - each entry separately
    case solo         // Teal - just this single node
    case containsSolo // Contains a solo child (outline only, no icon)
    case included     // Child of a reviewed container
    case off          // Gray - disabled

    var color: Color {
        switch self {
        case .bundle: return .purple
        case .iterate: return .indigo
        case .solo: return .teal
        case .containsSolo: return .teal
        case .included: return .indigo
        case .off: return .gray
        }
    }

    var icon: String {
        switch self {
        case .bundle: return "circle.hexagongrid.circle"
        case .iterate: return "film.stack"
        case .solo: return "target"
        case .containsSolo: return "target"
        case .included: return "target"
        case .off: return "sparkles"
        }
    }
}
