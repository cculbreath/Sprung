// Sprung/ResumeTree/Models/TreeNode+Export.swift
// Name-based child lookup helpers for TreeNode.

import Foundation
import SwiftData

extension TreeNode {
    /// Normalize a name for flexible matching (lowercase, remove spaces/punctuation)
    private static func normalizedKey(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Find a child node by name (case-insensitive, ignores spaces/punctuation)
    func findChildByName(_ name: String) -> TreeNode? {
        let normalizedSearch = Self.normalizedKey(name)
        // First try exact case-insensitive match
        if let exact = children?.first(where: { $0.name.lowercased() == name.lowercased() }) {
            return exact
        }
        // Fall back to normalized match (ignores spaces/punctuation)
        return children?.first { Self.normalizedKey($0.name) == normalizedSearch }
    }
}
