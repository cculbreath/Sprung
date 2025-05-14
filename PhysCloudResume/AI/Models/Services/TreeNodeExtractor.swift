//
//  TreeNodeExtractor.swift
//  PhysCloudResume
//
//  Created by Team on 5/13/25.
//

import Foundation
import PDFKit
import AppKit
import SwiftUI

/// Service for extracting and manipulating tree nodes
class TreeNodeExtractor {
    /// Shared instance of the service
    static let shared = TreeNodeExtractor()
    
    private init() {}
    
    /// Extracts "Skills and Expertise" nodes into a JSON string format for the LLM.
    /// - Parameter resume: The resume to extract skills from.
    /// - Returns: A JSON string representing the skills and expertise, or nil if an error occurs.
    func extractSkillsForLLM(resume: Resume) -> String? {
        // First, ensure the resume has a rootNode.
        guard let actualRootNode = resume.rootNode else {
            Logger.debug("Error: Resume has no rootNode.")
            return nil
        }

        // Attempt to find the "Skills and Expertise" section node.
        var skillsSectionNode: TreeNode? = actualRootNode.children?.first(where: {
            $0.name.lowercased() == "skills-and-expertise" || $0.name.lowercased() == "skills and expertise"
        })

        // If not found with primary names, try the fallback key.
        if skillsSectionNode == nil {
            skillsSectionNode = actualRootNode.children?.first(where: { $0.name == "skills-and-expertise" })
        }

        // If still not found after both attempts, print an error and return nil.
        guard let finalSkillsSectionNode = skillsSectionNode else {
            Logger.debug("Error: 'Skills and Expertise' section node not found in the resume under rootNode.")
            return nil
        }

        return extractTreeNodesForLLM(parentNode: finalSkillsSectionNode)
    }

