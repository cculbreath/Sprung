//
//  NodeAIReviewModeDetector.swift
//  Sprung
//
//  Detects AI review modes for tree nodes.
//  Extracted from NodeHeaderView for single responsibility.
//

import Foundation
import SwiftUI

/// Detects AI review modes for tree nodes
struct NodeAIReviewModeDetector {

    /// Whether this collection has BOTH bundle and iterate modes (mixed mode)
    static func hasMixedModes(_ node: TreeNode) -> Bool {
        node.bundledAttributes?.isEmpty == false && node.enumeratedAttributes?.isEmpty == false
    }

    /// Current AI review mode for this node (primary mode if mixed)
    static func aiMode(for node: TreeNode) -> AIReviewMode {
        if node.bundledAttributes?.isEmpty == false {
            return .bundle
        } else if node.enumeratedAttributes?.isEmpty == false {
            return .iterate
        } else if node.status == .aiToReplace {
            return .solo  // Solo mode for directly marked nodes
        } else if node.aiStatusChildren > 0 {
            return .containsSolo  // Container has solo children (show outline only)
        }
        return .off
    }

    /// The grandparent node (collection level) if this node is an attribute under an entry
    static func grandparentNode(of node: TreeNode) -> TreeNode? {
        node.parent?.parent
    }

    /// The attribute name for bundle/iterate configuration
    static func attributeName(of node: TreeNode) -> String {
        node.name.isEmpty ? node.displayLabel : node.name
    }

    /// Whether this node is an attribute under a collection entry (e.g., "keywords" under a skill)
    /// True if grandparent is a collection node OR has bundle/iterate settings for this attribute
    static func isAttributeOfCollectionEntry(_ node: TreeNode) -> Bool {
        guard let grandparent = grandparentNode(of: node) else { return false }
        // Check if grandparent has AI review settings for this attribute
        let attr = attributeName(of: node)
        if grandparent.bundledAttributes?.contains(attr) == true { return true }
        if grandparent.enumeratedAttributes?.contains(attr) == true { return true }
        // Fall back to structural check - but exclude root (grandparent must have a parent)
        guard grandparent.parent != nil else { return false }
        return grandparent.isCollectionNode
    }

    /// The collection node (grandparent) when this is an attribute of a collection entry
    static func collectionNode(for node: TreeNode) -> TreeNode? {
        guard isAttributeOfCollectionEntry(node) else { return nil }
        return grandparentNode(of: node)
    }

    /// Current mode for this specific attribute across the collection
    /// For scalar attributes (no children):
    /// - bundledAttributes["name"] → purple (all combined)
    /// - enumeratedAttributes["name"] → cyan (each separate)
    /// For array attributes (has children):
    /// - *Attributes["keywords"] → purple (bundled together)
    /// - *Attributes["keywords[]"] → cyan (each item separate)
    static func attributeMode(for node: TreeNode) -> AIReviewMode {
        guard let grandparent = grandparentNode(of: node) else { return .off }
        let attr = attributeName(of: node)
        let attrWithSuffix = attr + "[]"
        let isArrayAttribute = !node.orderedChildren.isEmpty

        if isArrayAttribute {
            // Array attribute: check for [] suffix to determine mode
            // With [] suffix = each item separate (cyan)
            if grandparent.bundledAttributes?.contains(attrWithSuffix) == true ||
               grandparent.enumeratedAttributes?.contains(attrWithSuffix) == true {
                return .iterate  // Cyan - each item is separate
            }
            // Without [] suffix = bundled together (purple)
            if grandparent.bundledAttributes?.contains(attr) == true ||
               grandparent.enumeratedAttributes?.contains(attr) == true {
                return .bundle  // Purple - items bundled together
            }
        } else {
            // Scalar attribute: enumeratedAttributes = cyan, bundledAttributes = purple
            if grandparent.enumeratedAttributes?.contains(attr) == true {
                return .iterate  // Cyan - each entry's value separate
            }
            if grandparent.bundledAttributes?.contains(attr) == true {
                return .bundle  // Purple - all values combined
            }
        }

        if node.status == .aiToReplace {
            return .solo  // Orange - just this single node
        }
        return .off
    }

