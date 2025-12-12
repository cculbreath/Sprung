//
//  AttributePickerView.swift
//  Sprung
//
//  Popup for selecting AI review mode per attribute on a collection node.
//
//  Path pattern semantics:
//  - `*` (together/bundle) = combine all matches into ONE revnode for holistic review
//  - `[]` (separately/enumerate) = one revnode per entry for individual review
//
//  UI hierarchy:
//  1. Collection level: set mode per attribute (Off/Together/Separately)
//  2. Entry level: filter which entries to include (for Separately mode) - shown conditionally
//  3. Attribute level: filter which children within that attribute
//

import SwiftUI
import SwiftData

/// Review mode for an attribute within a collection
enum AttributeReviewMode: String, CaseIterable, Codable {
    case off         // Not AI-reviewed
    case together    // Bundle: 1 revnode with all entries' values (pattern: section.*.attr)
    case separately  // Enumerate: N revnodes, one per entry (pattern: section[].attr)

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .together: return "Together"
        case .separately: return "Separately"
        }
    }

    var pathSymbol: String? {
        switch self {
        case .off: return nil
        case .together: return "*"
        case .separately: return "[]"
        }
    }
}

/// Selection result from attribute picker - maps attribute names to their review modes
struct AttributePickerResult: Equatable {
    let attributeModes: [String: AttributeReviewMode]
}

struct AttributePickerView: View {
    let collectionNode: TreeNode
    let onApply: (AttributePickerResult) -> Void
    let onCancel: () -> Void

    @State private var attributeModes: [String: AttributeReviewMode]

    init(collectionNode: TreeNode, onApply: @escaping (AttributePickerResult) -> Void, onCancel: @escaping () -> Void) {
        self.collectionNode = collectionNode
        self.onApply = onApply
        self.onCancel = onCancel

        // Initialize from current state on the collection node
        var initial: [String: AttributeReviewMode] = [:]

        // Check bundled attributes (Together mode)
        if let bundled = collectionNode.bundledAttributes {
            for attr in bundled {
                initial[attr] = .together
            }
        }

        // Check enumerated attributes (Separately mode)
        if let enumerated = collectionNode.enumeratedAttributes {
            for attr in enumerated {
                initial[attr] = .separately
            }
        }

        _attributeModes = State(initialValue: initial)
    }

    /// Get shared attributes across all entries
    private var sharedAttributes: [(name: String, itemCount: Int, entryCount: Int)] {
        guard let firstChild = collectionNode.orderedChildren.first else { return [] }

        var attributes: [(name: String, itemCount: Int, entryCount: Int)] = []
        let entryCount = collectionNode.orderedChildren.count

        for attr in firstChild.orderedChildren {
            let attrName = attr.name.isEmpty ? attr.value : attr.name
            guard !attrName.isEmpty else { continue }

            // Count total items across all entries for this attribute
            var totalCount = 0
            for entry in collectionNode.orderedChildren {
                if let matchingAttr = entry.orderedChildren.first(where: {
                    ($0.name.isEmpty ? $0.value : $0.name) == attrName
                }) {
                    if !matchingAttr.orderedChildren.isEmpty {
                        totalCount += matchingAttr.orderedChildren.count
                    } else {
                        totalCount += 1
                    }
                }
            }

            attributes.append((name: attrName, itemCount: totalCount, entryCount: entryCount))
        }

        return attributes
    }

    /// Check if children have uniform structure
    private var hasUniformStructure: Bool {
        let children = collectionNode.orderedChildren
        guard children.count > 1, let first = children.first else { return true }

        let firstAttrNames = Set(first.orderedChildren.map { $0.name.isEmpty ? $0.value : $0.name })

        for child in children.dropFirst() {
            let childAttrNames = Set(child.orderedChildren.map { $0.name.isEmpty ? $0.value : $0.name })
            if childAttrNames != firstAttrNames {
                return false
            }
        }
        return true
    }