    /// Extracts tree nodes into a JSON string format for the LLM.
    /// - Parameter parentNode: The parent node to extract children from.
    /// - Returns: A JSON string or nil if an error occurs.
    private func extractTreeNodesForLLM(parentNode: TreeNode) -> String? {
        var nodesToProcess: [TreeNode] = []

        // We only want to process the direct children of the "Skills and Expertise" section node,
        // as these are the individual skills or skill categories.
        parentNode.children?.forEach { childNode in
            // If a child node itself has children (e.g. a category with bullet points),
            // we add the category node (title) and then its children (values).
            if childNode.hasChildren {
                if childNode.includeInEditor || !childNode.name.isEmpty { // Add the category title node
                    nodesToProcess.append(childNode)
                }
                childNode.children?.forEach { subChildNode in // Add its children (skill details)
                    if subChildNode.includeInEditor || !subChildNode.value.isEmpty {
                        nodesToProcess.append(subChildNode)
                    }
                }
            } else { // It's a direct skill item
                if childNode.includeInEditor || !childNode.name.isEmpty || !childNode.value.isEmpty {
                    nodesToProcess.append(childNode)
                }
            }
        }

        let exportableNodes: [[String: Any]] = nodesToProcess.compactMap { node in
            let textContent: String
            let isTitle: Bool = node.isTitleNode

            if isTitle {
                guard !node.name.isEmpty else { return nil }
                textContent = node.name
            } else {
                guard !node.value.isEmpty || !node.name.isEmpty else { return nil }
                textContent = !node.value.isEmpty ? node.value : node.name
            }

            return [
                "id": node.id,
                "originalValue": textContent,
                "isTitleNode": isTitle,
                "treePath": node.buildTreePath(),
            ]
        }

        guard !exportableNodes.isEmpty else {
            Logger.debug("Warning: No exportable skill/expertise nodes found under the identified section.")
            return "[]"
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: exportableNodes, options: [.prettyPrinted])
            return String(data: jsonData, encoding: .utf8)
        } catch {
            Logger.debug("Error serializing skills nodes to JSON: \(error)")
            return nil
        }
    }
    
    /// Finds a tree node by its ID
    /// - Parameters:
    ///   - id: The ID of the node to find
    ///   - resume: The resume containing the nodes
    /// - Returns: The TreeNode if found, nil otherwise
    func findTreeNode(byId id: String, in resume: Resume) -> TreeNode? {
        return resume.nodes.first { $0.id == id }
    }
    
    /// Applies the reordering of skills from the LLM response
    /// - Parameters:
    ///   - resume: The resume to update
    ///   - reorderedNodes: The reordered skill nodes from the LLM
    /// - Returns: True if reordering was successful, false otherwise
    func applyReordering(resume: Resume, reorderedNodes: [ReorderedSkillNode]) -> Bool {
        // First, ensure the resume has a rootNode
        guard let actualRootNode = resume.rootNode else {
            Logger.debug("Error: Resume has no rootNode.")
            return false
        }

        // Find the "Skills and Expertise" section node
        var skillsSectionNode: TreeNode? = actualRootNode.children?.first(where: {
            $0.name.lowercased() == "skills-and-expertise" || $0.name.lowercased() == "skills and expertise"
        })

        // If not found with primary names, try the fallback key
        if skillsSectionNode == nil {
            skillsSectionNode = actualRootNode.children?.first(where: { $0.name == "skills-and-expertise" })
        }

        // If still not found, return false
        guard let finalSkillsSectionNode = skillsSectionNode else {
            Logger.debug("Error: 'Skills and Expertise' section node not found in the resume.")
            return false
        }

        // Create a dictionary mapping node id to its new position
        let positionMap = Dictionary(uniqueKeysWithValues: reorderedNodes.map { ($0.id, $0.newPosition) })
        
        // Create a list of nodes to reorder with their new positions
        var nodesToReorder: [(node: TreeNode, newPosition: Int)] = []
        
        // We need to handle different levels separately
        // First, get all direct children of the skills section
        if let directChildren = finalSkillsSectionNode.children {
            for child in directChildren {
                if let newPosition = positionMap[child.id] {
                    nodesToReorder.append((child, newPosition))
                }
                
                // If this child has its own children (like a skill category with bullet points)
                // We need to handle those too, but separately since they're at a different level
                if let subChildren = child.children {
                    var subNodesToReorder: [(node: TreeNode, newPosition: Int)] = []
                    for subChild in subChildren {
                        if let newPosition = positionMap[subChild.id] {
                            subNodesToReorder.append((subChild, newPosition))
                        }
                    }
                    
                    // Only apply reordering if we found nodes to reorder at this level
                    if !subNodesToReorder.isEmpty {
                        // Sort by new position
                        let sortedSubNodes = subNodesToReorder.sorted { $0.newPosition < $1.newPosition }
                        
                        // Update myIndex values
                        for (index, nodeInfo) in sortedSubNodes.enumerated() {
                            nodeInfo.node.myIndex = index
                        }
                        
                        // Ensure changes are saved
                        if let modelContext = child.resume.modelContext {
                            do {
                                try modelContext.save()
                            } catch {
                                Logger.debug("Error saving model context after reordering sub-nodes: \(error)")
                                return false
                            }
                        }
                    }
                }
            }
        }
        
        // Only apply top-level reordering if we found nodes to reorder
        if !nodesToReorder.isEmpty {
            // Sort by new position
            let sortedNodes = nodesToReorder.sorted { $0.newPosition < $1.newPosition }
            
            // Update myIndex values
            for (index, nodeInfo) in sortedNodes.enumerated() {
                nodeInfo.node.myIndex = index
            }
            
            // Ensure changes are saved
            if let modelContext = finalSkillsSectionNode.resume.modelContext {
                do {
                    try modelContext.save()
                } catch {
                    Logger.debug("Error saving model context after reordering: \(error)")
                    return false
                }
            }
        }
        
        return !nodesToReorder.isEmpty
    }
}