    /// Whether this attribute is extracted per-entry (vs all-combined)
    static func isPerEntryExtraction(_ node: TreeNode) -> Bool {
        guard let grandparent = grandparentNode(of: node) else { return false }
        return grandparent.enumeratedAttributes?.contains(attributeName(of: node)) == true
    }

    /// Generate the path pattern for this node's review configuration
    static func pathPattern(for node: TreeNode) -> String? {
        guard let grandparent = grandparentNode(of: node) else { return nil }
        let attr = attributeName(of: node)
        let collectionName = grandparent.name.isEmpty ? grandparent.displayLabel : grandparent.name

        if grandparent.bundledAttributes?.contains(attr) == true {
            return "\(collectionName.lowercased()).*.\(attr)"  // e.g., skills.*.name
        } else if grandparent.enumeratedAttributes?.contains(attr) == true {
            return "\(collectionName.lowercased())[].\(attr)"  // e.g., skills[].keywords
        }
        return nil
    }

    /// Whether this node is a child of a container being reviewed (bundle/iterate)
    /// e.g., "Swift" is a child of "keywords" which is set to iterate
    static func isChildOfReviewedContainer(_ node: TreeNode) -> Bool {
        guard let parent = node.parent,
              let grandparent = parent.parent,
              let greatGrandparent = grandparent.parent else { return false }

        let parentName = parent.name.isEmpty ? parent.displayLabel : parent.name

        // Check if great-grandparent has parent's name in bundle/iterate
        if greatGrandparent.bundledAttributes?.contains(parentName) == true { return true }
        if greatGrandparent.enumeratedAttributes?.contains(parentName) == true { return true }

        return false
    }

    /// Whether this node is an entry under a collection with review config
    /// e.g., "Software Engineering" is an entry under "Skills" which has enumeratedAttributes
    static func isEntryUnderReviewedCollection(_ node: TreeNode) -> Bool {
        guard let parent = node.parent else { return false }
        // Exclude container enumerate children - they get icon + background, not outline
        if parent.enumeratedAttributes?.contains("*") == true { return false }
        return parent.bundledAttributes?.isEmpty == false || parent.enumeratedAttributes?.isEmpty == false
    }

    /// Whether this node is a child of a container enumerate pattern (parent has enumeratedAttributes: ["*"])
    /// e.g., "Physicist" under "Job Titles" where jobTitles[] is configured
    static func isContainerEnumerateChild(_ node: TreeNode) -> Bool {
        guard let parent = node.parent else { return false }
        return parent.enumeratedAttributes?.contains("*") == true
    }

    /// Whether clicking the AI mode indicator should toggle mode
    /// Only interactive on attribute nodes - collection nodes show read-only summary
    static func isAIModeInteractive(_ node: TreeNode) -> Bool {
        isAttributeOfCollectionEntry(node) && !isChildOfReviewedContainer(node)
    }

    /// Whether this node is itself a container enumerate node (has enumeratedAttributes["*"])
    static func isContainerEnumerateNode(_ node: TreeNode) -> Bool {
        node.enumeratedAttributes?.contains("*") == true
    }

    /// Whether this node supports collection modes (bundle/iterate)
    /// True for any non-root node with children (both object arrays and scalar arrays)
    static func supportsCollectionModes(_ node: TreeNode) -> Bool {
        node.parent != nil && !node.orderedChildren.isEmpty
    }

    /// Whether to show the AI mode indicator (icon badge)
    static func showAIModeIndicator(for node: TreeNode, isHoveringHeader: Bool) -> Bool {
        // Entry nodes get outline instead of icon - never show icon
        if isEntryUnderReviewedCollection(node) { return false }

        // Containers of solo items get outline, not icon
        if aiMode(for: node) == .containsSolo { return false }

        // Always show if node has actual AI configuration
        if node.parent != nil && (
            node.status == .aiToReplace ||
            node.hasAttributeReviewModes ||
            isContainerEnumerateNode(node) ||
            isAttributeOfCollectionEntry(node) ||
            isChildOfReviewedContainer(node) ||
            isContainerEnumerateChild(node)
        ) {
            return true
        }

        // Only show hover indicator for interactive nodes (attribute nodes that can be clicked)
        // or collection nodes (right-click menu available)
        if isHoveringHeader && node.parent != nil {
            return isAIModeInteractive(node) || supportsCollectionModes(node)
        }

        return false
    }

