//
//  TreeNode+ViewChildren.swift
//  Sprung
//
//  ViewChildren operations for TreeNode.
//  Handles the presentation hierarchy (viewChildren) separately from the data hierarchy (children).
//
import Foundation
// MARK: - ViewChildren Operations
extension TreeNode {
    /// Rebuilds the viewChildren hierarchy for v4+ manifests after mutations.
    /// This ensures the presentation layer stays in sync with the data layer.
    ///
    /// - Parameter manifest: The template manifest containing keysInEditor configuration
    func rebuildViewHierarchy(manifest: TemplateManifest) {
        // Only rebuild if using v4+ manifest with keysInEditor
        guard manifest.schemaVersion >= 4, let keysInEditor = manifest.keysInEditor else {
            clearViewHierarchyState()
            return
        }
        clearViewHierarchyState()
        viewDepth = 0
        let context = ViewHierarchyContext(
            transparentKeys: Set(manifest.transparentKeys ?? []),
            editorLabels: manifest.editorLabels ?? [:]
        )
        var viewChildren: [TreeNode] = []
        for (index, keyPath) in keysInEditor.enumerated() {
            let pathComponents = keyPath.split(separator: ".").map(String.init)
            guard !pathComponents.isEmpty else { continue }
            guard let node = TreeNode.findNode(
                in: self,
                path: pathComponents,
                transparentKeys: context.transparentKeys
            ) else {
                Logger.warning("TreeNode.rebuildViewHierarchy: missing node for keyPath '\(keyPath)'")
                continue
            }
            node.applyEditorLabel(forPath: pathComponents, context: context)
            node.rebuildViewSubtree(
                using: context,
                path: pathComponents,
                viewDepth: 1
            )
            node.myIndex = index
            viewChildren.append(node)
        }
        self.viewChildren = viewChildren.isEmpty ? nil : viewChildren
    }
    /// Finds a node in the data tree by following a path, skipping transparent containers.
    ///
    /// - Parameters:
    ///   - root: The root node to start searching from
    ///   - path: Array of key names representing the path to follow
    ///   - transparentKeys: Set of keys that should be skipped during traversal
    /// - Returns: The found node, or nil if the path doesn't exist
    static func findNode(in root: TreeNode, path: [String], transparentKeys: Set<String>) -> TreeNode? {
        guard !path.isEmpty else { return nil }
        return findNode(
            current: root,
            path: path,
            pathIndex: 0,
            transparentKeys: transparentKeys
        )
    }
}
// MARK: - View Hierarchy Helpers
private extension TreeNode {
    struct ViewHierarchyContext {
        let transparentKeys: Set<String>
        let editorLabels: [String: String]
        func label(for path: [String]) -> String? {
            guard let last = path.last else { return nil }
            if let label = editorLabels[path.joined(separator: ".")] {
                return label
            }
            return editorLabels[last]
        }
    }
    func clearViewHierarchyState() {
        editorLabel = nil
        viewChildren = nil
        viewDepth = 0
        for child in children ?? [] {
            child.clearViewHierarchyState()
        }
    }
    static func findNode(
        current: TreeNode,
        path: [String],
        pathIndex: Int,
        transparentKeys: Set<String>
    ) -> TreeNode? {
        guard pathIndex < path.count else { return nil }
        let key = path[pathIndex]
        for child in current.children ?? [] {
            if child.matchesEditorKey(key) {
                if pathIndex == path.count - 1 {
                    return child
                }
                return findNode(
                    current: child,
                    path: path,
                    pathIndex: pathIndex + 1,
                    transparentKeys: transparentKeys
                )
            }
            if transparentKeys.contains(child.name) || child.editorTransparent {
                if let match = findNode(
                    current: child,
                    path: path,
                    pathIndex: pathIndex,
                    transparentKeys: transparentKeys
                ) {
                    return match
                }
            }
        }
        return nil
    }
    func matchesEditorKey(_ key: String) -> Bool {
        if name == key { return true }
        if let schemaKey, schemaKey == key { return true }
        return sanitized(name) == sanitized(key)
    }
    func sanitized(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "-", with: "")
    }
    func applyEditorLabel(forPath path: [String], context: ViewHierarchyContext) {
        editorLabel = context.label(for: path)
    }
    func rebuildViewSubtree(
        using context: ViewHierarchyContext,
        path: [String],
        viewDepth: Int
    ) {
        self.viewDepth = viewDepth
        guard let rawChildren = children, rawChildren.isEmpty == false else {
            viewChildren = nil
            return
        }
        let ordered = rawChildren.sorted { $0.myIndex < $1.myIndex }
        var visibleChildren: [TreeNode] = []
        for child in ordered {
            let childPath = path + [child.name]
            if context.transparentKeys.contains(child.name) || child.editorTransparent {
                child.applyEditorLabel(forPath: childPath, context: context)
                child.rebuildViewSubtree(
                    using: context,
                    path: childPath,
                    viewDepth: viewDepth
                )
                if let promoted = child.viewChildren {
                    for promotedChild in promoted {
                        promotedChild.viewDepth = viewDepth + 1
                    }
                    visibleChildren.append(contentsOf: promoted)
                }
                continue
            }
            child.applyEditorLabel(forPath: childPath, context: context)
            child.rebuildViewSubtree(
                using: context,
                path: childPath,
                viewDepth: viewDepth + 1
            )
            visibleChildren.append(child)
        }
        for (index, child) in visibleChildren.enumerated() {
            child.myIndex = index
        }
        viewChildren = visibleChildren.isEmpty ? nil : visibleChildren
    }
}
