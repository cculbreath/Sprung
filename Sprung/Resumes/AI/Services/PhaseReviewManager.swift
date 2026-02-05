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
// | Pattern           | TreeNode Effect                                      |
// |-------------------|------------------------------------------------------|
// | skills.*.name     | skills.bundledAttributes = ["name"]                  |
// | skills[].keywords | skills.enumeratedAttributes = ["keywords"]           |
// | custom.jobTitles[]| jobTitles.status = .aiToReplace, children marked     |
// | custom.objective  | objective.status = .aiToReplace (scalar)             |
//
// Each TreeNode stores:
// - `bundledAttributes: [String]?` -- Attributes bundled into 1 RevNode (Phase 1)
// - `enumeratedAttributes: [String]?` -- Attributes as N separate RevNodes (Phase 2)
// - `status == .aiToReplace` -- Node is selected for AI review
//
// buildReviewRounds() walks the tree and reads TreeNode state:
//
// 1. For nodes with `bundledAttributes`:
//    -> Generate pattern like "skills.*.name"
//    -> Export via TreeNode.exportNodesMatchingPath() -> Phase 1 RevNodes
//
// 2. For nodes with `enumeratedAttributes`:
//    -> Generate pattern like "skills[].keywords"
//    -> Export via TreeNode.exportNodesMatchingPath() -> Phase 2 RevNodes
//
// 3. For container nodes where all children are aiToReplace:
//    -> Generate pattern like "custom.jobTitles[]"
//    -> Export as container enumerate -> Phase 2 RevNodes
//
// 4. For scalar nodes with aiToReplace and no children:
//    -> Export directly -> Phase 2 RevNodes
//
// Pattern Syntax:
// | Symbol | Meaning                 | Result                              |
// |--------|-------------------------|-------------------------------------|
// | *      | Bundle all children     | 1 RevNode with all values combined  |
// | []     | Iterate children        | N RevNodes, one per child           |
// | .name  | Navigate to field       | Match specific attribute            |
//
// Phase Assignment:
// - Phase 1: bundledAttributes patterns (need holistic review first)
// - Phase 2: Everything else (enumerated, scalars, container enumerates)
//
// Phase 1 changes are applied to tree before Phase 2 export, so Phase 2
// content can reference updated names (e.g., keywords under renamed skills).

import Foundation
import SwiftUI

/// Builds the manifest-driven multi-phase review structure from TreeNode state.
/// Phase execution is handled by RevisionWorkflowOrchestrator.
@MainActor
@Observable
class PhaseReviewManager {

    // MARK: - Phase Detection

    /// Build the two-round review structure from TreeNode state.
    ///
    /// TreeNode is the single source of truth for AI review configuration:
    /// - `bundledAttributes`: Attributes to bundle into 1 RevNode
    /// - `enumeratedAttributes`: Attributes to enumerate as N RevNodes
    /// - `status == .aiToReplace`: Scalar nodes or container items to review
    ///
    /// Phase assignments come from `resume.phaseAssignments` (populated from manifest defaults
    /// at tree creation time, then editable via Phase Assignments panel).
    /// Fallback: bundle=1, enumerate/scalar=2
    func buildReviewRounds(for resume: Resume) -> (phase1: [ExportedReviewNode], phase2: [ExportedReviewNode]) {
        guard let rootNode = resume.rootNode else {
            Logger.warning("[buildReviewRounds] No rootNode")
            return ([], [])
        }

        var phase1Nodes: [ExportedReviewNode] = []
        var phase2Nodes: [ExportedReviewNode] = []
        var processedPaths = Set<String>()

        // Phase assignments: key exists = phase 1, absent = phase 2 (default)
        let phase1Keys = Set(resume.phaseAssignments.keys)

        /// Get phase for a section+attribute combination
        /// Key present in phaseAssignments = phase 1, absent = phase 2
        func phaseFor(section: String, attr: String) -> Int {
            let groupKey = "\(section)-\(attr)"
            return phase1Keys.contains(groupKey) ? 1 : 2
        }

        /// Add nodes to appropriate phase
        func addToPhase(_ nodes: [ExportedReviewNode], phase: Int, pattern: String) {
            if phase == 1 {
                phase1Nodes.append(contentsOf: nodes)
                Logger.debug("[buildReviewRounds] '\(pattern)' -> \(nodes.count) Phase 1 RevNodes")
            } else {
                phase2Nodes.append(contentsOf: nodes)
                Logger.debug("[buildReviewRounds] '\(pattern)' -> \(nodes.count) Phase 2 RevNodes")
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
                for attr in bundled {
                    let pattern = "\(currentPath).*.\(attr)"
                    if !processedPaths.contains(pattern) {
                        processedPaths.insert(pattern)
                        let nodes = TreeNode.exportNodesMatchingPath(pattern, from: rootNode)
                        let phase = phaseFor(section: currentSection, attr: attr)
                        addToPhase(nodes, phase: phase, pattern: pattern)
                    }
                }
            }

            if let enumerated = node.enumeratedAttributes, !enumerated.isEmpty {
                for attr in enumerated {
                    // Skip container enumerate marker
                    guard attr != "*" else { continue }
                    let pattern = "\(currentPath)[].\(attr)"
                    if !processedPaths.contains(pattern) {
                        processedPaths.insert(pattern)
                        let nodes = TreeNode.exportNodesMatchingPath(pattern, from: rootNode)
                        let phase = phaseFor(section: currentSection, attr: attr)
                        addToPhase(nodes, phase: phase, pattern: pattern)
                    }
                }
            }

            // Check for container enumerate (enumeratedAttributes contains "*")
            if node.enumeratedAttributes?.contains("*") == true {
                let pattern = "\(currentPath)[]"
                if !processedPaths.contains(pattern) {
                    processedPaths.insert(pattern)
                    let nodes = TreeNode.exportNodesMatchingPath(pattern, from: rootNode)
                    let phase = phaseFor(section: currentSection, attr: "*")
                    addToPhase(nodes, phase: phase, pattern: pattern)
                }
            }

            // Check for scalar node (no children, AI-enabled)
            let isScalar = node.status == .aiToReplace &&
                           node.orderedChildren.isEmpty &&
                           node.bundledAttributes == nil &&
                           node.enumeratedAttributes == nil

            if isScalar && !processedPaths.contains(currentPath) {
                processedPaths.insert(currentPath)
                let nodes = TreeNode.exportNodesMatchingPath(currentPath, from: rootNode)
                // Scalar nodes default to phase 2
                addToPhase(nodes, phase: 2, pattern: currentPath)
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

        Logger.info("Review rounds: Phase 1 has \(phase1Nodes.count) nodes, Phase 2 has \(phase2Nodes.count) nodes")
        return (phase1Nodes, phase2Nodes)
    }
}
