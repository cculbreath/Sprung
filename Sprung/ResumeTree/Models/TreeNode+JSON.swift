// Sprung/ResumeTree/Models/TreeNode+JSON.swift
// JSON conversion extensions for TreeNode.

import Foundation

// MARK: - JSON Conversion Extension
extension TreeNode {
    /// Convert TreeNode to JSON string representation
    func toJSONString() -> String? {
        do {
            let nodeDict = toDictionary()
            let jsonData = try JSONSerialization.data(withJSONObject: nodeDict, options: [.prettyPrinted])
            return String(data: jsonData, encoding: .utf8)
        } catch {
            Logger.error("Failed to convert TreeNode to JSON: \(error)")
            return nil
        }
    }
    /// Convert TreeNode to dictionary for JSON serialization
    private func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "name": name,
            "value": value,
            "includeInEditor": includeInEditor,
            "myIndex": myIndex
        ]
        if let children = children, !children.isEmpty {
            dict["children"] = children.map { $0.toDictionary() }
        }
        return dict
    }

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
