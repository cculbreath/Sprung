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

    /// Returns true if any attribute is in "Separately" mode (entries can be toggled)
    var hasEnumeratedAttributes: Bool {
        !(enumeratedAttributes?.isEmpty ?? true)
    }

    /// Total revnode count for this subtree
    /// Counts: solo nodes, bundle attributes (1 each), iterate attributes (N each), container enumerate children
    var revnodeCount: Int {
        var count = 0

        // Container enumerate: each child is a revnode
        if enumeratedAttributes?.contains("*") == true {
            count += orderedChildren.count
        }
        // Bundle attributes: 1 revnode per attribute (regardless of entry count)
        else if let bundled = bundledAttributes, !bundled.isEmpty {
            count += bundled.count
        }

        // Iterate attributes: N revnodes per attribute (1 per entry)
        if let enumerated = enumeratedAttributes, !enumerated.isEmpty {
            // Filter out container enumerate marker "*"
            let iterateAttrs = enumerated.filter { $0 != "*" }
            let entryCount = orderedChildren.count
            count += iterateAttrs.count * entryCount
        }

        // Solo nodes: leaf with status == .aiToReplace (not already counted above)
        if status == .aiToReplace && orderedChildren.isEmpty {
            // Only count if not part of a container enumerate (those are counted above)
            if parent?.enumeratedAttributes?.contains("*") != true {
                count += 1
            }
        }

        // Recurse into children (but skip if this is container enumerate - already counted)
        if enumeratedAttributes?.contains("*") != true {
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

    /// Returns true if this node is a child of a container being reviewed in bundle/iterate mode
    var isIncludedInContainerReview: Bool {
        isIncludedInBundleReview || isIncludedInIterateReview
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
                let oldValueArray = collectDescendantValues(from: node)
                let concatenatedValue = oldValueArray.joined(separator: "\n")

                let groupedNodeData: [String: Any] = [
                    "id": node.id,
                    "name": node.name,
                    "value": concatenatedValue,
                    "tree_path": treePath,
                    "isGrouped": true,
                    "oldValueArray": oldValueArray,
                    "itemCount": oldValueArray.count,
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
        // Collect all values (either from childValues or direct value)
        var allValues: [String] = []
        var allIds: [String] = []

        for node in nodes {
            allIds.append(node.id)
            if let childValues = node.childValues, !childValues.isEmpty {
                // Container node - add all its children
                allValues.append(contentsOf: childValues)
            } else if !node.value.isEmpty {
                // Scalar node - add its value
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
            for (index, child) in node.orderedChildren.enumerated() {
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
            for (index, child) in node.orderedChildren.enumerated() {
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
