//
//  PhaseReviewRoundBuilder.swift
//  Sprung
//
//  Builds the two-round review node arrays from the Resume's TreeNode tree.
//  Pure tree-walking logic with no LLM or UI dependencies.
//

import Foundation

/// Builds the two-round review node arrays from the Resume's TreeNode tree.
struct PhaseReviewRoundBuilder {

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
            Logger.warning("\u{26a0}\u{fe0f} [buildReviewRounds] No rootNode")
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
                Logger.debug("\u{1f4cb} [buildReviewRounds] '\(pattern)' \u{2192} \(nodes.count) Phase 1 RevNodes")
            } else {
                phase2Nodes.append(contentsOf: nodes)
                Logger.debug("\u{1f4cb} [buildReviewRounds] '\(pattern)' \u{2192} \(nodes.count) Phase 2 RevNodes")
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
                    // Multi-attribute bundle -> 1 single RevNode with the full serialized section object.
                    let pattern = "\(currentPath).*"
                    if !processedPaths.contains(pattern) {
                        processedPaths.insert(pattern)
                        let nodes = TreeNode.exportSectionAsObject(
                            sectionPath: currentPath,
                            attributes: simpleAttrs,
                            from: rootNode
                        )
                        let allPhase1 = simpleAttrs.allSatisfy { phaseFor(section: currentSection, attr: $0) == 1 }
                        addToPhase(nodes, phase: allPhase1 ? 1 : 2, pattern: pattern)
                    }
                } else {
                    // Single attribute (or "*"): existing bundle behavior -- 1 bundled ExportedReviewNode
                    for attr in bundled {
                        let pattern = attr == "*"
                            ? "\(currentPath).*"
                            : "\(currentPath).*.\(attr)"
                        if !processedPaths.contains(pattern) {
                            processedPaths.insert(pattern)
                            let nodes = TreeNode.exportNodesMatchingPath(pattern, from: rootNode)
                            let phase = phaseFor(section: currentSection, attr: attr)
                            addToPhase(nodes, phase: phase, pattern: pattern)
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

                // Group by phase, then export
                let attrsByPhase = Dictionary(grouping: iterateAttrs) { phaseFor(section: currentSection, attr: $0) }

                for (phase, attrs) in attrsByPhase {
                    let isMultiAttr = attrs.count > 1
                    for attr in attrs {
                        let pattern = "\(currentPath)[].\(attr)"
                        guard !processedPaths.contains(pattern) else { continue }
                        processedPaths.insert(pattern)
                        var nodes = TreeNode.exportNodesMatchingPath(pattern, from: rootNode)
                        if isMultiAttr {
                            nodes = nodes.map { $0.withMultiAttributeFlag() }
                        }
                        addToPhase(nodes, phase: phase, pattern: pattern)
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
                        let phase = phaseFor(section: currentSection, attr: "*")
                        addToPhase(nodes, phase: phase, pattern: pattern)
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
                let phase = phaseFor(section: currentSection, attr: nodeName)
                addToPhase(nodes, phase: phase, pattern: currentPath)
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

        Logger.info("\u{1f4cb} Review rounds: Phase 1 has \(phase1Nodes.count) nodes, Phase 2 has \(phase2Nodes.count) nodes")
        return (phase1Nodes, phase2Nodes)
    }
}
