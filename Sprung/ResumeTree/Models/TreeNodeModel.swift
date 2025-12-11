// Sprung/ResumeTree/Models/TreeNodeModel.swift
import Foundation
import SwiftData
enum LeafStatus: String, Codable, Hashable {
    case isEditing
    case aiToReplace
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

    /// Returns true if this node should be included in AI revision
    /// (either directly selected or inherited from parent)
    var isSelectedForAIRevision: Bool {
        status == .aiToReplace || isInheritedAISelection
    }

    /// Toggle AI selection on this node and optionally propagate to children
    /// - Parameter propagateToChildren: If true, also sets all descendants to the new status
    func toggleAISelection(propagateToChildren: Bool = false) {
        if status == .aiToReplace {
            status = .saved
            if propagateToChildren {
                setChildrenAIStatus(to: .saved)
            }
        } else {
            status = .aiToReplace
            if propagateToChildren {
                setChildrenAIStatus(to: .aiToReplace)
            }
        }
    }

    /// Recursively set AI status on all descendants
    private func setChildrenAIStatus(to newStatus: LeafStatus) {
        guard let children = children else { return }
        for child in children {
            child.status = newStatus
            child.setChildrenAIStatus(to: newStatus)
        }
    }

    // MARK: - Smart Badge Counts

    /// Returns a meaningful count for badge display
    /// For section nodes (skills, work): counts direct children (categories, positions)
    /// For other nodes: counts selected items
    var reviewOperationsCount: Int {
        // For section-level nodes that are selected, count their direct children
        // This gives us "5 categories" for skills, "3 positions" for work
        if status == .aiToReplace && isSectionNode {
            return children?.count ?? 0
        }

        // If this node is selected but not a section, count as 1
        if status == .aiToReplace {
            return 1
        }

        // Otherwise, count selected direct children only (don't recurse into grandchildren)
        // This prevents counting 67 keywords when we want 5 categories
        guard let children = children else { return 0 }

        var count = 0
        for child in children {
            if child.status == .aiToReplace {
                // Child is directly selected - count as 1 operation
                count += 1
            } else if child.aiStatusChildren > 0 {
                // Child has selected descendants
                // For section nodes, just count this child as having selections
                // Don't recurse to avoid counting leaf nodes
                if isSectionNode {
                    count += 1
                } else {
                    count += child.reviewOperationsCount
                }
            }
        }
        return count
    }

    /// Returns true if this is a top-level section node (skills, work, education, etc.)
    private var isSectionNode: Bool {
        let sectionNames = ["skills", "work", "education", "projects", "volunteer", "awards", "certificates", "publications", "languages", "interests"]
        return sectionNames.contains(name.lowercased())
    }