    /// Whether any attribute is set to Separately mode
    private var hasSeparatelyMode: Bool {
        attributeModes.values.contains(.separately)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("AI Review Settings")
                .font(.headline)
                .foregroundColor(.primary)

            if !hasUniformStructure {
                Text("Entries have different structures - some attributes may not exist in all entries")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            // Per-attribute mode selection
            VStack(alignment: .leading, spacing: 4) {
                // Header row
                HStack(spacing: 0) {
                    Text("Attribute")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(width: 120, alignment: .leading)

                    Spacer()

                    Text("Review Mode")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 4)

                Divider()

                // Attribute rows
                ForEach(sharedAttributes, id: \.name) { attr in
                    AttributeModeRow(
                        attrName: attr.name,
                        itemCount: attr.itemCount,
                        entryCount: attr.entryCount,
                        mode: Binding(
                            get: { attributeModes[attr.name] ?? .off },
                            set: { attributeModes[attr.name] = $0 }
                        )
                    )
                }
            }
            .padding(.vertical, 4)

            // Help text
            VStack(alignment: .leading, spacing: 2) {
                Text("Together: All entries bundled into one review")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Separately: Each entry reviewed individually")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Buttons
            HStack {
                Button("Clear All") {
                    attributeModes.removeAll()
                }
                .buttonStyle(.link)
                .font(.caption)

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Apply") {
                    let result = AttributePickerResult(attributeModes: attributeModes)
                    onApply(result)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 400)
    }
}

/// Row for a single attribute with tri-state mode picker
private struct AttributeModeRow: View {
    let attrName: String
    let itemCount: Int
    let entryCount: Int
    @Binding var mode: AttributeReviewMode

    var body: some View {
        HStack(spacing: 8) {
            // Attribute name and count
            VStack(alignment: .leading, spacing: 2) {
                Text(attrName)
                    .font(.body)
                Text(itemCount > entryCount ? "\(itemCount) items" : "\(entryCount) values")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 120, alignment: .leading)

            Spacer()

            // Tri-state picker
            Picker("", selection: $mode) {
                ForEach(AttributeReviewMode.allCases, id: \.self) { m in
                    Text(m.displayName).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
        .padding(.vertical, 4)
    }
}

/// Helper to detect if a node is a "collection" node that should show attribute picker
extension TreeNode {
    /// Returns true if this node is a collection with uniform child structure
    /// (i.e., children have the same set of attribute names)
    var isCollectionNode: Bool {
        let children = orderedChildren
        guard children.count > 0 else { return false }

        // Must have children that themselves have children (structured entries)
        guard let first = children.first, !first.orderedChildren.isEmpty else { return false }

        // Check if all children have the same attribute names
        let firstAttrNames = Set(first.orderedChildren.compactMap {
            $0.name.isEmpty ? (($0.value.isEmpty) ? nil : $0.value) : $0.name
        })

        // Need at least 2 attributes to be considered a collection
        guard firstAttrNames.count >= 2 else { return false }

        for child in children.dropFirst() {
            let childAttrNames = Set(child.orderedChildren.compactMap {
                $0.name.isEmpty ? (($0.value.isEmpty) ? nil : $0.value) : $0.name
            })
            if childAttrNames != firstAttrNames {
                return false
            }
        }
        return true
    }

    /// Apply attribute picker result to this collection node.
    /// Stores per-attribute modes and updates AI state accordingly.
    func applyPickerResult(_ result: AttributePickerResult) {
        // Separate attributes by mode
        var bundled: [String] = []
        var enumerated: [String] = []

        for (attrName, mode) in result.attributeModes {
            switch mode {
            case .off:
                break // Not included
            case .together:
                bundled.append(attrName)
            case .separately:
                enumerated.append(attrName)
            }
        }

        // Store the attribute lists
        bundledAttributes = bundled.isEmpty ? nil : bundled
        enumeratedAttributes = enumerated.isEmpty ? nil : enumerated

        // Update AI status on collection node:
        // If any bundled attributes, collection itself is aiEnabled
        if !bundled.isEmpty {
            status = .aiToReplace
        } else {
            status = .saved
        }

        // For enumerated attributes, entries need to be enabled separately
        // (entry-level sparkle becomes visible when hasEnumeratedAttributes is true)
        // Default: enable all entries when first setting up enumerated mode
        if !enumerated.isEmpty {
            for entry in orderedChildren {
                entry.status = .aiToReplace
            }
        }
    }

    /// Clear all AI state from this collection and its entries
    func clearCollectionAIState() {
        status = .saved
        bundledAttributes = nil
        enumeratedAttributes = nil
        for entry in orderedChildren {
            entry.status = .saved
        }
    }

    /// Build path patterns for this collection's AI selections.
    /// Returns patterns like "skills.*.name" (bundle) or "skills[].keywords" (enumerate)
    func buildCollectionPatterns() -> [String] {
        let sectionName = name.isEmpty ? value : name
        var patterns: [String] = []

        // Bundle patterns: section.*.attr
        if let bundled = bundledAttributes {
            for attr in bundled {
                patterns.append("\(sectionName).*.\(attr)")
            }
        }

        // Enumerate patterns: section[].attr (only for enabled entries)
        if let enumerated = enumeratedAttributes {
            // Only include patterns if at least one entry is enabled
            let hasEnabledEntries = orderedChildren.contains { $0.status == .aiToReplace }
            if hasEnabledEntries {
                for attr in enumerated {
                    patterns.append("\(sectionName)[].\(attr)")
                }
            }
        }

        return patterns
    }

    /// Get enabled entry IDs (for enumerate mode)
    var enabledEntryIds: [String] {
        orderedChildren.filter { $0.status == .aiToReplace }.map { $0.id }
    }
}
