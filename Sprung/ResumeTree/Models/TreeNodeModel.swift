// Sprung/ResumeTree/Models/TreeNodeModel.swift
import Foundation
import SwiftData
enum LeafStatus: String, Codable, Hashable {
    case isEditing
    case aiToReplace
    case excludedFromGroup
    case disabled = "leafDisabled"
    case saved = "leafValueSaved"
    case isNotLeaf = "nodeIsNotLeaf"
}
@Model class TreeNode: Identifiable {
    var id = UUID().uuidString
    var name: String = ""
    var value: String
    var includeInEditor: Bool = false
    var myIndex: Int = -1 // Represents order within its parent's children array
    @Relationship(deleteRule: .cascade) var children: [TreeNode]?
    weak var parent: TreeNode?
    var label: String { return resume.label(name) } // Assumes resume.label handles missing keys
    /// Custom display label from manifest editorLabels (overrides label if set)
    var editorLabel: String?
    /// Returns the effective display label: editorLabel if set, otherwise falls back to label
    var displayLabel: String { editorLabel ?? label }
    @Relationship(deleteRule: .noAction) var resume: Resume
    /// Backing storage for `status`. SwiftData's `@Model` macro drops property
    /// observers, so the public computed `status` below is the single write
    /// chokepoint for transition side effects. `originalName` keeps the
    /// existing column so the rename is a lossless lightweight migration.
    @Attribute(originalName: "status")
    private var statusStorage: LeafStatus
    /// The node's editability state. Every UI surface assigns this directly,
    /// so the setter owns the TB-4 sweep: when a node leaves `.aiToReplace`
    /// and no editable ancestor remains, its group dissolves and orphaned
    /// `.excludedFromGroup` marks in the subtree are cleared — otherwise they
    /// would linger invisibly and silently re-apply if the node were marked
    /// editable again later. Exclusions inside a subtree rooted at a node
    /// that is still `.aiToReplace` belong to that live group and are kept.
    var status: LeafStatus {
        get { statusStorage }
        set {
            let oldValue = statusStorage
            statusStorage = newValue
            guard oldValue == .aiToReplace, newValue != .aiToReplace else { return }
            guard !hasAncestorWithAIStatus else { return }
            clearOrphanedDescendantExclusions()
        }
    }
    var depth: Int = 0
    // Schema metadata (optional, derived from manifest descriptors)
    var schemaKey: String?
    var schemaInputKindRaw: String?
    var schemaRequired: Bool = false
    var schemaRepeatable: Bool = false
    var schemaPlaceholder: String?
    var schemaTitleTemplate: String?
    var schemaValidationRule: String?
    var schemaValidationMessage: String?
    var schemaValidationPattern: String?
    var schemaValidationMin: Double?
    var schemaValidationMax: Double?
    @Attribute(.externalStorage)
    private var schemaValidationOptionsData: Data?
    var schemaValidationOptions: [String] {
        get {
            guard let schemaValidationOptionsData,
                  let decoded = try? JSONDecoder().decode([String].self, from: schemaValidationOptionsData) else {
                return []
            }
            return decoded
        }
        set {
            schemaValidationOptionsData = try? JSONEncoder().encode(newValue)
        }
    }
    var schemaSourceKey: String?
    /// Indicates whether the manifest allows adding/removing child entries for this node.
    var schemaAllowsChildMutation: Bool = false
    /// Indicates whether this node can be deleted by the user per manifest metadata.
    var schemaAllowsNodeDeletion: Bool = false
    // This property should be explicitly set when a node is created or its role changes.
    // It's not reliably computable based on name/value alone.
    // For the "Fix Overflow" feature, we will pass this to the LLM and expect it back.
    var isTitleNode: Bool = false
    var hasChildren: Bool {
        return !(children?.isEmpty ?? true)
    }
    var schemaInputKind: TemplateManifest.Section.FieldDescriptor.InputKind? {
        schemaInputKindRaw.flatMap { TemplateManifest.Section.FieldDescriptor.InputKind(rawValue: $0) }
    }
    var orderedChildren: [TreeNode] {
        (children ?? []).sorted { $0.myIndex < $1.myIndex }
    }
    var aiStatusChildren: Int {
        var count = 0
        if status == .aiToReplace {
            count += 1
        }
        if let children = children {
            for child in children {
                count += child.aiStatusChildren
            }
        }
        return count
    }

    // MARK: - AI Selection Inheritance

    // MARK: - Per-Attribute Review Mode (Collection Nodes)

    /// Attributes in "Together" mode - bundled into 1 revnode (pattern: section.*.attr)
    /// Stored as JSON-encoded array on collection nodes (e.g., skills, work)
    // DEPRECATED vNext — read once by migrateAISelectionV1, then ignored.
    // Remove this property (and the migration) in vNext+1. Keep the storage in
    // place until then so SwiftData lightweight migration does not drop the column.
    @Attribute(.externalStorage)
    private var bundledAttributesData: Data?

