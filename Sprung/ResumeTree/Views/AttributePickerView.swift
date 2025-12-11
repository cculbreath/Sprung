//
//  AttributePickerView.swift
//  Sprung
//
//  Popup for selecting which attributes to include when toggling a collection node.
//  Shows available attributes from uniform child structure with checkboxes.
//

import SwiftUI
import SwiftData

struct AttributePickerView: View {
    let collectionNode: TreeNode
    let onApply: ([String]) -> Void
    let onCancel: () -> Void

    @State private var selectedAttributes: Set<String> = []

    /// Get available attributes from child nodes (assumes uniform structure)
    private var availableAttributes: [(name: String, count: Int, hasGrandchildren: Bool)] {
        guard let firstChild = collectionNode.orderedChildren.first else { return [] }

        // Get attribute names from first child's children
        var attributes: [(name: String, count: Int, hasGrandchildren: Bool)] = []

        for attr in firstChild.orderedChildren {
            let attrName = attr.name.isEmpty ? attr.value : attr.name
            guard !attrName.isEmpty else { continue }

            // Count total items across all children for this attribute
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

            attributes.append((name: attrName, count: totalCount, hasGrandchildren: hasGrandchildren))
        }

        return attributes
    }

    /// Check if children have uniform structure (same attribute names)
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

            VStack(alignment: .leading, spacing: 8) {
                ForEach(availableAttributes, id: \.name) { attr in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { selectedAttributes.contains(attr.name) },
                            set: { isSelected in
                                if isSelected {
                                    selectedAttributes.insert(attr.name)
                                } else {
                                    selectedAttributes.remove(attr.name)
                                }
                            }
                        )) {
                            HStack {
                                Text(attr.name)
                                    .font(.body)
                                Spacer()
                                if attr.hasGrandchildren {
                                    Text("(\(attr.count) items across \(collectionNode.orderedChildren.count) entries)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("(\(collectionNode.orderedChildren.count) entries)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
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
                    onApply(Array(selectedAttributes))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedAttributes.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 300)
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
    ///   - attributes: Names of attributes to select
    ///   - sourceId: ID of the collection node triggering the selection
    func applyGroupSelection(attributes: [String], sourceId: String) {
        for child in orderedChildren {
            for attr in child.orderedChildren {
                let attrName = attr.name.isEmpty ? attr.value : attr.name
                if attributes.contains(attrName) {
                    attr.status = .aiToReplace
                    attr.groupSelectionSourceId = sourceId
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
                }
            }
        }
    }

    /// Get currently selected attributes for this collection node
    var selectedGroupAttributes: [String] {
        var selected: Set<String> = []
        for child in orderedChildren {
            for attr in child.orderedChildren {
                if attr.groupSelectionSourceId == id {
                    let attrName = attr.name.isEmpty ? attr.value : attr.name
                    selected.insert(attrName)
                }
            }
        }
        return Array(selected)
    }
}
