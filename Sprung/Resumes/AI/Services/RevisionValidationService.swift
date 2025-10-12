//
//  RevisionValidationService.swift
//  Sprung
//

import Foundation

/// Service responsible for validating and matching revision nodes against resume state
/// Handles complex node matching by ID, content, and tree path
@MainActor
class RevisionValidationService {

    /// Validate revisions against current resume state
    /// Filters out non-existent nodes and ensures correct node identification
    /// - Parameters:
    ///   - revisions: The revisions to validate
    ///   - resume: The current resume state
    /// - Returns: Validated and corrected revisions
    func validateRevisions(_ revisions: [ProposedRevisionNode], for resume: Resume) -> [ProposedRevisionNode] {
        Logger.debug("🔍 Validating \(revisions.count) revisions")

        var validRevisions = revisions
        let updateNodes = resume.getUpdatableNodes()

        // Filter out revisions for nodes that no longer exist
        let currentNodeIds = Set(resume.nodes.map { $0.id })
        let initialCount = validRevisions.count
        validRevisions = validRevisions.filter { revNode in
            let exists = currentNodeIds.contains(revNode.id)
            if !exists {
                Logger.debug("⚠️ Filtering out revision for non-existent node: \(revNode.id)")
            }
            return exists
        }

        if validRevisions.count < initialCount {
            Logger.debug("🔍 Removed \(initialCount - validRevisions.count) revisions for non-existent nodes")
        }

        // Validate and fix revision node content
        for (index, item) in validRevisions.enumerated() {
            // Find matching node by ID
            let nodesWithSameId = updateNodes.filter { $0["id"] as? String == item.id }

            if !nodesWithSameId.isEmpty {
                var matchedNode: [String: Any]?

                // Handle multiple nodes with same ID (title vs value)
                if nodesWithSameId.count > 1 {
                    // Try to match by content first
                    if !item.oldValue.isEmpty {
                        matchedNode = nodesWithSameId.first { node in
                            let nodeValue = node["value"] as? String ?? ""
                            let nodeName = node["name"] as? String ?? ""
                            return nodeValue == item.oldValue || nodeName == item.oldValue
                        }
                    }

                    // Fallback to title node preference
                    if matchedNode == nil {
                        matchedNode = nodesWithSameId.first { node in
                            node["isTitleNode"] as? Bool == true
                        } ?? nodesWithSameId.first
                    }
                } else {
                    matchedNode = nodesWithSameId.first
                }

                // Update revision with correct values
                if let matchedNode = matchedNode {
                    if validRevisions[index].oldValue.isEmpty {
                        let isTitleNode = matchedNode["isTitleNode"] as? Bool ?? false
                        if isTitleNode {
                            validRevisions[index].oldValue = matchedNode["name"] as? String ?? ""
                        } else {
                            validRevisions[index].oldValue = matchedNode["value"] as? String ?? ""
                        }
                        validRevisions[index].isTitleNode = isTitleNode
                    } else {
                        validRevisions[index].isTitleNode = matchedNode["isTitleNode"] as? Bool ?? false
                    }
                }
            }

            // Last resort: find by tree path
            else if !item.treePath.isEmpty {
                let treePath = item.treePath
                let components = treePath.components(separatedBy: " > ")
                if components.count > 1 {
                    let potentialMatches = updateNodes.filter { node in
                        let nodePath = node["tree_path"] as? String ?? ""
                        return nodePath == treePath || nodePath.hasSuffix(treePath)
                    }

                    if let match = potentialMatches.first {
                        validRevisions[index].id = match["id"] as? String ?? item.id
                        let isTitleNode = match["isTitleNode"] as? Bool ?? false
                        if isTitleNode {
                            validRevisions[index].oldValue = match["name"] as? String ?? ""
                        } else {
                            validRevisions[index].oldValue = match["value"] as? String ?? ""
                        }
                        validRevisions[index].isTitleNode = isTitleNode
                    }
                }
            }

            // Final fallback: direct node lookup
            if validRevisions[index].oldValue.isEmpty && !validRevisions[index].id.isEmpty {
                if let treeNode = resume.nodes.first(where: { $0.id == validRevisions[index].id }) {
                    if validRevisions[index].isTitleNode {
                        validRevisions[index].oldValue = treeNode.name
                    } else {
                        validRevisions[index].oldValue = treeNode.value
                    }
                }
            }
        }

        Logger.debug("✅ Validated revisions: \(validRevisions.count) (from \(revisions.count))")
        return validRevisions
    }
}
