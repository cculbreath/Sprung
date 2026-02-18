//
//  ExperienceDefaultsToTree+AIFields.swift
//  Sprung
//
//  Parses and applies defaultAIFields patterns from the template manifest.
//
//  Pattern types:
//    section.*.attr         -> bundledAttributes on collection node
//    section[].attr         -> enumeratedAttributes on collection node
//    section.container[]    -> enumeratedAttributes["*"] on container node
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
    /// | `section.*.attr` | `section.bundledAttributes += [attr]` |
    /// | `section[].attr` | `section.enumeratedAttributes += [attr]` |
    /// | `section.container[]` | Each child of container marked aiToReplace |
    /// | `section.field` | field node marked aiToReplace (scalar) |
    ///
    /// # Examples
    ///
    /// | Pattern | Effect |
    /// |---------|--------|
    /// | `skills.*.name` | skills.bundledAttributes = ["name"] |
    /// | `skills[].keywords` | skills.enumeratedAttributes = ["keywords"] |
    /// | `custom.jobTitles` | jobTitles node marked aiToReplace (solo container) |
    /// | `custom.objective` | objective node marked aiToReplace |
    ///
    func applyDefaultAIFields(to root: TreeNode, patterns: [String]) {
        Logger.debug("🎯 [applyDefaultAIFields] Starting with \(patterns.count) patterns: \(patterns)")

        for pattern in patterns {
            applyPattern(pattern, to: root)
        }
    }

    /// Apply a single pattern to the tree, setting appropriate TreeNode state.
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

        // Identify pattern type by position of * or []
        if let starIndex = components.firstIndex(of: "*") {
            // Bundle pattern: section.*.attr
            applyBundlePattern(components: components, starIndex: starIndex, to: root)
        } else if let bracketIndex = components.firstIndex(of: "[]") {
            // Enumerate pattern
            if bracketIndex == components.count - 1 {
                // Pattern ends with []: section.container[] - enumerate container children
                applyContainerEnumeratePattern(components: components, to: root)
            } else {
                // Pattern has [] in middle: section[].attr - enumerate with specific attribute
                applyEnumeratePattern(components: components, bracketIndex: bracketIndex, to: root)
            }
        } else {
            // Scalar pattern: section.field
            applyScalarPattern(components: components, to: root)
        }
    }

    /// Apply bundle pattern (section.*.attr) - sets bundledAttributes on collection node
    private func applyBundlePattern(components: [String], starIndex: Int, to root: TreeNode) {
        // Navigate to collection node (components before *)
        let pathToCollection = Array(components[0..<starIndex])
        guard let collectionNode = findNode(path: pathToCollection, from: root) else {
            Logger.warning("🎯 [applyBundlePattern] Collection not found for path: \(pathToCollection)")
            return
        }

        // Get attribute name (components after *)
        guard starIndex + 1 < components.count else {
            Logger.warning("🎯 [applyBundlePattern] No attribute after * in pattern")
            return
        }
        let attrName = components[starIndex + 1]

        // Add to bundled attributes
        var bundled = collectionNode.bundledAttributes ?? []
        if !bundled.contains(attrName) {
            bundled.append(attrName)
            collectionNode.bundledAttributes = bundled
        }

        // Note: Don't set .aiToReplace on collection - bundledAttributes is the source of truth
        // Visual indicators come from row background color based on bundledAttributes

        Logger.info("🎯 [applyBundlePattern] Set bundledAttributes[\(attrName)] on '\(collectionNode.name)'")
    }

    /// Apply enumerate pattern (section[].attr) - sets enumeratedAttributes on collection node
    private func applyEnumeratePattern(components: [String], bracketIndex: Int, to root: TreeNode) {
        // Navigate to collection node (components before [])
        let pathToCollection = Array(components[0..<bracketIndex])
        guard let collectionNode = findNode(path: pathToCollection, from: root) else {
            Logger.warning("🎯 [applyEnumeratePattern] Collection not found for path: \(pathToCollection)")
            return
        }

        // Get attribute name (components after [])
        guard bracketIndex + 1 < components.count else {
            Logger.warning("🎯 [applyEnumeratePattern] No attribute after [] in pattern")
            return
        }
        let attrName = components[bracketIndex + 1]

        // Add to enumerated attributes
        var enumerated = collectionNode.enumeratedAttributes ?? []
        if !enumerated.contains(attrName) {
            enumerated.append(attrName)
            collectionNode.enumeratedAttributes = enumerated
        }

        // Note: Don't set .aiToReplace on entries - enumeratedAttributes is the source of truth
        // Visual indicators come from row background color based on enumeratedAttributes

        Logger.info("🎯 [applyEnumeratePattern] Set enumeratedAttributes[\(attrName)] on '\(collectionNode.name)'")
    }

    /// Apply container enumerate pattern (section.container[]) - marks each child of container
    /// Uses enumeratedAttributes with "*" to indicate "enumerate all children"
    private func applyContainerEnumeratePattern(components: [String], to root: TreeNode) {
        // Navigate to container node (all components except final [])
        let pathToContainer = Array(components.dropLast())
        guard let containerNode = findNode(path: pathToContainer, from: root) else {
            Logger.warning("🎯 [applyContainerEnumeratePattern] Container not found for path: \(pathToContainer)")
            return
        }

        // Use enumeratedAttributes with "*" to indicate container enumerate mode
        // This distinguishes from solo (.aiToReplace) for visual indicators
        var enumerated = containerNode.enumeratedAttributes ?? []
        if !enumerated.contains("*") {
            enumerated.append("*")
            containerNode.enumeratedAttributes = enumerated
        }

        Logger.info("🎯 [applyContainerEnumeratePattern] Set enumeratedAttributes[*] on '\(containerNode.name)' for container enumerate")
    }

    /// Apply scalar pattern (section.field) - marks specific node
    private func applyScalarPattern(components: [String], to root: TreeNode) {
        guard let node = findNode(path: components, from: root) else {
            Logger.warning("🎯 [applyScalarPattern] Node not found for path: \(components)")
            return
        }

        node.status = .aiToReplace
        Logger.info("🎯 [applyScalarPattern] Marked scalar '\(node.name)' for AI")
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
