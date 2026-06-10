//
//  ExperienceDefaultsToTree+AIFields.swift
//  Sprung
//
//  Parses and applies defaultAIFields patterns from the template manifest.
//
//  Pattern types:
//    section.*.attr         -> collection root marked .aiToReplace
//    section[].attr         -> collection root marked .aiToReplace
//    section.container[]    -> collection root marked .aiToReplace
//    section.field          -> .aiToReplace status on scalar node
//

import Foundation

@MainActor
extension ExperienceDefaultsToTree {

    // MARK: - Default AI Fields

    /// Apply defaultAIFields patterns to TreeNode state.
    ///
    /// This sets up the TreeNode as the single source of truth for AI review configuration.
    /// Patterns determine initial state; users can modify via UI (context menu toggle).
    ///
    /// # Pattern Types and TreeNode State
    ///
    /// | Pattern | TreeNode State |
    /// |---------|----------------|
    /// | `section.*.attr` | collection root marked `.aiToReplace` |
    /// | `section[].attr` | collection root marked `.aiToReplace` |
    /// | `section.container[]` | collection root marked `.aiToReplace` |
    /// | `section.field` | field node marked `.aiToReplace` (scalar) |
    ///
    /// # Examples
    ///
    /// | Pattern | Effect |
    /// |---------|--------|
    /// | `skills.*.name` | skills node marked `.aiToReplace` |
    /// | `skills[].keywords` | skills node marked `.aiToReplace` |
    /// | `custom.jobTitles` | jobTitles node marked `.aiToReplace` |
    /// | `custom.objective` | objective node marked `.aiToReplace` |
    ///
    func applyDefaultAIFields(to root: TreeNode, patterns: [String]) {
        Logger.debug("🎯 [applyDefaultAIFields] Starting with \(patterns.count) patterns: \(patterns)")

        for pattern in patterns {
            applyPattern(pattern, to: root)
        }
    }

    /// Apply a single pattern to the tree, marking the appropriate node `.aiToReplace`.
    ///
    /// Collection patterns (containing `*` or `[]`) mark the collection ROOT editable;
    /// scalar patterns mark the resolved leaf editable.
    private func applyPattern(_ pattern: String, to root: TreeNode) {
        // Parse pattern into components, normalizing "field[]" to "field", "[]"
        var components: [String] = []
        for part in pattern.split(separator: ".") {
            let partStr = String(part)
            if partStr.hasSuffix("[]") {
                let fieldName = String(partStr.dropLast(2))
                if !fieldName.isEmpty {
                    components.append(fieldName)
                }
                components.append("[]")
            } else {
                components.append(partStr)
            }
        }

        guard !components.isEmpty else { return }

        // Collection pattern: resolve the collection root (path up to the first * or [])
        // and mark it editable. Scalar pattern: resolve the leaf and mark it editable.
        let collectionMarkerIndex = components.firstIndex { $0 == "*" || $0 == "[]" }

        let path: [String]
        if let markerIndex = collectionMarkerIndex {
            path = Array(components[0..<markerIndex])
        } else {
            path = components
        }

        guard let node = findNode(path: path, from: root) else {
            Logger.warning("🎯 [applyPattern] Node not found for path: \(path) (pattern: \(pattern))")
            return
        }

        node.status = .aiToReplace
        Logger.info("🎯 [applyPattern] Marked '\(node.name)' .aiToReplace for pattern '\(pattern)'")
    }

    /// Find a node by navigating a path of component names from root
    private func findNode(path: [String], from root: TreeNode) -> TreeNode? {
        var current = root
        for component in path {
            guard let child = current.findChildByName(component) else {
                let childNames = current.orderedChildren.map { $0.name }
                Logger.debug("🎯 [findNode] Could not find '\(component)' in '\(current.name)'. Available: \(childNames)")
                return nil
            }
            current = child
        }
        Logger.debug("🎯 [findNode] Found node at path: \(path) -> '\(current.name)'")
        return current
    }
}
