//
//  ResumeSectionDropdown.swift
//  Sprung
//
//  Section picker for navigating between resume sections.
//  Shows AI configuration button (icon) for sections that support AI review.
//

import AppKit
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

/// Left-click menu using native NSMenu for proper fly-out submenus
private struct SectionAIModeMenu: View {
    let node: TreeNode

    private var hasAIConfig: Bool {
        node.bundledAttributes?.isEmpty == false ||
        node.enumeratedAttributes?.isEmpty == false ||
        node.hasAttributeReviewModes ||
        node.aiStatusChildren > 0
    }

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

    private var hasBundleAttrs: Bool {
        node.bundledAttributes?.isEmpty == false
    }

    private var hasIterateAttrs: Bool {
        node.enumeratedAttributes?.isEmpty == false
    }

    private var isBundleActive: Bool {
        node.bundledAttributes?.contains("*") == true
    }

    private var isIterateActive: Bool {
        node.enumeratedAttributes?.contains("*") == true
    }

    private enum CheckedMode {
        case bundle, iterate
    }

    var body: some View {
        if iconResolution.isDual {
            HStack(spacing: 2) {
                AIIconNativeMenuButton(mode: iconResolution.primary, showDropIndicator: true) {
                    self.buildConfiguredMenu(checkedMode: .bundle)
                }
                if let secondary = iconResolution.secondary {
                    AIIconNativeMenuButton(mode: secondary, showDropIndicator: true) {
                        self.buildConfiguredMenu(checkedMode: .iterate)
                    }
                }
            }
        } else {
            AIIconNativeMenuButton(mode: iconResolution.primary, showDropIndicator: true) {
                if self.isScalarArrayCollection {
                    return self.buildScalarMenu()
                } else if self.hasAIConfig {
                    let mode: CheckedMode = self.hasBundleAttrs ? .bundle : .iterate
                    return self.buildConfiguredMenu(checkedMode: mode)
                } else {
                    return self.buildUnsetMenu()
                }
            }
        }
    }

    // MARK: - NSMenu Builders

    private func buildScalarMenu() -> NSMenu {
        let menu = NSMenu()

        if hasAIConfig {
            menu.addItem(ActionMenuItem("Bundle All - 1 review", checked: isBundleActive) {
                node.bundledAttributes = ["*"]
                node.enumeratedAttributes = nil
            })
            menu.addItem(ActionMenuItem("Iterate - N reviews", checked: isIterateActive) {
                node.enumeratedAttributes = ["*"]
                node.bundledAttributes = nil
            })
            menu.addItem(.separator())
            menu.addItem(ActionMenuItem("Clear AI Review") {
                node.bundledAttributes = nil
                node.enumeratedAttributes = nil
            })
        } else {
            menu.addItem(ActionMenuItem("Create Bundle") {
                node.bundledAttributes = ["*"]
                node.enumeratedAttributes = nil
            })
            menu.addItem(ActionMenuItem("Create Iterate") {
                node.enumeratedAttributes = ["*"]
                node.bundledAttributes = nil
            })
        }

        return menu
    }

    /// Full menu for configured object collections.
    /// Structure: Bundle▶, Iterate▶, separator, Create▶, separator, Clear [mode]
    private func buildConfiguredMenu(checkedMode: CheckedMode) -> NSMenu {
        let menu = NSMenu()

        // Bundle ▶ → attribute submenu
        let bundleItem = NSMenuItem(title: "Bundle", action: nil, keyEquivalent: "")
        bundleItem.state = checkedMode == .bundle ? .on : .off
        bundleItem.submenu = buildBundleAttributeSubmenu(parentChecked: checkedMode == .bundle)
        menu.addItem(bundleItem)

        // Iterate ▶ → attribute submenu
        let iterateItem = NSMenuItem(title: "Iterate", action: nil, keyEquivalent: "")
        iterateItem.state = checkedMode == .iterate ? .on : .off
        iterateItem.submenu = buildIterateAttributeSubmenu(parentChecked: checkedMode == .iterate)
        menu.addItem(iterateItem)

        menu.addItem(.separator())

        // Create ▶ → Bundle▶ / Iterate▶ sub-submenus
        let createItem = NSMenuItem(title: "Create", action: nil, keyEquivalent: "")
        createItem.submenu = buildCreateSubmenu()
        menu.addItem(createItem)

        menu.addItem(.separator())

        // Clear [mode]
        if checkedMode == .bundle {
            menu.addItem(ActionMenuItem("Clear Bundle") {
                node.bundledAttributes = nil
            })
        } else {
            menu.addItem(ActionMenuItem("Clear Iterate") {
                node.enumeratedAttributes = nil
            })
        }

        return menu
    }

    /// Menu for unset object collections: Create Bundle▶ / Create Iterate▶
    private func buildUnsetMenu() -> NSMenu {
        let menu = NSMenu()

        let createBundleItem = NSMenuItem(title: "Create Bundle", action: nil, keyEquivalent: "")
        createBundleItem.submenu = buildBundleAttributeSubmenu(parentChecked: false)
        menu.addItem(createBundleItem)

        let createIterateItem = NSMenuItem(title: "Create Iterate", action: nil, keyEquivalent: "")
        createIterateItem.submenu = buildIterateAttributeSubmenu(parentChecked: false)
        menu.addItem(createIterateItem)

        return menu
    }

