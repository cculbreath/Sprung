// Sprung/ResumeTree/Models/TreeNode+JSON.swift
// JSON conversion extensions for TreeNode.

import Foundation

// MARK: - JSON Conversion Extension
extension TreeNode {
    /// Convert TreeNode to revision-format dictionary for the revision agent workspace.
    /// Includes: id, name, value, myIndex, isTitleNode, children — omits editor-only fields.
    /// Skips children with `.excludedFromGroup` status (user excluded them from AI review).
    func toRevisionDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "name": name,
            "value": value,
            "myIndex": myIndex,
            "isTitleNode": isTitleNode
        ]
        let exportableChildren = orderedChildren.filter { $0.status != .excludedFromGroup }
        if !exportableChildren.isEmpty {
            dict["children"] = exportableChildren.map { $0.toRevisionDictionary() }
        } else {
            dict["children"] = [] as [[String: Any]]
        }
        return dict
    }
}
