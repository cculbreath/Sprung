import Foundation
import SwiftData

enum LeafStatus: String, Codable, Hashable {
    case isEditing
    case aiToReplace
    case disabled = "leafDisabled"
    case saved = "leafValueSaved"
    case isNotLeaf = "nodeIsNotLeaf"
}

// Example SwiftData model

@Model class TreeNode: Identifiable {
    var id = UUID().uuidString
    var name: String = ""
    var value: String
    var includeInEditor: Bool = false
    var myIndex: Int = -1
    @Relationship(deleteRule: .cascade) var children: [TreeNode]? = nil
    weak var parent: TreeNode?
    var label: String { return resume.label(name) }
    @Relationship(deleteRule: .noAction) var resume: Resume
    var status: LeafStatus
    private(set) var nodeDepth: Int
    var depth: Int {
        var current = self
        var depthCount = 0

        while let parent = current.parent {
            depthCount += 1
            current = parent
        }

        return depthCount
    }

    var hasChildren: Bool {
        return !(children?.isEmpty ?? true)
    }

    var aiStatusChildren: Int {
        var count = 0

        // Check if the current node has the desired status
        if status == .aiToReplace {
            count += 1
        }

        // Recursively count the descendants with the desired status
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
        resume: Resume
    ) {
        self.name = name
        self.value = value
        self.children = children
        self.parent = parent
        self.status = status
        includeInEditor = inEditor

        nodeDepth = 0
        self.resume = resume
        // No need to set status again, it's already set by default.
    }

    @discardableResult
    func addChild(_ child: TreeNode) -> TreeNode {
        if children == nil {
            children = []
        }
        //    print(child.resume.id)
        child.parent = self
        // Assign index sequentially within the parent's children array.
        child.myIndex = (children?.count ?? 0)
        child.nodeDepth = nodeDepth + 1
        children?.append(child)
        return child
    }

    var growDepth: Bool { return nodeDepth > 2 }
    static func traverseAndExportNodes(node: TreeNode, currentPath: String = "")
        -> [[String: Any]]
    {
        var result: [[String: Any]] = []
        var newPath: String
        // Construct the current tree path
        if node.parent == nil {
            newPath = "Resume"
        } else {
            newPath =
                currentPath.isEmpty ? node.name : "\(currentPath) > \(node.name)"
        }
        // If the node's status is .aiToReplace, add it to the result array
        if node.status == .aiToReplace {
            if node.name != "" && node.value != "" {
                let titleNodeData: [String: Any] = [
                    "id": node.id,
                    "value": node.name,
                    "tree_path": currentPath,
                    "isTitleNode": true,
                ]
                result.append(titleNodeData)
            }

            let nodeData: [String: Any] = [
                "id": node.id,
                "value": node.value,
                "tree_path": newPath,
                "isTitleNode": false,
            ]
            result.append(nodeData)
        }

        // Recursively traverse the children
        for child in node.children ?? [] {
            let childResults = traverseAndExportNodes(
                node: child, currentPath: newPath
            )
            result.append(contentsOf: childResults)
        }

        return result
    }

    /// Updates the values of TreeNode objects based on the provided JSON file.
    /// - Parameters:
    ///   - jsonFileURL: The URL of the JSON file containing the array of {id: String, value: String} objects.
    ///   - context: The SwiftData context used to fetch and update the TreeNode objects.
    /// - Throws: An error if reading the JSON file, parsing JSON, or saving the context fails.
    static func updateValues(from jsonFileURL: URL, using context: ModelContext) throws {
        // Load JSON data from the provided file URL
        let jsonData = try Data(contentsOf: jsonFileURL)

        // Parse JSON data into an array of dictionaries
        guard let jsonArray = try JSONSerialization.jsonObject(
            with: jsonData, options: []
        ) as? [[String: String]] else {
            return
        }

        // Iterate over the array and update corresponding TreeNodes
        for jsonObject in jsonArray {
            if let id = jsonObject["id"], let newValue = jsonObject["value"], let titleNode = jsonObject["isTitleNode"] {
                // Fetch the corresponding TreeNode from the SwiftData store manually
                let fetchRequest = FetchDescriptor<TreeNode>(
                    predicate: #Predicate { $0.id == id }
                )

                if let node = try context.fetch(fetchRequest).first {
                    // Update the value of the TreeNode
                    if titleNode == "true" {
                        node.name = newValue
                    } else {
                        node.value = newValue
                    }
                } else {
                }
            } else {
            }
        }

        // Save the context to persist changes
        try context.save()
    }

    static func deleteTreeNode(node: TreeNode, context: ModelContext) {
        // Recursively delete children
        for child in node.children ?? [] {
            deleteTreeNode(node: child, context: context)
        }
        // Remove from parent's children array if necessary
        if let parent = node.parent, let index = parent.children?.firstIndex(of: node) {
            parent.children?.remove(at: index)
        }
        // No need to manually maintain a nodes array; the computed property
        // on `Resume` will pick up changes automatically.
        // Delete the node itself
        context.delete(node)

        // Save context to persist changes
        do {
            try context.save()
        } catch {
        }
    }

    func deepCopy(newResume: Resume) -> TreeNode {
        // Create a copy of the current node with the new resume
        let copyNode = TreeNode(
            name: name,
            value: value,
            parent: nil, // The parent will be set during recursion
            inEditor: includeInEditor,
            status: status,
            resume: newResume
        )

        // Recursively copy the children
        if let children = children {
            for child in children {
                let childCopy = child.deepCopy(newResume: newResume)
                copyNode.addChild(childCopy) // Attach the child to the copied parent
            }
        }

        return copyNode
    }
}
