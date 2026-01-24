//
//  ResumeSectionDropdown.swift
//  Sprung
//
//  Section picker for navigating between resume sections.
//  Shows AI configuration button (sparkle) for sections that support AI review.
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
                // Previous section button
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

                // Section picker
                Menu {
                    ForEach(sections) { section in
                        Button {
                            selectedSection = section.name
                        } label: {
                            HStack {
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

                // Next section button
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

                // AI configuration button (always show for collections)
                if let node = selectedSectionNode, sectionSupportsAIConfig(node) {
                    SectionAIModeMenu(node: node)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func sectionHasAIConfig(_ node: TreeNode) -> Bool {
        node.bundledAttributes?.isEmpty == false ||
        node.enumeratedAttributes?.isEmpty == false ||
        node.aiStatusChildren > 0
    }

    private func sectionSupportsAIConfig(_ node: TreeNode) -> Bool {
        node.parent != nil && !node.orderedChildren.isEmpty
    }

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

// MARK: - Section AI Mode Menu

/// Left-click menu for configuring AI review modes at section level
private struct SectionAIModeMenu: View {
    let node: TreeNode
    @State private var isHovering = false

    private var hasAIConfig: Bool {
        node.bundledAttributes?.isEmpty == false || node.enumeratedAttributes?.isEmpty == false
    }

    private var hasMixedModes: Bool {
        node.bundledAttributes?.isEmpty == false && node.enumeratedAttributes?.isEmpty == false
    }

    private var aiMode: AIReviewMode {
        NodeAIReviewModeDetector.aiMode(for: node)
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

    private var isScalarArrayCollection: Bool {
        guard !node.orderedChildren.isEmpty,
              let firstChild = node.orderedChildren.first else { return false }
        return firstChild.orderedChildren.isEmpty
    }

    /// Icon based on current configuration
    private var displayIcon: String {
        if !hasAIConfig {
            return "sparkles"
        } else if hasMixedModes {
            return "sparkles"
        } else if aiMode == .bundle {
            return "square.on.square.squareshape.controlhandles"
        } else if aiMode == .iterate {
            return "flowchart"
        }
        return "sparkles"
    }

    /// Color based on current configuration
    private var displayColor: Color {
        if !hasAIConfig {
            return .secondary
        } else if hasMixedModes {
            return .orange
        } else if aiMode == .bundle {
            return .purple
        } else if aiMode == .iterate {
            return .cyan
        }
        return .secondary
    }

    var body: some View {
        Menu {
            if isScalarArrayCollection {
                scalarCollectionMenu
            } else {
                objectCollectionMenu
            }
        } label: {
            Image(systemName: displayIcon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(displayColor)
                .padding(6)
                .background(
                    Circle()
                        .fill(displayColor.opacity(hasAIConfig ? 0.15 : (isHovering ? 0.1 : 0)))
                )
        }
        .menuStyle(.borderlessButton)
        .onHover { isHovering = $0 }
        .help(hasAIConfig ? "Configure AI review" : "Enable AI review")
    }

    // MARK: - Scalar Collection Menu

    @ViewBuilder
    private var scalarCollectionMenu: some View {
        Text("AI Review: \(node.displayLabel)")

        Divider()

        Button {
            node.bundledAttributes = ["*"]
            node.enumeratedAttributes = nil
        } label: {
            HStack {
                Image(systemName: "square.on.square.squareshape.controlhandles")
                    .foregroundColor(.purple)
                Text("Bundle All – 1 review")
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
                Text("Iterate – N reviews")
                if node.enumeratedAttributes?.contains("*") == true {
                    Image(systemName: "checkmark")
                }
            }
        }

        if hasAIConfig {
            Divider()

            Button(role: .destructive) {
                node.bundledAttributes = nil
                node.enumeratedAttributes = nil
            } label: {
                Label("Disable AI Review", systemImage: "xmark.circle")
            }
        }
    }

    // MARK: - Object Collection Menu

    @ViewBuilder
    private var objectCollectionMenu: some View {
        Text("AI Review: \(node.displayLabel)")

        Divider()

        // Bundle menu
        Menu {
            ForEach(availableAttributes, id: \.self) { attr in
                bundleAttributeButton(attr: attr)
            }
        } label: {
            HStack {
                Image(systemName: "square.on.square.squareshape.controlhandles")
                    .foregroundColor(.purple)
                Text("Bundle – 1 review")
            }
        }

        // Iterate menu
        Menu {
            ForEach(availableAttributes, id: \.self) { attr in
                if isNestedArray(attr) {
                    iterateNestedArraySubmenu(attr: attr)
                } else {
                    iterateScalarButton(attr: attr)
                }
            }
        } label: {
            HStack {
                Image(systemName: "flowchart")
                    .foregroundColor(.cyan)
                Text("Iterate – N reviews")
            }
        }

        if hasAIConfig {
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

    @ViewBuilder
    private func bundleAttributeButton(attr: String) -> some View {
        let isActive = isAttributeBundled(attr)

        Button {
            if isActive {
                removeFromBundledAttributes(attr)
            } else {
                removeFromEnumeratedAttributes(attr)
                removeFromEnumeratedAttributes(attr + "[]")
                addToBundledAttributes(attr)
            }
        } label: {
            HStack {
                Text(attr)
                if isActive { Image(systemName: "checkmark") }
            }
        }
    }

    // MARK: - Iterate Menu Items

    @ViewBuilder
    private func iterateScalarButton(attr: String) -> some View {
        let isActive = isAttributeIterated(attr)

        Button {
            if isActive {
                removeFromEnumeratedAttributes(attr)
            } else {
                removeFromBundledAttributes(attr)
                addToEnumeratedAttributes(attr)
            }
        } label: {
            HStack {
                Text(attr)
                if isActive { Image(systemName: "checkmark") }
            }
        }
    }

    @ViewBuilder
    private func iterateNestedArraySubmenu(attr: String) -> some View {
        let attrWithSuffix = attr + "[]"
        let isBundledPerEntry = isAttributeIterated(attr) && !isAttributeIterated(attrWithSuffix)
        let isIteratedEach = isAttributeIterated(attrWithSuffix)

        Menu {
            Button {
                removeAttributeFromBoth(attr)
                addToEnumeratedAttributes(attr)
            } label: {
                HStack {
                    Image(systemName: "square.on.square.squareshape.controlhandles")
                        .foregroundColor(.purple)
                    Text("Bundle – N reviews")
                    if isBundledPerEntry { Image(systemName: "checkmark") }
                }
            }

            Button {
                removeAttributeFromBoth(attr)
                addToEnumeratedAttributes(attrWithSuffix)
            } label: {
                HStack {
                    Image(systemName: "flowchart")
                        .foregroundColor(.cyan)
                    Text("Iterate – N×M reviews")
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

    // MARK: - Helpers

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
