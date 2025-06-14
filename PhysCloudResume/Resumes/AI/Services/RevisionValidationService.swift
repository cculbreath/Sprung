// PhysCloudResume/Resumes/AI/Services/RevisionValidationService.swift

import Foundation

class RevisionValidationService {
    
    // MARK: - Validation Methods
    
    func validateRevisions(_ revisions: [ProposedRevisionNode], for resume: Resume) -> [ProposedRevisionNode] {
        Logger.debug("🔍 Validating \(revisions.count) revisions")
        
        var validRevisions = revisions
        let updateNodes = resume.getUpdatableNodes()
        
        // Filter out revisions for nodes that no longer exist
        validRevisions = filterNonExistentNodes(validRevisions, in: resume)
        
        // Validate and fix revision node content
        validRevisions = fixRevisionNodeContent(validRevisions, updateNodes: updateNodes, resume: resume)
        
        Logger.debug("✅ Validated revisions: \(validRevisions.count) (from \(revisions.count))")
        return validRevisions
    }
    
    // MARK: - Private Helper Methods
    
    private func filterNonExistentNodes(_ revisions: [ProposedRevisionNode], in resume: Resume) -> [ProposedRevisionNode] {
        let currentNodeIds = Set(resume.nodes.map { $0.id })
        let initialCount = revisions.count
        
        let filteredRevisions = revisions.filter { revNode in
            let exists = currentNodeIds.contains(revNode.id)
            if !exists {
                Logger.debug("⚠️ Filtering out revision for non-existent node: \(revNode.id)")
            }
            return exists
        }
        
        if filteredRevisions.count < initialCount {
            Logger.debug("🔍 Removed \(initialCount - filteredRevisions.count) revisions for non-existent nodes")
        }
        
        return filteredRevisions
    }
    
    private func fixRevisionNodeContent(
        _ revisions: [ProposedRevisionNode],
        updateNodes: [[String: Any]],
        resume: Resume
    ) -> [ProposedRevisionNode] {
        var validRevisions = revisions
        
        for (index, item) in validRevisions.enumerated() {
            // Find matching node by ID
            let nodesWithSameId = updateNodes.filter { $0["id"] as? String == item.id }
            
            if !nodesWithSameId.isEmpty {
                if let matchedNode = findBestMatchingNode(for: item, in: nodesWithSameId) {
                    validRevisions[index] = updateRevisionWithMatchedNode(
                        validRevisions[index],
                        matchedNode: matchedNode
                    )
                }
            }
            // Last resort: find by tree path
            else if !item.treePath.isEmpty {
                if let match = findNodeByTreePath(item.treePath, in: updateNodes) {
                    validRevisions[index] = updateRevisionWithTreePathMatch(
                        validRevisions[index],
                        match: match
                    )
                }
            }
            
            // Final fallback: direct node lookup
            if validRevisions[index].oldValue.isEmpty && !validRevisions[index].id.isEmpty {
                if let treeNode = resume.nodes.first(where: { $0.id == validRevisions[index].id }) {
                    validRevisions[index] = updateRevisionWithTreeNode(
                        validRevisions[index],
                        treeNode: treeNode
                    )
                }
            }
        }
        
        return validRevisions
    }
    
    private func findBestMatchingNode(
        for revision: ProposedRevisionNode,
        in nodesWithSameId: [[String: Any]]
    ) -> [String: Any]? {
        var matchedNode: [String: Any]?
        
        // Handle multiple nodes with same ID (title vs value)
        if nodesWithSameId.count > 1 {
            // Try to match by content first
            if !revision.oldValue.isEmpty {
                matchedNode = nodesWithSameId.first { node in
                    let nodeValue = node["value"] as? String ?? ""
                    let nodeName = node["name"] as? String ?? ""
                    return nodeValue == revision.oldValue || nodeName == revision.oldValue
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
        
        return matchedNode
    }
    
    private func findNodeByTreePath(_ treePath: String, in updateNodes: [[String: Any]]) -> [String: Any]? {
        let components = treePath.components(separatedBy: " > ")
        if components.count > 1 {
            let potentialMatches = updateNodes.filter { node in
                let nodePath = node["tree_path"] as? String ?? ""
                return nodePath == treePath || nodePath.hasSuffix(treePath)
            }
            return potentialMatches.first
        }
        return nil
    }
    
    private func updateRevisionWithMatchedNode(
        _ revision: ProposedRevisionNode,
        matchedNode: [String: Any]
    ) -> ProposedRevisionNode {
        var updatedRevision = revision
        
        if updatedRevision.oldValue.isEmpty {
            let isTitleNode = matchedNode["isTitleNode"] as? Bool ?? false
            if isTitleNode {
                updatedRevision.oldValue = matchedNode["name"] as? String ?? ""
            } else {
                updatedRevision.oldValue = matchedNode["value"] as? String ?? ""
            }
            updatedRevision.isTitleNode = isTitleNode
        } else {
            updatedRevision.isTitleNode = matchedNode["isTitleNode"] as? Bool ?? false
        }
        
        return updatedRevision
    }
    
    private func updateRevisionWithTreePathMatch(
        _ revision: ProposedRevisionNode,
        match: [String: Any]
    ) -> ProposedRevisionNode {
        var updatedRevision = revision
        
        updatedRevision.id = match["id"] as? String ?? revision.id
        let isTitleNode = match["isTitleNode"] as? Bool ?? false
        if isTitleNode {
            updatedRevision.oldValue = match["name"] as? String ?? ""
        } else {
            updatedRevision.oldValue = match["value"] as? String ?? ""
        }
        updatedRevision.isTitleNode = isTitleNode
        
        return updatedRevision
    }
    
    private func updateRevisionWithTreeNode(
        _ revision: ProposedRevisionNode,
        treeNode: TreeNode
    ) -> ProposedRevisionNode {
        var updatedRevision = revision
        
        if updatedRevision.isTitleNode {
            updatedRevision.oldValue = treeNode.name
        } else {
            updatedRevision.oldValue = treeNode.value
        }
        
        return updatedRevision
    }
}