    /// The mode to display for this node
    static func displayMode(for node: TreeNode) -> AIReviewMode {
        // Container enumerate node (e.g., jobTitles with enumeratedAttributes["*"])
        // Shows cyan iterate icon (the container itself, not children)
        if isContainerEnumerateNode(node) {
            return .iterate
        }
        // Container enumerate children get iterate mode (cyan icon + background)
        if isContainerEnumerateChild(node) {
            return .iterate
        }
        // Check if this is a child of a reviewed container first
        if isChildOfReviewedContainer(node) {
            return .included
        }
        // Entry under reviewed collection (e.g., Software Engineering under Skills)
        if isEntryUnderReviewedCollection(node) {
            return .included  // Show included indicator (but no icon, just outline)
        }
        if isAttributeOfCollectionEntry(node) {
            return attributeMode(for: node)
        }
        return aiMode(for: node)
    }

    /// Whether this is an array attribute marked with [] suffix (each item separate)
    static func isIterateArrayAttribute(_ node: TreeNode) -> Bool {
        guard let grandparent = grandparentNode(of: node) else { return false }
        let attr = attributeName(of: node)
        let attrWithSuffix = attr + "[]"
        // Only true for array attributes (has children) with [] suffix
        guard !node.orderedChildren.isEmpty else { return false }
        return grandparent.bundledAttributes?.contains(attrWithSuffix) == true ||
               grandparent.enumeratedAttributes?.contains(attrWithSuffix) == true
    }

    /// Whether this node has any outline (for external padding)
    static func hasAnyOutline(for node: TreeNode) -> Bool {
        outerOutlineColor(for: node) != .clear || innerOutlineColor(for: node) != .clear
    }
}

// MARK: - Color Helpers

extension NodeAIReviewModeDetector {
    /// Outer outline color (containsSolo - orange)
    /// Checks aiStatusChildren directly since aiMode may return bundle/iterate first
    static func outerOutlineColor(for node: TreeNode) -> SwiftUI.Color {
        if node.aiStatusChildren > 0 {
            return .orange.opacity(0.5)
        }
        return .clear
    }

    /// Inner outline color (entry under reviewed collection - purple/cyan)
    static func innerOutlineColor(for node: TreeNode) -> SwiftUI.Color {
        guard isEntryUnderReviewedCollection(node), let parent = node.parent else { return .clear }
        let hasBundled = parent.bundledAttributes?.isEmpty == false
        let hasEnumerated = parent.enumeratedAttributes?.isEmpty == false

        // Mixed mode: cyan outline (purple shown via background)
        if hasBundled && hasEnumerated {
            return .cyan.opacity(0.5)
        }
        // Single mode: outline matches the mode
        if hasBundled {
            return .purple.opacity(0.5)
        } else if hasEnumerated {
            return .cyan.opacity(0.5)
        }
        return .clear
    }

    /// Background color for the entire row based on AI review mode
    static func rowBackgroundColor(for node: TreeNode, showAIModeIndicator: Bool) -> SwiftUI.Color {
        // Entry nodes under mixed mode collections get purple background (checked before showAIModeIndicator)
        if isEntryUnderReviewedCollection(node) {
            if let parent = node.parent,
               parent.bundledAttributes?.isEmpty == false,
               parent.enumeratedAttributes?.isEmpty == false {
                return .purple.opacity(0.15)  // Mixed mode: purple background
            }
            return .clear  // Single mode: outline only
        }

        guard showAIModeIndicator else { return .clear }

        // Container enumerate nodes get icon only, no background (children are the revnodes)
        if isContainerEnumerateNode(node) {
            return .clear
        }

        // Collection nodes with mixed mode get purple background
        if node.isCollectionNode && hasMixedModes(node) {
            return .purple.opacity(0.15)
        }
        // Collection nodes with single mode get no background (icon only)
        if node.isCollectionNode && (node.bundledAttributes?.isEmpty == false || node.enumeratedAttributes?.isEmpty == false) {
            return .clear
        }

        // Array attribute nodes with [] suffix get icon only, no background (children are the revnodes)
        // e.g., highlights when work[].highlights[] is configured
        if isAttributeOfCollectionEntry(node) && isIterateArrayAttribute(node) {
            return .clear
        }

        let mode = displayMode(for: node)
        guard mode != .off else { return .clear }
        return mode.color.opacity(0.15)
    }
}
