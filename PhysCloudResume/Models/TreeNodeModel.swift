import Foundation
import SwiftUI
import SwiftData

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
    var value: String = ""
    private(set) var myIndex: Int = -1
    private var childIndexer = 0
    @Relationship(deleteRule: .cascade, inverse: \TreeNode.parent) private(set)
    var children: [TreeNode]? = nil
    weak var parent: TreeNode? = nil
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
        parent: TreeNode? = nil, status: LeafStatus = LeafStatus.disabled
    ) {
        self.name = name
        self.value = value
        self.children = children
        self.parent = parent
        self.status = status
        self.nodeDepth = 0
        // No need to set status again, it's already set by default.
    }
    @discardableResult
    func addChild(_ child: TreeNode) -> TreeNode {
        if self.children == nil {
            self.children = []
        }
        child.parent = self
        child.myIndex = childIndexer
        child.nodeDepth = self.nodeDepth + 1
        self.children?.append(child)
        childIndexer += 1
        return child
    }
    var growDepth: Bool { return nodeDepth > 2 }

}
