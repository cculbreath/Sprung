//
//  NodeAIReviewModeDetector.swift
//  Sprung
//
//  Detects AI review modes for tree nodes.
//  Provides utility functions for determining collection relationships.
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
    /// - bundledAttributes["name"] -> purple (all combined)
    /// - enumeratedAttributes["name"] -> cyan (each separate)
    /// For array attributes (has children):
    /// - *Attributes["keywords"] -> purple (bundled together)
    /// - *Attributes["keywords[]"] -> cyan (each item separate)
    static func attributeMode(for node: TreeNode) -> AIReviewMode {
        guard let grandparent = grandparentNode(of: node) else { return .off }
        let attr = attributeName(of: node)
        let attrWithSuffix = attr + "[]"
        let isArrayAttribute = !node.orderedChildren.isEmpty

        if isArrayAttribute {
            // Array attribute: check for [] suffix to determine mode
            // With [] suffix = each item separate (iterate)
            if grandparent.bundledAttributes?.contains(attrWithSuffix) == true ||
               grandparent.enumeratedAttributes?.contains(attrWithSuffix) == true {
                return .iterate
            }
            // Without [] suffix = bundled together
            if grandparent.bundledAttributes?.contains(attr) == true ||
               grandparent.enumeratedAttributes?.contains(attr) == true {
                return .bundle
            }
        } else {
            // Scalar attribute: enumeratedAttributes = iterate, bundledAttributes = bundle
            if grandparent.enumeratedAttributes?.contains(attr) == true {
                return .iterate
            }
            if grandparent.bundledAttributes?.contains(attr) == true {
                return .bundle
            }
        }

        if node.status == .aiToReplace {
            return .solo
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

    /// The mode to display for this node
    static func displayMode(for node: TreeNode) -> AIReviewMode {
        // Container enumerate node (e.g., jobTitles with enumeratedAttributes["*"])
        if isContainerEnumerateNode(node) {
            return .iterate
        }
        // Container enumerate children get iterate mode
        if isContainerEnumerateChild(node) {
            return .iterate
        }
        // Check if this is a child of a reviewed container first
        if isChildOfReviewedContainer(node) {
            return .included
        }
        // Entry under reviewed collection
        if isEntryUnderReviewedCollection(node) {
            return .included
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
}