    // MARK: - Attribute Submenus

    /// Bundle attribute submenu: each attribute toggles in/out of bundledAttributes.
    /// Nested arrays get a sub-submenu with the leaf label.
    /// Checkmarks only shown when `parentChecked` is true (this mode is active).
    private func buildBundleAttributeSubmenu(parentChecked: Bool) -> NSMenu {
        let sub = NSMenu()

        for attr in availableAttributes {
            if isNestedArray(attr) {
                let isActive = isAttributeBundled(attr)
                let showCheck = parentChecked && isActive
                let item = NSMenuItem(title: attr, action: nil, keyEquivalent: "")
                item.state = showCheck ? .on : .off

                let nested = NSMenu()
                nested.addItem(ActionMenuItem(leafLabel(for: attr), checked: showCheck) {
                    if isActive {
                        removeFromBundledAttributes(attr)
                    } else {
                        removeFromEnumeratedAttributes(attr)
                        removeFromEnumeratedAttributes(attr + "[]")
                        addToBundledAttributes(attr)
                    }
                })
                item.submenu = nested
                sub.addItem(item)
            } else {
                let isActive = isAttributeBundled(attr)
                let showCheck = parentChecked && isActive
                sub.addItem(ActionMenuItem(attr, checked: showCheck) {
                    if isActive {
                        removeFromBundledAttributes(attr)
                    } else {
                        removeFromEnumeratedAttributes(attr)
                        removeFromEnumeratedAttributes(attr + "[]")
                        addToBundledAttributes(attr)
                    }
                })
            }
        }

        return sub
    }

    /// Iterate attribute submenu: scalar attributes toggle directly.
    /// Nested arrays get a sub-submenu with Bundle▶/Iterate▶ options.
    /// Checkmarks only shown when `parentChecked` is true (this mode is active).
    private func buildIterateAttributeSubmenu(parentChecked: Bool) -> NSMenu {
        let sub = NSMenu()

        for attr in availableAttributes {
            if isNestedArray(attr) {
                let attrWithSuffix = attr + "[]"
                let isBundledPerEntry = isAttributeIterated(attr) && !isAttributeIterated(attrWithSuffix)
                let isIteratedEach = isAttributeIterated(attrWithSuffix)
                let isActive = isBundledPerEntry || isIteratedEach
                let showCheck = parentChecked && isActive
                let leaf = leafLabel(for: attr)

                let item = NSMenuItem(title: attr, action: nil, keyEquivalent: "")
                item.state = showCheck ? .on : .off

                let nested = NSMenu()

                // Bundle ▶ → leaf
                let showBundleCheck = showCheck && isBundledPerEntry
                let bundleNested = NSMenuItem(title: "Bundle", action: nil, keyEquivalent: "")
                bundleNested.state = showBundleCheck ? .on : .off
                let bundleLeafMenu = NSMenu()
                bundleLeafMenu.addItem(ActionMenuItem(leaf, checked: showBundleCheck) {
                    removeAttributeFromBoth(attr)
                    addToEnumeratedAttributes(attr)
                })
                bundleNested.submenu = bundleLeafMenu
                nested.addItem(bundleNested)

                // Iterate ▶ → leaf
                let showIterateCheck = showCheck && isIteratedEach
                let iterateNested = NSMenuItem(title: "Iterate", action: nil, keyEquivalent: "")
                iterateNested.state = showIterateCheck ? .on : .off
                let iterateLeafMenu = NSMenu()
                iterateLeafMenu.addItem(ActionMenuItem(leaf, checked: showIterateCheck) {
                    removeAttributeFromBoth(attr)
                    addToEnumeratedAttributes(attrWithSuffix)
                })
                iterateNested.submenu = iterateLeafMenu
                nested.addItem(iterateNested)

                item.submenu = nested
                sub.addItem(item)
            } else {
                let isActive = isAttributeIterated(attr)
                let showCheck = parentChecked && isActive
                sub.addItem(ActionMenuItem(attr, checked: showCheck) {
                    if isActive {
                        removeFromEnumeratedAttributes(attr)
                    } else {
                        removeFromBundledAttributes(attr)
                        addToEnumeratedAttributes(attr)
                    }
                })
            }
        }

        return sub
    }

    /// Create submenu with Bundle▶ and Iterate▶ sub-submenus
    private func buildCreateSubmenu() -> NSMenu {
        let menu = NSMenu()

        let bundleItem = NSMenuItem(title: "Bundle", action: nil, keyEquivalent: "")
        bundleItem.submenu = buildBundleAttributeSubmenu(parentChecked: false)
        menu.addItem(bundleItem)

        let iterateItem = NSMenuItem(title: "Iterate", action: nil, keyEquivalent: "")
        iterateItem.submenu = buildIterateAttributeSubmenu(parentChecked: false)
        menu.addItem(iterateItem)

        return menu
    }

    /// Simple singularization for leaf display labels (keywords → Keyword)
    private func leafLabel(for attr: String) -> String {
        let name = attr.titleCased
        if name.hasSuffix("s") && !name.hasSuffix("ss") {
            return String(name.dropLast())
        }
        return name
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
