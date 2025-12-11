//
//  AttributePickerView.swift
//  Sprung
//
//  Popup for selecting which attributes to include when toggling a collection node.
//  Shows available attributes with bundle/enumerate mode selection.
//
//  Path pattern semantics:
//  - `*` (bundle) = combine all matches into ONE revnode for holistic review
//  - `[]` (enumerate) = one revnode per item for individual review
//

import SwiftUI
import SwiftData

/// Grouping mode for attribute selection
enum AttributeGroupingMode: String, CaseIterable {
    case bundle = "*"       // Combine all into 1 revnode
    case enumerate = "[]"   // One revnode per item

    var displayName: String {
        switch self {
        case .bundle: return "Bundle"
        case .enumerate: return "Per-item"
        }
    }

    var description: String {
        switch self {
        case .bundle: return "Review all together"
        case .enumerate: return "Review each separately"
        }
    }
}

/// Selection info for an attribute including its grouping mode
struct AttributeSelection: Equatable {
    let name: String
    var mode: AttributeGroupingMode
}

struct AttributePickerView: View {
    let collectionNode: TreeNode
    let onApply: ([AttributeSelection]) -> Void
    let onCancel: () -> Void

    @State private var selections: [String: AttributeGroupingMode]

    init(collectionNode: TreeNode, onApply: @escaping ([AttributeSelection]) -> Void, onCancel: @escaping () -> Void) {
        self.collectionNode = collectionNode
        self.onApply = onApply
        self.onCancel = onCancel

        // Initialize with current selections
        var initial: [String: AttributeGroupingMode] = [:]
        for attr in collectionNode.selectedGroupAttributes {
            initial[attr.name] = attr.mode
        }
        _selections = State(initialValue: initial)
    }

    /// Get available attributes from child nodes (assumes uniform structure)
    private var availableAttributes: [(name: String, count: Int, hasGrandchildren: Bool, entryCount: Int)] {
        guard let firstChild = collectionNode.orderedChildren.first else { return [] }

        var attributes: [(name: String, count: Int, hasGrandchildren: Bool, entryCount: Int)] = []
        let entryCount = collectionNode.orderedChildren.count

        for attr in firstChild.orderedChildren {
            let attrName = attr.name.isEmpty ? attr.value : attr.name
            guard !attrName.isEmpty else { continue }

            var totalCount = 0
            var hasGrandchildren = false

            for child in collectionNode.orderedChildren {
                if let matchingAttr = child.orderedChildren.first(where: {
                    ($0.name.isEmpty ? $0.value : $0.name) == attrName
                }) {
                    if !matchingAttr.orderedChildren.isEmpty {
                        hasGrandchildren = true
                        totalCount += matchingAttr.orderedChildren.count
                    } else {
                        totalCount += 1
                    }
                }
            }

            attributes.append((name: attrName, count: totalCount, hasGrandchildren: hasGrandchildren, entryCount: entryCount))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select attributes to customize:")
                .font(.headline)
                .foregroundColor(.primary)

            if !hasUniformStructure {
                Text("Children have different structures")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(availableAttributes, id: \.name) { attr in
                    AttributeRow(
                        attr: attr,
                        isSelected: selections[attr.name] != nil,
                        mode: selections[attr.name] ?? .enumerate,
                        onToggle: { isSelected in
                            if isSelected {
                                // Default: bundle for scalars, enumerate for containers
                                selections[attr.name] = attr.hasGrandchildren ? .enumerate : .bundle
                            } else {
                                selections.removeValue(forKey: attr.name)
                            }
                        },
                        onModeChange: { newMode in
                            selections[attr.name] = newMode
                        }
                    )
                }
            }
            .padding(.vertical, 4)

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Apply") {
                    let result = selections.map { AttributeSelection(name: $0.key, mode: $0.value) }
                    onApply(result)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selections.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 380)
    }
}

/// Row for a single attribute with checkbox and mode picker
private struct AttributeRow: View {
    let attr: (name: String, count: Int, hasGrandchildren: Bool, entryCount: Int)
    let isSelected: Bool
    let mode: AttributeGroupingMode
    let onToggle: (Bool) -> Void
    let onModeChange: (AttributeGroupingMode) -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Toggle(isOn: Binding(
                get: { isSelected },
                set: { onToggle($0) }
            )) {
                Text(attr.name)
                    .font(.body)
            }
            .toggleStyle(.checkbox)
            .frame(minWidth: 100, alignment: .leading)

            // Count info
            Group {
                if attr.hasGrandchildren {
                    Text("\(attr.count) items / \(attr.entryCount) entries")
                } else {
                    Text("\(attr.entryCount) entries")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(minWidth: 100, alignment: .leading)

            Spacer()

            // Mode picker (only show when selected)
            if isSelected {
                Picker("", selection: Binding(
                    get: { mode },
                    set: { onModeChange($0) }
                )) {
                    ForEach(AttributeGroupingMode.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .help(mode.description)
            }
        }
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

    /// Apply group selection for specified attributes across all child entries
    /// - Parameters:
    ///   - selections: Attributes to select with their grouping modes
    ///   - sourceId: ID of the collection node triggering the selection
    func applyGroupSelection(selections: [AttributeSelection], sourceId: String) {
        let selectionMap = Dictionary(uniqueKeysWithValues: selections.map { ($0.name, $0.mode) })

        for child in orderedChildren {
            for attr in child.orderedChildren {
                let attrName = attr.name.isEmpty ? attr.value : attr.name
                if let mode = selectionMap[attrName] {
                    attr.status = .aiToReplace
                    attr.groupSelectionSourceId = sourceId
                    attr.groupSelectionModeRaw = mode.rawValue
                }
            }
        }
    }

    /// Clear group selection that originated from this node
    func clearGroupSelection() {
        for child in orderedChildren {
            for attr in child.orderedChildren {
                if attr.groupSelectionSourceId == id {
                    attr.status = .saved
                    attr.groupSelectionSourceId = nil
                    attr.groupSelectionModeRaw = nil
                }
            }
        }
    }

    /// Get currently selected attributes with their modes for this collection node
    var selectedGroupAttributes: [AttributeSelection] {
        var selections: [String: AttributeGroupingMode] = [:]
        for child in orderedChildren {
            for attr in child.orderedChildren {
                if attr.groupSelectionSourceId == id {
                    let attrName = attr.name.isEmpty ? attr.value : attr.name
                    let mode = AttributeGroupingMode(rawValue: attr.groupSelectionModeRaw ?? "[]") ?? .enumerate
                    selections[attrName] = mode
                }
            }
        }
        return selections.map { AttributeSelection(name: $0.key, mode: $0.value) }
    }

    /// Build path patterns for all group selections on this collection node
    /// Returns patterns like "skills.*.name" (bundle) or "skills[].keywords" (enumerate)
    func buildGroupSelectionPatterns() -> [String] {
        let sectionName = name.isEmpty ? value : name
        return selectedGroupAttributes.map { selection in
            let wildcard = selection.mode.rawValue  // "*" or "[]"
            return "\(sectionName)\(wildcard).\(selection.name)"
        }
    }
}
