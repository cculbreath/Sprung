//
//  ResumeSectionDropdown.swift
//  Sprung
//
//  Section picker for navigating between resume sections.
//  Shows AI indicator with context menu when the selected section has AI configuration.
//

import SwiftUI

/// Information about a resume section for the dropdown
struct SectionInfo: Identifiable {
    var id: String { name }
    let name: String
    let displayLabel: String
    let node: TreeNode
}

/// Section dropdown with AI indicator and navigation buttons
struct ResumeSectionDropdown: View {
    let sections: [SectionInfo]
    @Binding var selectedSection: String

    private var currentIndex: Int {
        sections.firstIndex(where: { $0.name == selectedSection }) ?? 0
    }

    private var canGoPrevious: Bool {
        currentIndex > 0
    }

    private var canGoNext: Bool {
        currentIndex < sections.count - 1
    }

    private var selectedSectionNode: TreeNode? {
        sections.first(where: { $0.name == selectedSection })?.node
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section label
            Text("Resume Content")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            Divider()
                .padding(.horizontal, 8)

            // Navigation row
            HStack(spacing: 8) {
                // Previous section button (circled)
                Button {
                    if canGoPrevious {
                        selectedSection = sections[currentIndex - 1].name
                    }
                } label: {
                    Image(systemName: "chevron.backward.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(canGoPrevious ? .secondary : .quaternary)
                }
                .buttonStyle(.plain)
                .disabled(!canGoPrevious)
                .help("Previous section")

                // Section picker with AI indicators in menu
                Menu {
                    ForEach(sections) { section in
                        Button {
                            selectedSection = section.name
                        } label: {
                            HStack {
                                // AI status indicator (colored symbol only, not a badge)
                                if sectionHasAIConfig(section.node) {
                                    let mode = detectAIMode(for: section.node)
                                    Image(systemName: mode.icon)
                                        .foregroundColor(mode.color)
                                }

                                Text(section.displayLabel)

                                if section.name == selectedSection {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(sections.first(where: { $0.name == selectedSection })?.displayLabel ?? "Select")
                            .fontWeight(.medium)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Capsule())
                }
                .menuStyle(.borderlessButton)

                // Next section button (circled)
                Button {
                    if canGoNext {
                        selectedSection = sections[currentIndex + 1].name
                    }
                } label: {
                    Image(systemName: "chevron.forward.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(canGoNext ? .secondary : .quaternary)
                }
                .buttonStyle(.plain)
                .disabled(!canGoNext)
                .help("Next section")

                // AI indicator for the selected section (interactive with context menu)
                if let node = selectedSectionNode, sectionHasAIConfig(node) {
                    SectionAIModeButton(node: node)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    /// Check if a section node has any AI configuration
    private func sectionHasAIConfig(_ node: TreeNode) -> Bool {
        if node.bundledAttributes?.isEmpty == false ||
           node.enumeratedAttributes?.isEmpty == false {
            return true
        }
        if node.aiStatusChildren > 0 {
            return true
        }
        return false
    }

    /// Detect the primary AI mode for a section node
    private func detectAIMode(for node: TreeNode) -> AIReviewMode {
        if node.bundledAttributes?.isEmpty == false {
            return .bundle
        } else if node.enumeratedAttributes?.isEmpty == false {
            return .iterate
        } else if node.aiStatusChildren > 0 {
            return .containsSolo
        }
        return .off
    }
}

// MARK: - Section AI Mode Button

/// Interactive AI mode button for section-level configuration
/// Matches the behavior of NodeHeaderView's AI button with context menu
private struct SectionAIModeButton: View {
    let node: TreeNode
    @State private var isHovering = false

    private var hasMixedModes: Bool {
        node.bundledAttributes?.isEmpty == false && node.enumeratedAttributes?.isEmpty == false
    }

    private var aiMode: AIReviewMode {
        NodeAIReviewModeDetector.aiMode(for: node)
    }

    private var isCollectionNode: Bool {
        node.isCollectionNode
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

    /// Whether this collection contains scalar values (no nested attributes)
    private var isScalarArrayCollection: Bool {
        guard !node.orderedChildren.isEmpty else { return false }
        guard let firstChild = node.orderedChildren.first else { return false }
        return firstChild.orderedChildren.isEmpty
    }

    var body: some View {
        HStack(spacing: 4) {
            // Show both icons for mixed mode collections
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
                    mode: aiMode,
                    pathPattern: nil,
                    isPerEntry: aiMode == .iterate
                )
            }
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            if node.parent != nil && !node.orderedChildren.isEmpty {
                collectionModeContextMenu
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var collectionModeContextMenu: some View {
        if isScalarArrayCollection {
            scalarCollectionMenu
        } else {
            objectCollectionMenu
        }
    }

    @ViewBuilder
    private var scalarCollectionMenu: some View {
        let containerName = node.name.isEmpty ? node.displayLabel : node.name

        Text("AI Review Mode for \(containerName)")
            .font(.headline)

        Divider()

        Button {
            node.bundledAttributes = ["*"]
            node.enumeratedAttributes = nil
        } label: {
            HStack {
                Image(systemName: "square.on.square.squareshape.controlhandles")
                    .foregroundColor(.purple)
                Text("Bundle All")
                Text("– 1 review for all items")
                    .foregroundColor(.secondary)
                if node.bundledAttributes?.contains("*") == true {
                    Image(systemName: "checkmark")
                }
            }
        }

        Button {
            node.enumeratedAttributes = ["*"]
            node.bundledAttributes = nil
        } label: {
            HStack {
                Image(systemName: "flowchart")
                    .foregroundColor(.cyan)
                Text("Iterate")
                Text("– N reviews (one per item)")
                    .foregroundColor(.secondary)
                if node.enumeratedAttributes?.contains("*") == true {
                    Image(systemName: "checkmark")
                }
            }
        }

        Button {
            node.bundledAttributes = nil
            node.enumeratedAttributes = nil
        } label: {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.gray)
                Text("Off")
                if node.bundledAttributes == nil && node.enumeratedAttributes == nil {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    /// Menu for object array collections (e.g., skills - entries with attributes)
    /// Structure: Bundle/Iterate → Attributes → (for collections) Bundle/Iterate
    @ViewBuilder
    private var objectCollectionMenu: some View {
        let hasAnyConfig = node.bundledAttributes?.isEmpty == false ||
                           node.enumeratedAttributes?.isEmpty == false

        // Top-level Bundle menu: skills.*.attr pattern (1 rev node for all)
        Menu {
            ForEach(availableAttributes, id: \.self) { attr in
                if isNestedArray(attr) {
                    // Nested array: only Bundle option (all items combined across all entries)
                    bundleNestedArrayButton(attr: attr)
                } else {
                    // Scalar attribute: toggle for bundle mode
                    bundleScalarButton(attr: attr)
                }
            }
        } label: {
            HStack {
                Image(systemName: "square.on.square.squareshape.controlhandles")
                    .foregroundColor(.purple)
                Text("Bundle")
                Text("– 1 review")
                    .foregroundColor(.secondary)
            }
        }

        // Top-level Iterate menu: skills[].attr pattern (N rev nodes, one per entry)
        Menu {
            ForEach(availableAttributes, id: \.self) { attr in
                if isNestedArray(attr) {
                    // Nested array: submenu with Bundle (per entry) or Iterate (each item)
                    iterateNestedArraySubmenu(attr: attr)
                } else {
                    // Scalar attribute: toggle for iterate mode
                    iterateScalarButton(attr: attr)
                }
            }
        } label: {
            HStack {
                Image(systemName: "flowchart")
                    .foregroundColor(.cyan)
                Text("Iterate")
                Text("– N reviews")
                    .foregroundColor(.secondary)
            }
        }

        if hasAnyConfig {
            Divider()
            Button(role: .destructive) {
                node.bundledAttributes = nil
                node.enumeratedAttributes = nil
            } label: {
                Label("Clear All AI Settings", systemImage: "xmark.circle")
            }
        }
    }

    // MARK: - Bundle Menu Items

    /// Scalar attribute under Bundle menu (skills.*.name → 1 rev node for all names)
    @ViewBuilder
    private func bundleScalarButton(attr: String) -> some View {
        let isActive = isAttributeBundled(attr)

        Button {
            toggleBundleAttribute(attr)
        } label: {
            HStack {
                Text(attr)
                if isActive { Image(systemName: "checkmark") }
            }
        }
    }

    /// Nested array under Bundle menu (skills.*.keywords → 1 rev node for all keywords)
    @ViewBuilder
    private func bundleNestedArrayButton(attr: String) -> some View {
        let isActive = isAttributeBundled(attr)

        Button {
            toggleBundleAttribute(attr)
        } label: {
            HStack {
                Text(attr)
                if isActive { Image(systemName: "checkmark") }
            }
        }
    }

    // MARK: - Iterate Menu Items

    /// Scalar attribute under Iterate menu (skills[].name → N rev nodes, one per skill)
    @ViewBuilder
    private func iterateScalarButton(attr: String) -> some View {
        let isActive = isAttributeIterated(attr)

        Button {
            toggleIterateAttribute(attr)
        } label: {
            HStack {
                Text(attr)
                if isActive { Image(systemName: "checkmark") }
            }
        }
    }

    /// Nested array submenu under Iterate menu
    /// skills[].keywords → N rev nodes (each skill's keywords bundled together)
    /// skills[].keywords[] → N×M rev nodes (each skill, each keyword separate)
    @ViewBuilder
    private func iterateNestedArraySubmenu(attr: String) -> some View {
        let attrWithSuffix = attr + "[]"
        let isBundledPerEntry = isAttributeIterated(attr) && !isAttributeIterated(attrWithSuffix)
        let isIteratedEach = isAttributeIterated(attrWithSuffix)

        Menu {
            // Bundle: skills[].keywords (N rev nodes, each skill's keywords together)
            Button {
                removeAttributeFromBoth(attr)
                addToEnumeratedAttributes(attr)
            } label: {
                HStack {
                    Image(systemName: "square.on.square.squareshape.controlhandles")
                        .foregroundColor(.purple)
                    Text("Bundle")
                    Text("– N reviews")
                        .foregroundColor(.secondary)
                    if isBundledPerEntry { Image(systemName: "checkmark") }
                }
            }

            // Iterate: skills[].keywords[] (N×M rev nodes, each keyword separate)
            Button {
                removeAttributeFromBoth(attr)
                addToEnumeratedAttributes(attrWithSuffix)
            } label: {
                HStack {
                    Image(systemName: "flowchart")
                        .foregroundColor(.cyan)
                    Text("Iterate")
                    Text("– N×M reviews")
                        .foregroundColor(.secondary)
                    if isIteratedEach { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                if isBundledPerEntry {
                    Image(systemName: "square.on.square.squareshape.controlhandles")
                        .foregroundColor(.purple)
                } else if isIteratedEach {
                    Image(systemName: "flowchart")
                        .foregroundColor(.cyan)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                }
                Text(attr)
            }
        }
    }

    // MARK: - Attribute Mode Helpers

    private func toggleBundleAttribute(_ attr: String) {
        if isAttributeBundled(attr) {
            // Remove from bundled
            removeFromBundledAttributes(attr)
        } else {
            // Remove from enumerated (if present) and add to bundled
            removeFromEnumeratedAttributes(attr)
            removeFromEnumeratedAttributes(attr + "[]")
            addToBundledAttributes(attr)
        }
    }

    private func toggleIterateAttribute(_ attr: String) {
        if isAttributeIterated(attr) {
            // Remove from enumerated
            removeFromEnumeratedAttributes(attr)
        } else {
            // Remove from bundled (if present) and add to enumerated
            removeFromBundledAttributes(attr)
            addToEnumeratedAttributes(attr)
        }
    }

    private func removeAttributeFromBoth(_ attr: String) {
        removeFromBundledAttributes(attr)
        removeFromBundledAttributes(attr + "[]")
        removeFromEnumeratedAttributes(attr)
        removeFromEnumeratedAttributes(attr + "[]")
    }

    private func addToBundledAttributes(_ attr: String) {
        var bundled = node.bundledAttributes ?? []
        if !bundled.contains(attr) {
            bundled.append(attr)
            node.bundledAttributes = bundled
        }
    }

    private func removeFromBundledAttributes(_ attr: String) {
        guard var bundled = node.bundledAttributes else { return }
        bundled.removeAll { $0 == attr }
        node.bundledAttributes = bundled.isEmpty ? nil : bundled
    }

    private func addToEnumeratedAttributes(_ attr: String) {
        var enumerated = node.enumeratedAttributes ?? []
        if !enumerated.contains(attr) {
            enumerated.append(attr)
            node.enumeratedAttributes = enumerated
        }
    }

    private func removeFromEnumeratedAttributes(_ attr: String) {
        guard var enumerated = node.enumeratedAttributes else { return }
        enumerated.removeAll { $0 == attr }
        node.enumeratedAttributes = enumerated.isEmpty ? nil : enumerated
    }
}
