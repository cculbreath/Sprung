import Foundation
import SwiftData
import SwiftUI

enum LeafStatus: String, Codable, Hashable {
  case isEditing = "isEditing"
  case aiToReplace = "aiToReplace"
  case disabled = "leafDisabled"
  case saved = "leafValueSaved"
  case isNotLeaf = "nodeIsNotLeaf"
}

// Example SwiftData model

@Model class TreeNode: Identifiable {
  var id = UUID().uuidString
  var name: String = ""
  var value: String

  private(set) var myIndex: Int = -1
  private var childIndexer = 0
  @Relationship(deleteRule: .cascade) var children: [TreeNode]? = nil
  weak var parent: TreeNode?

  @Relationship(deleteRule: .noAction) var resume: Resume
  var status: LeafStatus
  private(set) var nodeDepth: Int

  var hasChildren: Bool {
    return !(children?.isEmpty ?? true)
  }
  var aiStatusChildren: Int {
    var count = 0

    // Check if the current node has the desired status
    if self.status == .aiToReplace {
      count += 1
    }

    // Recursively count the descendants with the desired status
    if let children = self.children {
      for child in children {
        count += child.aiStatusChildren
      }
    }

    return count
  }

  init(
    name: String, value: String = "", children: [TreeNode]? = nil,
    parent: TreeNode? = nil, status: LeafStatus = LeafStatus.disabled,
    resume: Resume
  ) {
    self.name = name
    self.value = value
    self.children = children
    self.parent = parent
    self.status = status
    self.nodeDepth = 0
    self.resume = resume
    resume.nodes.append(self)
    // No need to set status again, it's already set by default.
  }
  @discardableResult
  func addChild(_ child: TreeNode) -> TreeNode {
    if self.children == nil {
      self.children = []
    }
    //    print(child.resume.id)
    child.parent = self
    child.myIndex = childIndexer
    child.nodeDepth = self.nodeDepth + 1
    self.children?.append(child)
    childIndexer += 1
    return child
  }
  var growDepth: Bool { return nodeDepth > 2 }
  static func traverseAndExportNodes(node: TreeNode, currentPath: String = "")
    -> [[String: String]]
  {
    var result: [[String: String]] = []
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

      }

      let nodeData: [String: String] = [
        "id": node.id,
        "value": node.value,
        "tree_path": newPath,
      ]
      result.append(nodeData)
    }

    // Recursively traverse the children
    for child in node.children ?? [] {
      let childResults = traverseAndExportNodes(
        node: child, currentPath: newPath)
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
      with: jsonData, options: []) as? [[String: String]] else {
      print("Failed to parse JSON.")
      return
    }

    // Iterate over the array and update corresponding TreeNodes
    for jsonObject in jsonArray {
      if let id = jsonObject["id"], let newValue = jsonObject["value"] {
        // Fetch the corresponding TreeNode from the SwiftData store manually
        let fetchRequest = FetchDescriptor<TreeNode>(
          predicate: #Predicate { $0.id == id }
        )

        if let node = try context.fetch(fetchRequest).first {
          // Update the value of the TreeNode
          node.value = newValue
        } else {
          print("TreeNode with id \(id) not found.")
        }
      } else {
        print("Invalid JSON object: \(jsonObject)")
      }
    }

    // Save the context to persist changes
    try context.save()
  }
  static func deleteTreeNode(node: TreeNode, context: ModelContext) {
    // First, recursively delete all children
    if let children = node.children {
      for child in children {
        deleteTreeNode(node: child, context: context)
      }
    }
    // Then delete the node itself
    context.delete(node)

    // Save context to persist changes
    do {
      try context.save()
    } catch {
      print("Failed to delete TreeNode: \(error)")
    }
  }

  
  func deepCopy(newResume: Resume) -> TreeNode {
    // Create a copy of the current node with the new resume
    let copyNode = TreeNode(
      name: self.name,
      value: self.value,
      parent: nil,  // The parent will be set during recursion
      status: self.status,
      resume: newResume
    )

    // Recursively copy the children
    if let children = self.children {
      for child in children {
        let childCopy = child.deepCopy(newResume: newResume)
        copyNode.addChild(childCopy)  // Attach the child to the copied parent
      }
    }

    return copyNode
  }

}
