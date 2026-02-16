//
//  PhaseReviewManager.swift
//  Sprung
//
//  Builds the manifest-driven multi-phase review structure from TreeNode state.
//  Phase execution is handled by RevisionWorkflowOrchestrator + CustomizationParallelExecutor.
//

// MARK: - AI Review System Architecture
//
// TreeNode is the SINGLE SOURCE OF TRUTH for AI review configuration.
// Manifest patterns provide INITIAL DEFAULTS; users can modify via UI.
//
// ExperienceDefaultsToTree.applyDefaultAIFields() parses manifest patterns
// and sets TreeNode state:
//
// | Pattern                    | TreeNode Effect                                      |
// |----------------------------|------------------------------------------------------|
// | skills.*.name              | skills.bundledAttributes = ["name"]                  |
// | skills.*.(name, keywords)  | skills.bundledAttributes = ["name", "keywords"]      |
// |                            | → 1 RevNode with serialized JSON object              |
// | skills[].keywords          | skills.enumeratedAttributes = ["keywords"]           |
// | skills[name, keywords]     | skills.enumeratedAttributes = ["name", "keywords"]   |
// |                            | → per-entry compounds (multi-attr iterate)           |
// | custom.jobTitles           | jobTitles.status = .aiToReplace (solo container)     |
// | custom.objective           | objective.status = .aiToReplace (scalar)             |
//
// Each TreeNode stores:
// - `bundledAttributes: [String]?` -- Attributes bundled into 1 RevNode
// - `enumeratedAttributes: [String]?` -- Attributes as N separate RevNodes
// - `status == .aiToReplace` -- Node is selected for AI review
//
// buildReviewManifest() walks the tree and reads TreeNode state:
//
// 1. For nodes with `bundledAttributes`:
//    -> Single attr: Generate pattern like "skills.*.name" -> 1 bundled RevNode
//    -> Multi attr: exportSectionAsObject() -> 1 RevNode with serialized JSON object
//
// 2. For nodes with `enumeratedAttributes`:
//    -> Generate pattern like "skills[].keywords"
//    -> Export via TreeNode.exportNodesMatchingPath() -> Phase 2 RevNodes
//
// 3. For container nodes where all children are aiToReplace:
//    -> Generate pattern like "custom.jobTitles[]"
//    -> Export as container enumerate -> Phase 2 RevNodes
//
// 4. For nodes with aiToReplace (leaf or container, no bundle/enumerate):
//    -> Export directly -> Phase 2 RevNodes
//    -> Container nodes export as one RevNode with childValues
//
// Pattern Syntax:
// | Symbol | Meaning                 | Result                              |
// |--------|-------------------------|-------------------------------------|
// | *      | Bundle all children     | 1 RevNode with all values combined  |
// | []     | Iterate children        | N RevNodes, one per child           |
// | .name  | Navigate to field       | Match specific attribute            |
//
// Node Assignment:
// - Auto nodes: phaseAssignment key present (skill categories, titles — auto-applied)
// - Review nodes: everything else (single human review pass)
//
// Auto nodes are executed and applied before review nodes, so review
// tasks can reference updated names (e.g., keywords under renamed skills).

import Foundation
import SwiftUI

/// Builds the manifest-driven multi-phase review structure from TreeNode state.
/// Phase execution is handled by RevisionWorkflowOrchestrator.
@MainActor
@Observable
class PhaseReviewManager {

    // MARK: - Phase Detection

