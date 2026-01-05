//
//  CollectionAttributeManager.swift
//  Sprung
//
//  Manages collection attribute modes for AI review.
//  Extracted from NodeHeaderView for single responsibility.
//

import Foundation

/// Manages collection attribute modes for AI review
@MainActor
struct CollectionAttributeManager {

    /// Toggle the AI status of a node
    static func toggleAIStatus(node: TreeNode, vm: ResumeDetailVM) {
        if node.status == .aiToReplace {
            node.status = .saved
            node.bundledAttributes = nil
            node.enumeratedAttributes = nil
        } else {
            node.status = .aiToReplace
        }
        vm.refreshRevnodeCount()
    }

    /// Set the AI review mode for an attribute across the collection
    static func setAttributeMode(_ mode: AIReviewMode, for node: TreeNode, vm: ResumeDetailVM) {
        guard let collection = NodeAIReviewModeDetector.collectionNode(for: node) else { return }
        let attr = NodeAIReviewModeDetector.attributeName(of: node)

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
    static func clearSoloStatusForAttribute(_ attr: String, in collection: TreeNode) {
        for entry in collection.orderedChildren {
            for attrNode in entry.orderedChildren {
                let nodeName = attrNode.name.isEmpty ? attrNode.displayLabel : attrNode.name
                if nodeName == attr && attrNode.status == .aiToReplace {
                    attrNode.status = .saved
                }
            }
        }
    }

    /// Set mode for scalar array collections (uses "*" as attribute name)
    static func setScalarCollectionMode(_ mode: AIReviewMode, for node: TreeNode, vm: ResumeDetailVM) {
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
    static func toggleCollectionAttribute(_ attr: String, mode: AIReviewMode, for node: TreeNode, vm: ResumeDetailVM) {
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
    static func removeCollectionAttribute(_ attr: String, from node: TreeNode, vm: ResumeDetailVM) {
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
    static func clearAllCollectionModes(for node: TreeNode, vm: ResumeDetailVM) {
        node.bundledAttributes = nil
        node.enumeratedAttributes = nil
        vm.refreshRevnodeCount()
    }

    // MARK: - Collection Context Menu Helpers

    /// Whether this collection contains scalar values (no nested attributes)
    static func isScalarArrayCollection(_ node: TreeNode) -> Bool {
        guard !node.orderedChildren.isEmpty else { return false }
        guard let firstChild = node.orderedChildren.first else { return false }
        return firstChild.orderedChildren.isEmpty
    }

    /// Get attribute names available in this collection's entries
    static func availableAttributes(in node: TreeNode) -> [String] {
        guard let firstChild = node.orderedChildren.first else { return [] }
        return firstChild.orderedChildren.compactMap {
            let name = $0.name.isEmpty ? $0.displayLabel : $0.name
            return name.isEmpty ? nil : name
        }
    }

    /// Check if an attribute is itself an array (has children)
    static func isNestedArray(_ attrName: String, in node: TreeNode) -> Bool {
        guard let firstChild = node.orderedChildren.first,
              let attr = firstChild.orderedChildren.first(where: {
                  ($0.name.isEmpty ? $0.displayLabel : $0.name) == attrName
              }) else { return false }
        return !attr.orderedChildren.isEmpty
    }

    /// Check if an attribute is currently in bundle mode
    static func isAttributeBundled(_ attr: String, in node: TreeNode) -> Bool {
        node.bundledAttributes?.contains(attr) == true
    }

    /// Check if an attribute is currently in iterate mode
    static func isAttributeIterated(_ attr: String, in node: TreeNode) -> Bool {
        node.enumeratedAttributes?.contains(attr) == true
    }
}
