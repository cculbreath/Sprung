// Sprung/ResumeTree/Models/TreeNode+Export.swift
// Path-based export and review change application for TreeNode.

import Foundation
import SwiftData

// MARK: - Generic Path-Based Export for Review Phases

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

    /// Export nodes matching a path pattern for LLM review.
    ///
    /// # Path Syntax
    /// - `*` = enumerate AND BUNDLE into one revnode (holistic review)
    /// - `[]` = enumerate with one revnode per item (individual review)
    /// - Plain names = schema field names
    ///
    /// # Examples
    /// - `skills.*.name` → 1 revnode with all 5 category names bundled
    /// - `skills[].name` → 5 revnodes, one per category name
    /// - `skills[].keywords` → 5 revnodes, each with that category's keywords
    /// - `work[].highlights` → 4 revnodes, each with that job's highlights
    /// - `work.*.highlights` → 1 revnode with all highlights bundled
    ///
    /// - Parameters:
    ///   - path: Path pattern to match (e.g., "skills.*.name")
    ///   - rootNode: The tree root to search from
    /// - Returns: Array of ExportedReviewNode for nodes matching the pattern
    static func exportNodesMatchingPath(_ path: String, from rootNode: TreeNode) -> [ExportedReviewNode] {
        // Parse path, separating [] from field names
        // "skills[].keywords" -> ["skills", "[]", "keywords"]
        // "skills.*.name" -> ["skills", "*", "name"]
        var components: [String] = []
        for part in path.split(separator: ".") {
            let partStr = String(part)
            if partStr.hasSuffix("[]") {
                // Split "skills[]" into "skills" and "[]"
                let fieldName = String(partStr.dropLast(2))
                if !fieldName.isEmpty {
                    components.append(fieldName)
                }
                components.append("[]")
            } else {
                components.append(partStr)
            }
        }
        var results: [ExportedReviewNode] = []

        // Check if pattern uses * (bundle) vs [] (enumerate)
        let usesBundling = components.contains("*")

        exportNodesRecursive(
            node: rootNode,
            pathComponents: components,
            componentIndex: 0,
            currentPath: [],
            results: &results
        )

        // If bundling mode, combine all results into one revnode
        if usesBundling && results.count > 1 {
            let bundled = bundleExportedNodes(results, pattern: path)
            Logger.debug("📊 Bundled \(results.count) nodes into 1 revnode for pattern '\(path)'")
            return [bundled]
        }

        Logger.debug("📊 Exported \(results.count) nodes matching path '\(path)'")
        return results
    }

    /// Bundle multiple exported nodes into a single revnode with combined values.
    private static func bundleExportedNodes(_ nodes: [ExportedReviewNode], pattern: String) -> ExportedReviewNode {
        // Collect one value per source node (1:1 with sourceNodeIds).
        // For containers, use the concatenated value — NOT flattened children —
        // so that applyBundledChanges can map each entry back to its source node.
        var allValues: [String] = []
        var allIds: [String] = []

        for node in nodes {
            allIds.append(node.id)
            if !node.value.isEmpty {
                allValues.append(node.value)
            }
        }

        // Generate a bundled ID from the pattern
        let bundledId = "bundled-\(pattern.replacingOccurrences(of: ".", with: "-").replacingOccurrences(of: "*", with: "star"))"

        // Create display name from pattern (e.g., "skills.*.name" -> "Skill Names")
        let displayName = bundleDisplayName(from: pattern)

        return ExportedReviewNode(
            id: bundledId,
            path: pattern,
            displayName: displayName,
            value: allValues.joined(separator: "\n"),
            childValues: allValues,
            childCount: allValues.count,
            isBundled: true,
            sourceNodeIds: allIds
        )
    }

    /// Generate a human-readable display name from a bundle pattern.
    private static func bundleDisplayName(from pattern: String) -> String {
        // Extract meaningful parts: "skills.*.name" -> "Skill Names"
        let parts = pattern.split(separator: ".").filter { $0 != "*" && $0 != "[]" }
        if parts.count >= 2 {
            let section = parts[0].capitalized
            let field = parts[parts.count - 1].capitalized
            return "\(section) \(field)s"
        } else if let lastPart = parts.last {
            return String(lastPart).capitalized + "s"
        }
        return "Bundled Items"
    }

    /// Export a section as a single bundled RevNode with the full serialized object.
    ///
    /// For multi-attribute bundles like `skills.*.(name, keywords)`, this produces ONE
    /// ExportedReviewNode whose value is a JSON array of entry objects, each containing
    /// only the specified attributes. Order is preserved.
    ///
    /// - Parameters:
    ///   - sectionPath: Path to the section node (e.g., "skills")
    ///   - attributes: Attributes to include per entry (e.g., ["name", "keywords"])
    ///   - rootNode: The tree root to search from
    /// - Returns: A single ExportedReviewNode with serialized JSON value, or empty array if section not found
    static func exportSectionAsObject(
        sectionPath: String,
        attributes: [String],
        from rootNode: TreeNode
    ) -> [ExportedReviewNode] {
        // Navigate to the section node
        let pathComponents = sectionPath.split(separator: ".").map(String.init)
        var current = rootNode
        for component in pathComponents {
            guard let child = current.findChildByName(component) else {
                Logger.warning("[exportSectionAsObject] Section not found: \(sectionPath)")
                return []
            }
            current = child
        }

        let entries = current.orderedChildren.filter { $0.status != .excludedFromGroup }
        guard !entries.isEmpty else { return [] }

        // Collect entry objects and source node IDs
        var entryDicts: [[String: Any]] = []
        var sourceNodeIds: [String] = []  // Flat: [entry0.attr0_id, entry0.attr1_id, entry1.attr0_id, ...]

        for entry in entries {
            var dict: [String: Any] = [:]
            for attr in attributes {
                if let attrNode = entry.findChildByName(attr) {
                    sourceNodeIds.append(attrNode.id)
                    if attrNode.orderedChildren.isEmpty {
                        // Scalar attribute
                        dict[attr] = attrNode.value
                    } else {
                        // Container attribute (e.g., keywords) — array of child values
                        let childVals = attrNode.orderedChildren.compactMap { child -> String? in
                            let v = child.value.isEmpty ? child.name : child.value
                            return v.isEmpty ? nil : v
                        }
                        dict[attr] = childVals
                    }
                } else {
                    // Attribute not found on this entry — use empty placeholder
                    sourceNodeIds.append("")
                    dict[attr] = ""
                }
            }
            entryDicts.append(dict)
        }

        // Serialize as JSON, preserving attribute order via manual construction
        let jsonLines = entryDicts.map { dict -> String in
            let fields = attributes.map { attr -> String in
                let val = dict[attr]
                if let arr = val as? [String] {
                    let escaped = arr.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }
                    return "\"\(attr)\": [\(escaped.joined(separator: ", "))]"
                } else if let str = val as? String {
                    return "\"\(attr)\": \"\(str.replacingOccurrences(of: "\"", with: "\\\""))\""
                } else {
                    return "\"\(attr)\": \"\""
                }
            }
            return "  { \(fields.joined(separator: ", ")) }"
        }
        let jsonValue = "[\n\(jsonLines.joined(separator: ",\n"))\n]"

        // Build display name
        let sectionName = pathComponents.last?.capitalized ?? sectionPath.capitalized
        let attrList = attributes.joined(separator: ", ")
        let displayName = "\(sectionName) (\(attrList))"

        let pattern = "\(sectionPath).*.(\(attributes.joined(separator: ", ")))"
        let bundledId = "bundled-\(sectionPath.replacingOccurrences(of: ".", with: "-"))-object"

        let node = ExportedReviewNode(
            id: bundledId,
            path: pattern,
            displayName: displayName,
            value: jsonValue,
            childValues: jsonLines.map { $0.trimmingCharacters(in: .whitespaces) },
            childCount: entries.count,
            isBundled: true,
            sourceNodeIds: sourceNodeIds
        )

        Logger.debug("[exportSectionAsObject] Exported \(entries.count) entries × \(attributes.count) attrs as single RevNode for '\(sectionPath)'")
        return [node]
    }

    private static func exportNodesRecursive(
        node: TreeNode,
        pathComponents: [String],
        componentIndex: Int,
        currentPath: [String],
        results: inout [ExportedReviewNode]
    ) {
        // Base case: we've matched all components
        guard componentIndex < pathComponents.count else {
            // This node matches - export it
            let exported = exportNode(node, path: currentPath.joined(separator: "."))
            results.append(exported)
            return
        }

        let component = pathComponents[componentIndex]

        // Handle wildcards
        if component == "*" {
            // Enumerate all object children (children with display names that have sub-fields)
            // Skip children excluded from group review
            for (index, child) in node.orderedChildren.enumerated() {
                guard child.status != .excludedFromGroup else { continue }
                // Build identifier: prefer name, then value, then index
                let identifier = !child.name.isEmpty ? child.name :
                                 !child.value.isEmpty ? child.value :
                                 "[\(index)]"
                let childPath = currentPath + [identifier]
                exportNodesRecursive(
                    node: child,
                    pathComponents: pathComponents,
                    componentIndex: componentIndex + 1,
                    currentPath: childPath,
                    results: &results
                )
            }
        } else if component == "[]" {
            // Enumerate all array item children (leaf values)
            // Skip children excluded from group review
            for (index, child) in node.orderedChildren.enumerated() {
                guard child.status != .excludedFromGroup else { continue }
                // Build identifier: prefer name, then value, then index
                let identifier = !child.name.isEmpty ? child.name :
                                 !child.value.isEmpty ? child.value :
                                 "[\(index)]"
                let childPath = currentPath + [identifier]
                exportNodesRecursive(
                    node: child,
                    pathComponents: pathComponents,
                    componentIndex: componentIndex + 1,
                    currentPath: childPath,
                    results: &results
                )
            }
        } else {
            // Exact field name match
            if let child = node.findChildByName(component) {
                let childPath = currentPath + [component]
                exportNodesRecursive(
                    node: child,
                    pathComponents: pathComponents,
                    componentIndex: componentIndex + 1,
                    currentPath: childPath,
                    results: &results
                )
            }
        }
    }

    /// Export a single node to ExportedReviewNode
    private static func exportNode(_ node: TreeNode, path: String) -> ExportedReviewNode {
        let nodeName = node.name.isEmpty ? node.value : node.name
        // Build contextual display name from path (e.g., "work.Tesla.description" → "Tesla - description")
        let displayName = buildContextualDisplayName(nodeName: nodeName, path: path)
        let hasChildren = node.children != nil && !node.orderedChildren.isEmpty

        if hasChildren {
            // Container node - collect child values
            let childValues = node.orderedChildren.compactMap { child -> String? in
                let value = child.value.isEmpty ? child.name : child.value
                return value.isEmpty ? nil : value
            }
            let concatenatedValue = childValues.joined(separator: ", ")

            return ExportedReviewNode(
                id: node.id,
                path: path,
                displayName: displayName,
                value: concatenatedValue,
                childValues: childValues,
                childCount: childValues.count
            )
        } else {
            // Scalar node
            let value = node.value.isEmpty ? node.name : node.value
            return ExportedReviewNode(
                id: node.id,
                path: path,
                displayName: displayName,
                value: value,
                childValues: nil,
                childCount: 0
            )
        }
    }

    /// Build a contextual display name that includes parent context.
    /// e.g., path "work.Tesla.description" with nodeName "description" → "Tesla - description"
    /// Never returns empty - falls back to nodeName, path component, or "Item"
    private static func buildContextualDisplayName(nodeName: String, path: String) -> String {
        let components = path.split(separator: ".").map(String.init)

        // Use nodeName if it's not empty
        let effectiveName = nodeName.isEmpty ? (components.last ?? "Item") : nodeName

        guard components.count >= 2 else { return effectiveName }

        // Skip section name (first component like "work", "skills") and the node name (last component)
        // Take the middle components as context (e.g., company name, skill category)
        let middleComponents = components.dropFirst().dropLast()

        if let context = middleComponents.first, !context.isEmpty {
            return "\(context) - \(effectiveName)"
        }
        return effectiveName
    }

    /// Apply review changes from a PhaseReviewContainer to the tree.
    ///
    /// - Parameters:
    ///   - review: The review container with approved changes
    ///   - rootNode: The tree root to apply changes to
    ///   - context: SwiftData model context for persistence
    @MainActor
    static func applyPhaseReviewChanges(
        _ review: PhaseReviewContainer,
        to rootNode: TreeNode,
        context: ModelContext
    ) {
        for item in review.items {
            // Only process accepted items (acceptedOriginal means keep original - no change needed)
            guard item.userDecision == .accepted else { continue }

            // Find the node by ID
            guard let node = findNodeById(item.id, in: rootNode) else {
                if item.action == .add {
                    // Handle adding new nodes - need parent context from path
                    Logger.warning("⚠️ Add action not yet implemented for new nodes")
                }
                continue
            }

            switch item.action {
            case .keep:
                break // No action needed

            case .modify:
                // Use user's edited value if provided, otherwise use proposed value
                if let editedChildren = item.editedChildren {
                    // User edited the children
                    replaceChildValues(in: node, with: editedChildren, context: context)
                    Logger.info("✅ Modified node with user edits: \(item.displayName)")
                } else if let proposedChildren = item.proposedChildren {
                    // Container modification - replace children with proposed
                    replaceChildValues(in: node, with: proposedChildren, context: context)
                    Logger.info("✅ Modified node: \(item.displayName)")
                } else {
                    // Scalar modification - use edited value if available
                    let newValue = item.editedValue ?? item.proposedValue
                    node.value = newValue
                    Logger.info("✅ Modified node\(item.editedValue != nil ? " with user edits" : ""): \(item.displayName)")
                }

            case .remove:
                deleteTreeNode(node: node, context: context)
                Logger.info("✅ Removed node: \(item.displayName)")

            case .add:
                Logger.warning("⚠️ Add action for existing node - unexpected")
            }
        }

        do {
            try context.save()
            Logger.debug("✅ Saved phase review changes")
        } catch {
            Logger.error("❌ Failed to save phase review changes: \(error)")
        }
    }

    /// Find a node by ID anywhere in the tree
    private static func findNodeById(_ id: String, in node: TreeNode) -> TreeNode? {
        if node.id == id { return node }
        for child in node.orderedChildren {
            if let found = findNodeById(id, in: child) {
                return found
            }
        }
        return nil
    }

    /// Replace all child values in a container node
    private static func replaceChildValues(
        in containerNode: TreeNode,
        with newValues: [String],
        context: ModelContext
    ) {
        // Remove existing children
        for child in containerNode.orderedChildren {
            context.delete(child)
        }
        containerNode.children?.removeAll()

        // Add new children
        for (index, value) in newValues.enumerated() {
            let childNode = TreeNode(
                name: "",
                value: value,
                children: nil,
                parent: containerNode,
                inEditor: true,
                status: .saved,
                resume: containerNode.resume,
                isTitleNode: false
            )
            childNode.myIndex = index
            containerNode.addChild(childNode)
        }
    }
}
