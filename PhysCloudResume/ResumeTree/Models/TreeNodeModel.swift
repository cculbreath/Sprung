// PhysCloudResume/ResumeTree/Models/TreeNodeModel.swift

import Foundation
import SwiftData

enum LeafStatus: String, Codable, Hashable {
    case isEditing
    case aiToReplace
    case disabled = "leafDisabled"
    case saved = "leafValueSaved"
    case isNotLeaf = "nodeIsNotLeaf"
}

@Model class TreeNode: Identifiable {
    var id = UUID().uuidString
    var name: String = ""
    var value: String
    var includeInEditor: Bool = false
    var myIndex: Int = -1 // Represents order within its parent's children array
    @Relationship(deleteRule: .cascade) var children: [TreeNode]? = nil
    weak var parent: TreeNode?
    var label: String { return resume.label(name) } // Assumes resume.label handles missing keys
    @Relationship(deleteRule: .noAction) var resume: Resume
    var status: LeafStatus
    var depth: Int = 0

    // This property should be explicitly set when a node is created or its role changes.
    // It's not reliably computable based on name/value alone.
    // For the "Fix Overflow" feature, we will pass this to the LLM and expect it back.
    var isTitleNode: Bool = false

    var hasChildren: Bool {
        return !(children?.isEmpty ?? true)
    }

    var orderedChildren: [TreeNode] {
        (children ?? []).sorted { $0.myIndex < $1.myIndex }
    }

    var aiStatusChildren: Int {
        var count = 0
        if status == .aiToReplace {
            count += 1
        }
        if let children = children {
            for child in children {
                count += child.aiStatusChildren
            }
        }
        return count
    }

    init(
        name: String, value: String = "", children: [TreeNode]? = nil,
        parent: TreeNode? = nil, inEditor: Bool, status: LeafStatus = LeafStatus.disabled,
        resume: Resume, isTitleNode: Bool = false // Added isTitleNode to initializer
    ) {
        self.name = name
        self.value = value
        self.children = children
        self.parent = parent
        self.status = status
        includeInEditor = inEditor
        depth = parent != nil ? parent!.depth + 1 : 0
        self.resume = resume
        self.isTitleNode = isTitleNode // Initialize isTitleNode
    }

    @discardableResult
    func addChild(_ child: TreeNode) -> TreeNode {
        if children == nil {
            children = []
        }
        child.parent = self
        child.myIndex = (children?.count ?? 0)
        child.depth = depth + 1
        children?.append(child)
        return child
    }

    static func traverseAndExportNodes(node: TreeNode, currentPath _: String = "")
        -> [[String: Any]]
    {
        var result: [[String: Any]] = []
        let newPath = node.buildTreePath() // Use the instance method

        // Export node if it's marked for AI replacement OR if it's a title node (even if not for replacement, LLM might need context)
        // For "Fix Overflow", we are specifically interested in nodes from the "Skills & Expertise" section,
        // which will be filtered by the caller (extractSkillsForLLM in ResumeReviewService).
        // This function is more general for AI updates.
        if node.status == .aiToReplace {
            // First, handle title node content if present (name field)
            if !node.name.isEmpty { // Always export name field as a title node if it's not empty
                let titleNodeData: [String: Any] = [
                    "id": node.id,
                    "value": node.name, // Exporting node.name as "value" for the LLM
                    "name": node.name, // Also include the actual name field for context
                    "tree_path": newPath, // Path to this node
                    "isTitleNode": true, // Explicitly mark as title node
                ]
                result.append(titleNodeData)
            }

            // Then, handle value node content if present
            if !node.value.isEmpty { // Always export value field as a content node if it's not empty
                let valueNodeData: [String: Any] = [
                    "id": node.id,
                    "value": node.value, // Exporting node.value
                    "name": node.name, // Include name for context/reference
                    "tree_path": newPath,
                    "isTitleNode": false, // Explicitly mark as not a title node
                ]
                result.append(valueNodeData)
            }
        }

        for child in node.children ?? [] {
            // Pass the child's full path for its children's context
            result.append(contentsOf: traverseAndExportNodes(node: child, currentPath: newPath))
        }
        return result
    }

    static func deleteTreeNode(node: TreeNode, context: ModelContext) {
        for child in node.children ?? [] {
            deleteTreeNode(node: child, context: context)
        }
        if let parent = node.parent, let index = parent.children?.firstIndex(of: node) {
            parent.children?.remove(at: index)
        }
        context.delete(node)
        do {
            try context.save()
        } catch {
            Logger.debug("Failed to save context after deleting TreeNode: \(error)")
        }
    }

    /// Builds the hierarchical path string for this node.
    /// Example: "Resume > Skills and Expertise > Software > Swift"
    func buildTreePath() -> String {
        var pathComponents: [String] = []
        var currentNode: TreeNode? = self
        while let node = currentNode {
            var componentName = "Unnamed Node"
            if !node.name.isEmpty {
                componentName = node.name
            } else if !node.value.isEmpty {
                componentName = String(node.value.prefix(20)) + (node.value.count > 20 ? "..." : "")
            }
            if node.parent == nil && node.name.lowercased() == "root" { // Check for root specifically
                componentName = "Resume"
            }
            pathComponents.insert(componentName, at: 0)
            currentNode = node.parent
        }
        return pathComponents.joined(separator: " > ")
    }
}
