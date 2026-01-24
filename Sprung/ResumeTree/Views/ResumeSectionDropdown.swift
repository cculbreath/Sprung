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

    @ViewBuilder
    private var objectCollectionMenu: some View {
        let containerName = node.name.isEmpty ? node.displayLabel : node.name

        Text("Configure AI Review for \(containerName)")
            .font(.headline)

        Divider()

        ForEach(availableAttributes, id: \.self) { attr in
            attributeSubmenu(attr)
        }

        Divider()

        Button(role: .destructive) {
            node.bundledAttributes = nil
            node.enumeratedAttributes = nil
        } label: {
            Label("Clear All AI Settings", systemImage: "xmark.circle")
        }
    }

    @ViewBuilder
    private func attributeSubmenu(_ attr: String) -> some View {
        let isArray = isNestedArray(attr)

        Menu {
            Button {
                toggleAttributeMode(attr, toMode: .bundle, isArray: isArray)
            } label: {
                HStack {
                    Image(systemName: "square.on.square.squareshape.controlhandles")
                        .foregroundColor(.purple)
                    if isArray {
                        Text("Bundle Together")
                    } else {
                        Text("Bundle")
                    }
                    if isAttributeBundled(attr) {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Button {
                toggleAttributeMode(attr, toMode: .iterate, isArray: isArray)
            } label: {
                HStack {
                    Image(systemName: "flowchart")
                        .foregroundColor(.cyan)
                    if isArray {
                        Text("Each Separate")
                    } else {
                        Text("Iterate")
                    }
                    if isAttributeIterated(attr) || isAttributeIterated(attr + "[]") {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Button {
                removeAttributeFromBoth(attr, isArray: isArray)
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.gray)
                    Text("Off")
                    if !isAttributeBundled(attr) && !isAttributeIterated(attr) &&
                       !isAttributeBundled(attr + "[]") && !isAttributeIterated(attr + "[]") {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            HStack {
                if isAttributeBundled(attr) || isAttributeBundled(attr + "[]") {
                    Image(systemName: "square.on.square.squareshape.controlhandles")
                        .foregroundColor(.purple)
                } else if isAttributeIterated(attr) || isAttributeIterated(attr + "[]") {
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

    private func toggleAttributeMode(_ attr: String, toMode: AIReviewMode, isArray: Bool) {
        let attrKey = isArray && toMode == .iterate ? attr + "[]" : attr

        removeAttributeFromBoth(attr, isArray: isArray)

        if toMode == .bundle {
            var bundled = node.bundledAttributes ?? []
            bundled.append(attrKey)
            node.bundledAttributes = bundled
        } else if toMode == .iterate {
            var enumerated = node.enumeratedAttributes ?? []
            enumerated.append(attrKey)
            node.enumeratedAttributes = enumerated
        }
    }

    private func removeAttributeFromBoth(_ attr: String, isArray: Bool) {
        if var bundled = node.bundledAttributes {
            bundled.removeAll { $0 == attr || $0 == attr + "[]" }
            node.bundledAttributes = bundled.isEmpty ? nil : bundled
        }
        if var enumerated = node.enumeratedAttributes {
            enumerated.removeAll { $0 == attr || $0 == attr + "[]" }
            node.enumeratedAttributes = enumerated.isEmpty ? nil : enumerated
        }
    }
}