    /// Returns a descriptive label for the badge count
    /// e.g., "3 categories" for skills, "2 positions" for work
    var reviewOperationsLabel: String? {
        let count = reviewOperationsCount
        guard count > 0 else { return nil }

        // Determine appropriate label based on node type
        switch name.lowercased() {
        case "skills":
            return count == 1 ? "1 category" : "\(count) categories"
        case "work":
            return count == 1 ? "1 position" : "\(count) positions"
        case "education":
            return count == 1 ? "1 school" : "\(count) schools"
        case "projects":
            return count == 1 ? "1 project" : "\(count) projects"
        default:
            return "\(count)"
        }
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
    static func traverseAndExportNodes(node: TreeNode, currentPath _: String = "")
        -> [[String: Any]] {
        var result: [[String: Any]] = []
        let treePath = node.buildTreePath()

        // Check if this node is DIRECTLY toggled (not just inherited from ancestor)
        if node.status == .aiToReplace {
            let hasChildren = node.children != nil && !node.orderedChildren.isEmpty

            if hasChildren {
                // PARENT TOGGLE: Concatenate all descendant values into ONE grouped node
                let childValues = collectDescendantValues(from: node)
                let concatenatedValue = childValues.joined(separator: ", ")

                let groupedNodeData: [String: Any] = [
                    "id": node.id,
                    "name": node.name,
                    "value": concatenatedValue,
                    "tree_path": treePath,
                    "isGrouped": true,
                    "childValues": childValues,
                    "childCount": childValues.count,
                    "isTitleNode": false
                ]
                result.append(groupedNodeData)

                // DON'T recurse - children are handled via grouping
                return result
            } else {
                // LEAF TOGGLE: Export individually
                // Export name if present (title node)
                if !node.name.isEmpty {
                    let titleNodeData: [String: Any] = [
                        "id": node.id,
                        "value": node.name,
                        "name": node.name,
                        "tree_path": treePath,
                        "isTitleNode": true,
                        "isGrouped": false
                    ]
                    result.append(titleNodeData)
                }
                // Export value if present (content node)
                if !node.value.isEmpty {
                    let valueNodeData: [String: Any] = [
                        "id": node.id,
                        "value": node.value,
                        "name": node.name,
                        "tree_path": treePath,
                        "isTitleNode": false,
                        "isGrouped": false
                    ]
                    result.append(valueNodeData)
                }
            }
        }
        // If this node has inherited selection (ancestor is toggled), skip - ancestor handles it
        // Otherwise, recurse into children to find other toggled nodes
        else if !node.isInheritedAISelection {
            let childNodes = node.children ?? []
            for child in childNodes {
                result.append(contentsOf: traverseAndExportNodes(node: child, currentPath: treePath))
            }
        }
        // If isInheritedAISelection is true, we skip - the ancestor that's directly toggled handles this node

        return result
    }

    /// Collect all descendant values from a node (for grouped export)
    private static func collectDescendantValues(from node: TreeNode) -> [String] {
        var values: [String] = []

        for child in node.orderedChildren {
            // If child has a value, add it
            if !child.value.isEmpty {
                values.append(child.value)
            } else if !child.name.isEmpty && child.orderedChildren.isEmpty {
                // Leaf with only name (no value, no children)
                values.append(child.name)
            }

            // Recurse into grandchildren
            values.append(contentsOf: collectDescendantValues(from: child))
        }

        return values
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
extension TreeNode {
    func applyDescriptor(_ descriptor: TemplateManifest.Section.FieldDescriptor?) {
        schemaKey = descriptor?.key
        schemaInputKindRaw = descriptor?.input?.rawValue
        schemaRequired = descriptor?.required ?? false
        schemaRepeatable = descriptor?.repeatable ?? false
        schemaPlaceholder = descriptor?.placeholder
        schemaTitleTemplate = descriptor?.titleTemplate
        schemaAllowsChildMutation = descriptor?.allowsManualMutations ?? false
        schemaAllowsNodeDeletion = descriptor?.allowsManualMutations ?? false
        if let validation = descriptor?.validation {
            schemaValidationRule = validation.rule.rawValue
            schemaValidationMessage = validation.message
            schemaValidationPattern = validation.pattern
            schemaValidationMin = validation.min
            schemaValidationMax = validation.max
            schemaValidationOptions = validation.options ?? []
        } else {
            schemaValidationRule = nil
            schemaValidationMessage = nil
            schemaValidationPattern = nil
            schemaValidationMin = nil
            schemaValidationMax = nil
            schemaValidationOptions = []
        }
    }
}
// MARK: - Schema convenience -------------------------------------------------
extension TreeNode {
    func copySchemaMetadata(from source: TreeNode) {
        schemaKey = source.schemaKey
        schemaInputKindRaw = source.schemaInputKindRaw
        schemaRequired = source.schemaRequired
        schemaRepeatable = source.schemaRepeatable
        schemaPlaceholder = source.schemaPlaceholder
        schemaTitleTemplate = source.schemaTitleTemplate
        schemaValidationRule = source.schemaValidationRule
        schemaValidationMessage = source.schemaValidationMessage
        schemaValidationPattern = source.schemaValidationPattern
        schemaValidationMin = source.schemaValidationMin
        schemaValidationMax = source.schemaValidationMax
        schemaValidationOptions = source.schemaValidationOptions
        schemaSourceKey = source.schemaSourceKey
        schemaAllowsChildMutation = source.schemaAllowsChildMutation
        schemaAllowsNodeDeletion = source.schemaAllowsNodeDeletion
    }
    func makeTemplateClone(for resume: Resume) -> TreeNode {
        let baseName: String
        if let titleTemplate = schemaTitleTemplate, titleTemplate.isEmpty == false {
            baseName = "New Item"
        } else if let placeholder = schemaPlaceholder, placeholder.isEmpty == false {
            baseName = placeholder
        } else if name.isEmpty == false {
            baseName = "New \(name)"
        } else {
            baseName = name
        }
        let clone = TreeNode(
            name: baseName,
            value: "",
            children: nil,
            parent: nil,
            inEditor: includeInEditor,
            status: .saved,
            resume: resume,
            isTitleNode: isTitleNode
        )
        clone.copySchemaMetadata(from: self)
        if !hasChildren {
            if let placeholder = schemaPlaceholder, placeholder.isEmpty == false {
                clone.value = placeholder
            } else {
                clone.value = ""
            }
        }
        for child in orderedChildren {
            let childClone = child.makeTemplateClone(for: resume)
            clone.addChild(childClone)
        }
        return clone
    }
    /// Determines whether the node's label ("name") should be editable in the UI.
    /// Manifest-backed nodes typically provide explicit titles, so we hide the name field
    /// unless the node lacks schema metadata.
    var allowsInlineNameEditing: Bool {
        if parent?.name == "section-labels" { return false }
        if schemaTitleTemplate != nil { return false }
        if schemaInputKind != nil { return false }
        if schemaKey != nil { return false }
        if parent?.schemaInputKind != nil { return false }
        if parent?.schemaTitleTemplate != nil { return false }
        if let parentKey = parent?.schemaKey, !parentKey.isEmpty { return false }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        return true
    }
    var allowsChildAddition: Bool {
        schemaAllowsChildMutation
    }
    var allowsDeletion: Bool {
        schemaAllowsNodeDeletion || (parent?.schemaAllowsChildMutation ?? false)
    }
}
// MARK: - Generic Path-Based Export for Review Phases

extension TreeNode {
    /// Find a child node by name (case-insensitive)
    func findChildByName(_ name: String) -> TreeNode? {
        let lowercasedName = name.lowercased()
        return children?.first { $0.name.lowercased() == lowercasedName }
    }

    /// Export nodes matching a path pattern for LLM review.
    ///
    /// # Path Syntax
    /// - `*` = enumerate objects/entries (e.g., job objects, skill categories)
    /// - `[]` = iterate array values (simple leaf items)
    /// - Plain names = schema field names
    ///
    /// # Examples
    /// - `skills.*.name` → exports the name field of each skill category
    /// - `skills.*.keywords` → exports the keywords container for each category
    /// - `work.*.highlights` → exports the highlights container for each job
    ///
    /// - Parameters:
    ///   - path: Path pattern to match (e.g., "skills.*.name")
    ///   - rootNode: The tree root to search from
    /// - Returns: Array of ExportedReviewNode for nodes matching the pattern
    static func exportNodesMatchingPath(_ path: String, from rootNode: TreeNode) -> [ExportedReviewNode] {
        let components = path.split(separator: ".").map(String.init)
        var results: [ExportedReviewNode] = []

        exportNodesRecursive(
            node: rootNode,
            pathComponents: components,
            componentIndex: 0,
            currentPath: [],
            results: &results
        )

        Logger.debug("📊 Exported \(results.count) nodes matching path '\(path)'")
        return results
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
            for child in node.orderedChildren {
                let childPath = currentPath + [child.name.isEmpty ? child.value : child.name]
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
            for child in node.orderedChildren {
                let childPath = currentPath + [child.name.isEmpty ? child.value : child.name]
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
        let displayName = node.name.isEmpty ? node.value : node.name
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
                if let proposedChildren = item.proposedChildren {
                    // Container modification - replace children
                    replaceChildValues(in: node, with: proposedChildren, context: context)
                } else {
                    // Scalar modification
                    node.value = item.proposedValue
                }
                Logger.info("✅ Modified node: \(item.displayName)")

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
}