    /// Build the review manifest from TreeNode state.
    ///
    /// TreeNode is the single source of truth for AI review configuration:
    /// - `bundledAttributes`: Attributes to bundle into 1 RevNode
    /// - `enumeratedAttributes`: Attributes to enumerate as N RevNodes
    /// - `status == .aiToReplace`: Scalar nodes or container items to review
    ///
    /// Phase assignments from `resume.phaseAssignments` determine which nodes
    /// are auto-applied (skill categories, titles) vs. human-reviewed.
    /// Auto nodes: phase assignment key present → executed and auto-applied before main tasks.
    /// Review nodes: everything else → single human review pass.
    func buildReviewManifest(for resume: Resume) -> (autoNodes: [ExportedReviewNode], reviewNodes: [ExportedReviewNode]) {
        guard let rootNode = resume.rootNode else {
            Logger.warning("[buildReviewRounds] No rootNode")
            return ([], [])
        }

        var autoNodes: [ExportedReviewNode] = []
        var reviewNodes: [ExportedReviewNode] = []
        var processedPaths = Set<String>()

        // Phase assignments: key exists = auto-apply, absent = human review
        let autoKeys = Set(resume.phaseAssignments.keys)

        /// Determine if a section+attribute combo is auto-applied or human-reviewed
        func isAuto(section: String, attr: String) -> Bool {
            let groupKey = "\(section)-\(attr)"
            return autoKeys.contains(groupKey)
        }

        /// Add nodes to appropriate list
        func addToManifest(_ nodes: [ExportedReviewNode], auto: Bool, pattern: String) {
            if auto {
                autoNodes.append(contentsOf: nodes)
                Logger.debug("[buildReviewManifest] '\(pattern)' -> \(nodes.count) auto nodes")
            } else {
                reviewNodes.append(contentsOf: nodes)
                Logger.debug("[buildReviewManifest] '\(pattern)' -> \(nodes.count) review nodes")
            }
        }

        // Walk tree and collect patterns from TreeNode state
        func processNode(_ node: TreeNode, parentPath: String, sectionName: String) {
            let nodeName = node.name.isEmpty ? node.value : node.name
            let currentPath = parentPath.isEmpty ? nodeName : "\(parentPath).\(nodeName)"
            // Capitalize section name to match manifest key format (e.g., "Skills-name")
            let currentSection = (sectionName.isEmpty ? nodeName : sectionName).capitalized

            // Check for collection patterns (bundled/enumerated attributes)
            if let bundled = node.bundledAttributes, !bundled.isEmpty {
                let simpleAttrs = bundled.filter { $0 != "*" && !$0.hasSuffix("[]") }
                let isMultiAttrBundle = simpleAttrs.count > 1

                if isMultiAttrBundle {
                    // Multi-attribute bundle → 1 single RevNode with the full serialized section object.
                    // All attributes per entry are serialized together, preserving order.
                    // Auto if ALL attributes are auto; otherwise review (since any review attr needs human eyes).
                    let pattern = "\(currentPath).*"
                    if !processedPaths.contains(pattern) {
                        processedPaths.insert(pattern)
                        let nodes = TreeNode.exportSectionAsObject(
                            sectionPath: currentPath,
                            attributes: simpleAttrs,
                            from: rootNode
                        )
                        let allAuto = simpleAttrs.allSatisfy { isAuto(section: currentSection, attr: $0) }
                        addToManifest(nodes, auto: allAuto, pattern: pattern)
                    }
                } else {
                    // Single attribute (or "*"): existing bundle behavior — 1 bundled ExportedReviewNode
                    for attr in bundled {
                        let pattern = attr == "*"
                            ? "\(currentPath).*"
                            : "\(currentPath).*.\(attr)"
                        if !processedPaths.contains(pattern) {
                            processedPaths.insert(pattern)
                            let nodes = TreeNode.exportNodesMatchingPath(pattern, from: rootNode)
                            let auto = isAuto(section: currentSection, attr: attr)
                            addToManifest(nodes, auto: auto, pattern: pattern)
                        }
                    }
                }
            }

            if let enumerated = node.enumeratedAttributes, !enumerated.isEmpty {
                // Expand "*" wildcard for object collections
                var iterateAttrs: [String]
                if enumerated == ["*"] {
                    if let firstEntry = node.orderedChildren.first, !firstEntry.orderedChildren.isEmpty {
                        // Object collection: expand to all attribute names
                        iterateAttrs = firstEntry.orderedChildren.compactMap {
                            let n = $0.name.isEmpty ? $0.displayLabel : $0.name
                            return n.isEmpty ? nil : n
                        }
                    } else {
                        iterateAttrs = [] // Flat container: handled by container enumerate block below
                    }
                } else {
                    iterateAttrs = enumerated.filter { $0 != "*" }
                }

                // Group by auto/review, then export
                let attrsByAuto = Dictionary(grouping: iterateAttrs) { isAuto(section: currentSection, attr: $0) }

                for (auto, attrs) in attrsByAuto {
                    let isMultiAttr = attrs.count > 1
                    if isMultiAttr {
                        Logger.debug("[buildReviewManifest] Multi-attribute iterate: \(currentPath)[\(attrs.joined(separator: ", "))]")
                    }
                    for attr in attrs {
                        let pattern = "\(currentPath)[].\(attr)"
                        guard !processedPaths.contains(pattern) else { continue }
                        processedPaths.insert(pattern)
                        var nodes = TreeNode.exportNodesMatchingPath(pattern, from: rootNode)
                        if isMultiAttr {
                            nodes = nodes.map { $0.withMultiAttributeFlag() }
                        }
                        addToManifest(nodes, auto: auto, pattern: pattern)
                    }
                }
            }

            // Check for container enumerate (enumeratedAttributes contains "*")
            // Only applies to flat containers (entries without sub-attributes).
            if node.enumeratedAttributes?.contains("*") == true {
                let isObjectCollection = node.orderedChildren.first.map { !$0.orderedChildren.isEmpty } ?? false
                if !isObjectCollection {
                    let pattern = "\(currentPath)[]"
                    if !processedPaths.contains(pattern) {
                        processedPaths.insert(pattern)
                        let nodes = TreeNode.exportNodesMatchingPath(pattern, from: rootNode)
                        let auto = isAuto(section: currentSection, attr: "*")
                        addToManifest(nodes, auto: auto, pattern: pattern)
                    }
                }
            }

            // Check for AI-enabled leaf or container node (no bundle/enumerate attributes)
            let isAIMarked = node.status == .aiToReplace &&
                             node.bundledAttributes == nil &&
                             node.enumeratedAttributes == nil

            if isAIMarked && !processedPaths.contains(currentPath) {
                processedPaths.insert(currentPath)
                let nodes = TreeNode.exportNodesMatchingPath(currentPath, from: rootNode)
                let auto = isAuto(section: currentSection, attr: nodeName)
                addToManifest(nodes, auto: auto, pattern: currentPath)
            }

            // Recurse into children
            for child in node.orderedChildren {
                processNode(child, parentPath: currentPath, sectionName: currentSection)
            }
        }

        // Start from root's children (skip root itself)
        for section in rootNode.orderedChildren {
            processNode(section, parentPath: "", sectionName: "")
        }

        Logger.info("Review manifest: \(autoNodes.count) auto nodes, \(reviewNodes.count) review nodes")
        return (autoNodes, reviewNodes)
    }
}
