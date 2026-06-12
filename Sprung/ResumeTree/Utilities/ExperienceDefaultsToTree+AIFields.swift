//
//  ExperienceDefaultsToTree+AIFields.swift
//  Sprung
//
//  Parses and applies defaultAIFields patterns from the template manifest.
//
//  Patterns resolve to ATTRIBUTE level: a collection marker (`*` or `[]`)
//  fans out across the collection's entries and the remainder of the path is
//  resolved inside each entry. Only the node the pattern actually names is
//  marked `.aiToReplace` — never the whole section.
//
//  Pattern types:
//    section.*.attr   -> each entry's `attr` node marked .aiToReplace
//    section[].attr   -> each entry's `attr` node marked .aiToReplace
//    section.list[]   -> the `list` container itself marked .aiToReplace
//    section.field    -> the resolved field node marked .aiToReplace
//

import Foundation

@MainActor
extension ExperienceDefaultsToTree {

    // MARK: - Default AI Fields

    /// Apply defaultAIFields patterns to TreeNode state.
    ///
    /// This sets up the TreeNode as the single source of truth for AI review
    /// configuration. Patterns determine initial state; users can modify via
    /// UI (context menu toggle). The single selection axis is preserved:
    /// `isEditable == (status == .aiToReplace)`.
    ///
    /// # Examples
    ///
    /// | Pattern | Effect |
    /// |---------|--------|
    /// | `work[].highlights` | each work entry's `highlights` container marked `.aiToReplace` |
    /// | `skills.*.name` | each skill entry's `name` field marked `.aiToReplace` |
    /// | `skills[].keywords` | each skill entry's `keywords` container marked `.aiToReplace` |
    /// | `custom.jobTitles[]` | the `jobTitles` container marked `.aiToReplace` |
    /// | `custom.objective` | the `objective` node marked `.aiToReplace` |
    ///
    func applyDefaultAIFields(to root: TreeNode, patterns: [String]) {
        Logger.debug("🎯 [applyDefaultAIFields] Starting with \(patterns.count) patterns: \(patterns)")

        for pattern in patterns {
            applyPattern(pattern, to: root)
        }
    }

    /// Apply a single pattern to the tree, marking the node(s) it names
    /// `.aiToReplace`. Collection markers fan out across entries so agent
    /// authority is scoped to exactly the attribute the manifest named.
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

        let markedCount = markNodes(components[...], from: root, pattern: pattern)
        if markedCount == 0 {
            Logger.warning("🎯 [applyPattern] No node matched pattern '\(pattern)'")
        } else {
            Logger.info("🎯 [applyPattern] Marked \(markedCount) node(s) .aiToReplace for pattern '\(pattern)'")
        }
    }

    /// Recursively resolve pattern components from `node`, fanning out across
    /// entries at each `*`/`[]` marker. Returns the number of nodes marked.
    private func markNodes(_ components: ArraySlice<String>, from node: TreeNode, pattern: String) -> Int {
        var current = node
        var index = components.startIndex

        while index < components.endIndex {
            let component = components[index]

            if component == "*" || component == "[]" {
                let remainder = components[(index + 1)...]
                if remainder.isEmpty {
                    // Trailing marker (`list[]`): the list container itself is
                    // the named attribute.
                    current.status = .aiToReplace
                    return 1
                }
                // Fan out: resolve the remainder inside each entry. Entries
                // missing the attribute (e.g. no highlights) contribute zero.
                var marked = 0
                for entry in current.orderedChildren {
                    marked += markNodes(remainder, from: entry, pattern: pattern)
                }
                return marked
            }

            guard let child = current.findChildByName(component) else {
                Logger.debug("🎯 [markNodes] No child '\(component)' under '\(current.name)' for pattern '\(pattern)'")
                return 0
            }
            current = child
            index += 1
        }

        current.status = .aiToReplace
        return 1
    }
}
