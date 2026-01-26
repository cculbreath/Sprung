//
//  ResumeSectionDropdown.swift
//  Sprung
//
//  Section picker for navigating between resume sections.
//  Shows AI configuration button (icon) for sections that support AI review.
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
            ZStack {
                // Centered: nav buttons + picker
                HStack(spacing: 8) {
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

                    SectionPickerButton(
                        sections: sections,
                        selectedSection: $selectedSection
                    )

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
                }

                // Left-aligned: section-level AI icon
                HStack {
                    if let node = selectedSectionNode, sectionSupportsAIConfig(node) {
                        SectionAIModeMenu(node: node)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func sectionSupportsAIConfig(_ node: TreeNode) -> Bool {
        node.parent != nil && !node.orderedChildren.isEmpty
    }
}

// MARK: - Section AI Mode Menu

/// Left-click menu for configuring AI review modes at section level
private struct SectionAIModeMenu: View {
    let node: TreeNode

    private var hasAIConfig: Bool {
        node.bundledAttributes?.isEmpty == false ||
        node.enumeratedAttributes?.isEmpty == false ||
        node.hasAttributeReviewModes ||
        node.aiStatusChildren > 0
    }

    /// Full icon resolution for this section node (may be dual for mixed modes)
    private var iconResolution: AIIconResolution {
        AIIconModeResolver.resolve(for: node)
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

    var body: some View {
        Menu {
            if isScalarArrayCollection {
                scalarCollectionMenu
            } else {
                objectCollectionMenu
            }
        } label: {
            ResolvedAIIcon(resolution: iconResolution)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
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
                Image(systemName: "circle.hexagongrid.circle")
                    .foregroundColor(.purple)
                Text("Bundle All - 1 review")
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
                Image(systemName: "film.stack")
                    .foregroundColor(.indigo)
                Text("Iterate - N reviews")
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
                Image(systemName: "circle.hexagongrid.circle")
                    .foregroundColor(.purple)
                Text("Bundle - 1 review")
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
                Image(systemName: "film.stack")
                    .foregroundColor(.indigo)
                Text("Iterate - N reviews")
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
                    Image(systemName: "circle.hexagongrid.circle")
                        .foregroundColor(.purple)
                    Text("Bundle - N reviews")
                    if isBundledPerEntry { Image(systemName: "checkmark") }
                }
            }

            Button {
                removeAttributeFromBoth(attr)
                addToEnumeratedAttributes(attrWithSuffix)
            } label: {
                HStack {
                    Image(systemName: "film.stack")
                        .foregroundColor(.indigo)
                    Text("Iterate - N×M reviews")
                    if isIteratedEach { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                if isBundledPerEntry {
                    Image(systemName: "circle.hexagongrid.circle")
                        .foregroundColor(.purple)
                } else if isIteratedEach {
                    Image(systemName: "film.stack")
                        .foregroundColor(.indigo)
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

// MARK: - Section Picker Button

/// Custom section picker using popover for full layout control (trailing icons)
private struct SectionPickerButton: View {
    let sections: [SectionInfo]
    @Binding var selectedSection: String
    @State private var showingPicker = false

    private var selectedLabel: String {
        sections.first(where: { $0.name == selectedSection })?.displayLabel ?? "Select"
    }

    /// The widest label text among all sections
    private var widestLabel: String {
        sections.max(by: { $0.displayLabel.count < $1.displayLabel.count })?.displayLabel ?? "Select"
    }

    var body: some View {
        Button {
            showingPicker.toggle()
        } label: {
            ZStack {
                // Invisible widest label to set fixed width
                Text(widestLabel)
                    .fontWeight(.medium)
                    .opacity(0)

                // Visible selected label
                Text(selectedLabel)
                    .fontWeight(.medium)
            }
            .overlay(alignment: .trailing) {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .offset(x: 16)
            }
            .padding(.horizontal, 12)
            .padding(.trailing, 16) // room for chevron
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.05))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sections) { section in
                    Button {
                        selectedSection = section.name
                        showingPicker = false
                    } label: {
                        HStack(spacing: 8) {
                            // Checkmark for selected
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(section.name == selectedSection ? .primary : .clear)
                                .frame(width: 14)

                            Text(section.displayLabel)
                                .font(.system(size: 13))

                            Spacer(minLength: 20)

                            // AI mode icon(s) (trailing)
                            if sectionHasAIConfig(section.node) {
                                let resolution = AIIconModeResolver.resolve(for: section.node)
                                HStack(spacing: 3) {
                                    sectionIconImage(resolution.primary)
                                    if let secondary = resolution.secondary {
                                        sectionIconImage(secondary)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .background(section.name == selectedSection ? Color.accentColor.opacity(0.1) : Color.clear)
                    }
                    .buttonStyle(.plain)

                    if section.id != sections.last?.id {
                        Divider()
                            .padding(.horizontal, 8)
                    }
                }
            }
            .padding(.vertical, 6)
            .frame(minWidth: 180)
        }
    }

    private func sectionHasAIConfig(_ node: TreeNode) -> Bool {
        node.bundledAttributes?.isEmpty == false ||
        node.enumeratedAttributes?.isEmpty == false ||
        node.aiStatusChildren > 0
    }

    private func sectionIconImage(_ mode: AIIconMode) -> some View {
        AIIconImage(mode: mode, size: 11)
    }
}