    /// Decodes legacy `bundledAttributesData` for migration use ONLY.
    var legacyBundledAttributes: [String]? {
        guard let data = bundledAttributesData else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    /// Attributes in "Separately" mode - one revnode per entry (pattern: section[].attr)
    /// Stored as JSON-encoded array on collection nodes
    // DEPRECATED vNext — read once by migrateAISelectionV1, then ignored.
    // Remove this property (and the migration) in vNext+1. Keep the storage in
    // place until then so SwiftData lightweight migration does not drop the column.
    @Attribute(.externalStorage)
    private var enumeratedAttributesData: Data?

    /// Decodes legacy `enumeratedAttributesData` for migration use ONLY.
    var legacyEnumeratedAttributes: [String]? {
        guard let data = enumeratedAttributesData else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    /// The single editability signal: a node is editable iff it is marked for AI replacement.
    var isEditable: Bool { status == .aiToReplace }

    /// Returns true if this is a collection node (has children that are entries)
    /// Collection nodes can have bundle/iterate modes applied
    var isCollectionNode: Bool {
        !orderedChildren.isEmpty && orderedChildren.first?.orderedChildren.isEmpty == false
    }

    /// Returns true if this node's AI selection is inherited from an ancestor
    /// (i.e., this node is NOT directly marked .aiToReplace, but an ancestor is)
    var isInheritedAISelection: Bool {
        guard status != .aiToReplace else { return false }
        return hasAncestorWithAIStatus
    }

    /// Returns true if any ancestor has .aiToReplace status.
    /// The walk stops at an `.excludedFromGroup` ancestor: exclusion blocks
    /// inheritance, so nodes under an excluded entry are NOT part of the
    /// editable group even when a higher ancestor is marked editable.
    var hasAncestorWithAIStatus: Bool {
        var current = parent
        while let ancestor = current {
            if ancestor.status == .excludedFromGroup {
                return false
            }
            if ancestor.status == .aiToReplace {
                return true
            }
            current = ancestor.parent
        }
        return false
    }

    /// Clears orphaned `.excludedFromGroup` marks in the subtree. Invoked by
    /// the `status` setter when this node leaves the editable state with no
    /// editable ancestor remaining. Subtrees rooted at a still-`.aiToReplace`
    /// node are skipped entirely: their exclusions opt out of that live group
    /// and remain meaningful until that group dissolves in turn.
    private func clearOrphanedDescendantExclusions() {
        for child in children ?? [] {
            if child.status == .aiToReplace { continue }
            if child.status == .excludedFromGroup {
                child.status = .saved
            }
            child.clearOrphanedDescendantExclusions()
        }
    }

    /// Evaluates the schemaTitleTemplate by replacing {{fieldName}} with child values.
    /// Falls back to displayLabel if no template or evaluation fails.
    var computedTitle: String {
        guard let template = schemaTitleTemplate, !template.isEmpty else {
            return displayLabel
        }
        var result = template
        // Replace {{fieldName}} patterns with child values
        let pattern = /\{\{(\w+)\}\}/
        for match in template.matches(of: pattern) {
            let fieldName = String(match.1)
            if let child = orderedChildren.first(where: { $0.name == fieldName || $0.schemaKey == fieldName }) {
                result = result.replacingOccurrences(of: String(match.0), with: child.value)
            }
        }
        return result.isEmpty ? displayLabel : result
    }

    init(
        name: String, value: String = "", children: [TreeNode]? = nil,
        parent: TreeNode? = nil, inEditor: Bool, status: LeafStatus = LeafStatus.disabled,
        resume: Resume, isTitleNode: Bool = false // Added isTitleNode to initializer
    ) {
        self.name = name
        self.value = value
        self.children = children
        self.parent = parent
        statusStorage = status
        includeInEditor = inEditor
        depth = parent.map { $0.depth + 1 } ?? 0
        self.resume = resume
        self.isTitleNode = isTitleNode // Initialize isTitleNode
    }
    @discardableResult
    func addChild(_ child: TreeNode) -> TreeNode {
        if children == nil {
            children = []
        }
        child.parent = self
        // max(existing)+1, not count: after deletions, count can collide with a
        // surviving sibling's index and make ordering nondeterministic.
        child.myIndex = (children?.map(\.myIndex).max() ?? -1) + 1
        child.depth = depth + 1
        children?.append(child)
        return child
    }

    static func deleteTreeNode(node: TreeNode, context: ModelContext) {
        guard node.allowsDeletion else {
            Logger.warning("🚫 Prevented deletion of node '\(node.name)' without manifest permission.")
            return
        }
        for child in node.children ?? [] {
            deleteTreeNode(node: child, context: context)
        }
        if let parent = node.parent, let index = parent.children?.firstIndex(of: node) {
            parent.children?.remove(at: index)
        }
        context.delete(node)
        // Note: save() is not called here to allow for batch operations
    }
    /// Builds the hierarchical path string for this node.
    /// Example: "Resume > Skills and Expertise > Software > Swift"
    func buildTreePath() -> String {
        var pathComponents: [String] = []
        var currentNode: TreeNode? = self
        while let node = currentNode {
            var componentName = "Unnamed Node"
            if !node.name.isEmpty {
                componentName = node.name
            } else if !node.value.isEmpty {
                componentName = String(node.value.prefix(20)) + (node.value.count > 20 ? "..." : "")
            }
            if node.parent == nil && node.name.lowercased() == "root" { // Check for root specifically
                componentName = "Resume"
            }
            pathComponents.insert(componentName, at: 0)
            currentNode = node.parent
        }
        return pathComponents.joined(separator: " > ")
    }
}
