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
    var status: LeafStatus
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
    @Attribute(.externalStorage)
    private var bundledAttributesData: Data?

    var bundledAttributes: [String]? {
        get {
            guard let data = bundledAttributesData else { return nil }
            return try? JSONDecoder().decode([String].self, from: data)
        }
        set {
            bundledAttributesData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    /// Attributes in "Separately" mode - one revnode per entry (pattern: section[].attr)
    /// Stored as JSON-encoded array on collection nodes
    @Attribute(.externalStorage)
    private var enumeratedAttributesData: Data?

    var enumeratedAttributes: [String]? {
        get {
            guard let data = enumeratedAttributesData else { return nil }
            return try? JSONDecoder().decode([String].self, from: data)
        }
        set {
            enumeratedAttributesData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    /// Returns true if this collection node has any attributes set for AI review
    var hasAttributeReviewModes: Bool {
        let hasBundled = !(bundledAttributes?.isEmpty ?? true)
        let hasEnumerated = !(enumeratedAttributes?.isEmpty ?? true)
        return hasBundled || hasEnumerated
    }

    /// Total revnode count for this subtree
    /// Counts: solo nodes, bundle attributes (1 each), iterate attributes (N each), container enumerate children
    /// Skips children with `.excludedFromGroup` status
    var revnodeCount: Int {
        var count = 0

        // Container enumerate: each child is a revnode (skip excluded)
        // Only for flat containers (entries without sub-attributes).
        // Object collections with ["*"] are handled by the iterate block below.
        let isContainerEnumerate = enumeratedAttributes?.contains("*") == true
        let isObjectCollection = orderedChildren.first.map { !$0.orderedChildren.isEmpty } ?? false
        if isContainerEnumerate && !isObjectCollection {
            count += orderedChildren.filter { $0.status != .excludedFromGroup }.count
        }
        // Bundle attributes: 1 revnode per attribute (single-attr), or entries × attrs (multi-attr)
        else if let bundled = bundledAttributes, !bundled.isEmpty {
            let namedAttrs = bundled.filter { $0 != "*" && !$0.hasSuffix("[]") }
            let nestedAttrs = bundled.filter { $0.hasSuffix("[]") }

            if namedAttrs.count > 1 {
                // Multi-attribute bundle: count entries × attributes (section compound review items)
                let entryCount = orderedChildren.filter { $0.status != .excludedFromGroup }.count
                count += entryCount * namedAttrs.count
            } else {
                // Single named attribute: 1 bundled revnode
                for _ in namedAttrs {
                    count += 1
                }
            }

            // "*" wildcard: 1 bundled revnode for all direct children
            if bundled.contains("*") {
                count += 1
            }

            // Nested array attrs: existing per-child counting
            for attr in nestedAttrs {
                let baseAttr = String(attr.dropLast(2))
                for entry in orderedChildren {
                    if let attrNode = entry.orderedChildren.first(where: {
                        ($0.name.isEmpty ? $0.displayLabel : $0.name) == baseAttr
                    }) {
                        count += attrNode.orderedChildren.filter { $0.status != .excludedFromGroup }.count
                    }
                }
            }
        }

        // Iterate attributes: N revnodes per attribute (1 per entry) or N×M for nested arrays
        if let enumerated = enumeratedAttributes, !enumerated.isEmpty {
            // Expand "*" for object collections (same logic as PhaseReviewManager)
            var iterateAttrs: [String]
            if enumerated == ["*"] {
                if let firstEntry = orderedChildren.first, !firstEntry.orderedChildren.isEmpty {
                    // Object collection: all attributes → multi-attribute iterate
                    iterateAttrs = firstEntry.orderedChildren.compactMap {
                        let n = $0.name.isEmpty ? $0.displayLabel : $0.name
                        return n.isEmpty ? nil : n
                    }
                } else {
                    iterateAttrs = [] // Flat → counted by container enumerate block above
                }
            } else {
                iterateAttrs = enumerated.filter { $0 != "*" }
            }

            // Group simple vs nested-array attrs
            let simpleAttrs = iterateAttrs.filter { !$0.hasSuffix("[]") }
            let nestedAttrs = iterateAttrs.filter { $0.hasSuffix("[]") }

            // Simple attrs: count entries ONCE regardless of how many attrs
            // (they merge into one compound RevNode per entry)
            if !simpleAttrs.isEmpty {
                count += orderedChildren.filter { $0.status != .excludedFromGroup }.count
            }

            // Nested array attrs: existing per-child counting
            for attr in nestedAttrs {
                let baseAttr = String(attr.dropLast(2))
                for entry in orderedChildren {
                    if let attrNode = entry.orderedChildren.first(where: {
                        ($0.name.isEmpty ? $0.displayLabel : $0.name) == baseAttr
                    }) {
                        count += attrNode.orderedChildren.filter { $0.status != .excludedFromGroup }.count
                    }
                }
            }
        }

        // Solo nodes: status == .aiToReplace with no bundle/enumerate attributes
        // Counts both leaf nodes and solo containers (e.g., jobTitles) as 1 revnode each
        if status == .aiToReplace && bundledAttributes == nil && enumeratedAttributes == nil {
            // Only count if not part of a container enumerate (those are counted above)
            if parent?.enumeratedAttributes?.contains("*") != true {
                count += 1
            }
        }

        // Recurse into children (skip if container enumerate or solo container - already counted)
        let isSoloContainer = status == .aiToReplace && !orderedChildren.isEmpty &&
                              bundledAttributes == nil && enumeratedAttributes == nil
        if enumeratedAttributes?.contains("*") != true && !isSoloContainer {
            for child in orderedChildren {
                count += child.revnodeCount
            }
        }

        return count
    }

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

    /// Returns true if any ancestor has .aiToReplace status
    var hasAncestorWithAIStatus: Bool {
        var current = parent
        while let ancestor = current {
            if ancestor.status == .aiToReplace {
                return true
            }
            current = ancestor.parent
        }
        return false
    }

    /// Returns true if this node is included via BUNDLE mode (purple)
    /// e.g., "Swift" under "keywords" when skills.*.keywords is configured
    var isIncludedInBundleReview: Bool {
        guard let containerParent = parent,
              let entry = containerParent.parent,
              let collection = entry.parent else { return false }

        let containerName = containerParent.name.isEmpty ? containerParent.displayLabel : containerParent.name
        return collection.bundledAttributes?.contains(containerName) == true
    }

    /// Returns true if this node is included via ITERATE mode (cyan)
    var isIncludedInIterateReview: Bool {
        // Container enumerate pattern: parent has enumeratedAttributes containing "*"
        // e.g., Physicist under Job Titles where jobTitles[] is configured
        if parent?.enumeratedAttributes?.contains("*") == true {
            return true
        }

        // Iterate attribute target: this node's name is in parent's parent's enumeratedAttributes
        // e.g., description when projects[].description is configured
        if let collection = parent?.parent {
            let nodeName = name.isEmpty ? displayLabel : name
            if collection.enumeratedAttributes?.contains(nodeName) == true {
                return true
            }
        }

        // Child of iterate container: parent's name is in great-grandparent's enumeratedAttributes
        // e.g., bullet under highlights when work[].highlights is configured
        guard let containerParent = parent,
              let entry = containerParent.parent,
              let collection = entry.parent else { return false }

        let containerName = containerParent.name.isEmpty ? containerParent.displayLabel : containerParent.name
        return collection.enumeratedAttributes?.contains(containerName) == true
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
        self.status = status
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
        child.myIndex = (children?.count ?? 0)
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
