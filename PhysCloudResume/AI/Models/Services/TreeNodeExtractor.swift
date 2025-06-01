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
    
    /// Extracts minimal "Skills and Expertise" nodes data (just id, name, and order) for reordering operations
    /// - Parameter resume: The resume to extract skills from.
    /// - Returns: A JSON string representing the skills with minimal data, or nil if an error occurs.
    func extractSkillsForReordering(resume: Resume) -> String? {
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
        
        // Same node collection logic as extractTreeNodesForLLM but simplified extraction
        var nodesToProcess: [TreeNode] = []

        // We only want to process the direct children of the "Skills and Expertise" section node,
        // as these are the individual skills or skill categories.
        finalSkillsSectionNode.children?.forEach { childNode in
            // If a child node itself has children (e.g. a category with bullet points),
            // we add the category node (title) and then its children (values).
            if childNode.hasChildren {
                if childNode.includeInEditor || !childNode.name.isEmpty { // Add the category title node
                    nodesToProcess.append(childNode)
                }
                childNode.children?.forEach { subChildNode in // Add its children (skill details)
                    if subChildNode.includeInEditor || !subChildNode.name.isEmpty {
                        nodesToProcess.append(subChildNode)
                    }
                }
            } else { // It's a direct skill item
                if childNode.includeInEditor || !childNode.name.isEmpty {
                    nodesToProcess.append(childNode)
                }
            }
        }
        
        // Create simplified JSON with just id, name and order (myIndex)
        let exportableNodes: [[String: Any]] = nodesToProcess.compactMap { node in
            guard !node.name.isEmpty else { return nil }
            
            return [
                "id": node.id,
                "name": node.name,
                "order": node.myIndex
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
    
    /// Extracts "Skills and Expertise" nodes for fix overflow operation.
    /// Each skill node contains both title and description.
    /// - Parameter resume: The resume to extract skills from.
    /// - Returns: A JSON string representing the skills with both title and description, or nil if an error occurs.
    func extractSkillsForFixOverflow(resume: Resume) -> String? {
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

        var exportableSkills: [[String: Any]] = []

        // Each child of the skills section is a complete skill with title (name) and description (value)
        finalSkillsSectionNode.children?.forEach { skillNode in
            // Skip nodes without both name and value
            guard !skillNode.name.isEmpty else { return }
            
            exportableSkills.append([
                "id": skillNode.id,
                "title": skillNode.name,
                "description": skillNode.value,
                "original_title": skillNode.name,
                "original_description": skillNode.value
            ])
        }

        guard !exportableSkills.isEmpty else {
            Logger.debug("Warning: No exportable skill nodes found under the identified section.")
            return "[]"
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: exportableSkills, options: [.prettyPrinted])
            let jsonString = String(data: jsonData, encoding: .utf8)
            Logger.debug("🔍 extractSkillsForFixOverflow: Generated JSON with \(exportableSkills.count) skills")
            Logger.debug("🔍 extractSkillsForFixOverflow: Sample skill structure: \(exportableSkills.first ?? [:])")
            return jsonString
        } catch {
            Logger.debug("Error serializing skills to JSON: \(error)")
            return nil
        }
    }
    
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

        // Create a dictionary mapping node id to its new position - log what we're getting
        Logger.debug("Applying reordering for \(reorderedNodes.count) nodes")
        for node in reorderedNodes {
            Logger.debug("Node ID: \(node.id), Position: \(node.newPosition), Original Value: \(node.originalValue)")
        }
        
        let positionMap = Dictionary(uniqueKeysWithValues: reorderedNodes.map { ($0.id, $0.newPosition) })
        
        // Create a list of nodes to reorder with their new positions
        var nodesToReorder: [(node: TreeNode, newPosition: Int)] = []
        
        // Let's log the top-level skills nodes we have available
        if let directChildren = finalSkillsSectionNode.children {
            Logger.debug("Available Skills section children (\(directChildren.count) nodes):")
            for (index, child) in directChildren.enumerated() {
                Logger.debug("\(index): ID=\(child.id), Name=\(child.name), Value=\(child.value)")
                if let subChildren = child.children {
                    Logger.debug("  - Has \(subChildren.count) sub-children")
                    for (subIndex, subChild) in subChildren.enumerated() {
                        Logger.debug("    - \(subIndex): ID=\(subChild.id), Name=\(subChild.name), Value=\(subChild.value)")
                    }
                }
            }
        }
        
        // We need to handle different levels separately
        // First, get all direct children of the skills section
        if let directChildren = finalSkillsSectionNode.children {
            for child in directChildren {
                if let newPosition = positionMap[child.id] {
                    Logger.debug("✅ Found node to reorder: \(child.id), current myIndex=\(child.myIndex), newPosition=\(newPosition)")
                    nodesToReorder.append((child, newPosition))
                } else {
                    Logger.debug("⚠️ No position found for node: \(child.id)")
                }
                
                // If this child has its own children (like a skill category with bullet points)
                // We need to handle those too, but separately since they're at a different level
                if let subChildren = child.children {
                    var subNodesToReorder: [(node: TreeNode, newPosition: Int)] = []
                    for subChild in subChildren {
                        if let newPosition = positionMap[subChild.id] {
                            Logger.debug("✅ Found subchild to reorder: \(subChild.id), current myIndex=\(subChild.myIndex), newPosition=\(newPosition)")
                            subNodesToReorder.append((subChild, newPosition))
                        } else {
                            Logger.debug("⚠️ No position found for subchild: \(subChild.id)")
                        }
                    }
                    // Only apply reordering if we found nodes to reorder at this level
                    if !subNodesToReorder.isEmpty {
                        Logger.debug("Reordering \(subNodesToReorder.count) subcategory nodes")
                        
                        // Sort by new position
                        let sortedSubNodes = subNodesToReorder.sorted { $0.newPosition < $1.newPosition }
                        
                        // Display the order change
                        Logger.debug("Sub-level reordering:")
                        for nodeInfo in subNodesToReorder {
                            Logger.debug("Node \(nodeInfo.node.id) moving from \(nodeInfo.node.myIndex) to \(nodeInfo.newPosition)")
                        }
                        
                        // Update myIndex values
                        for (index, nodeInfo) in sortedSubNodes.enumerated() {
                            let oldIndex = nodeInfo.node.myIndex
                            nodeInfo.node.myIndex = index
                            Logger.debug("Updated subnode \(nodeInfo.node.id) myIndex from \(oldIndex) to \(index)")
                        }
                        
                        // Ensure changes are saved
                        if let modelContext = child.resume.modelContext {
                            do {
                                try modelContext.save()
                                Logger.debug("✅ Successfully saved subcategory reordering")
                            } catch {
                                Logger.debug("❌ Error saving model context after reordering sub-nodes: \(error)")
                                return false
                            }
                        } else {
                            Logger.debug("⚠️ No model context available for subcategory")
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
