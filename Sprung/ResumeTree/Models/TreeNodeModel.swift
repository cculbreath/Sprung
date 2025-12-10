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
    @Relationship(deleteRule: .cascade) var viewChildren: [TreeNode]?
    weak var parent: TreeNode?
    var label: String { return resume.label(name) } // Assumes resume.label handles missing keys
    var editorLabel: String?
    /// Returns the effective display label: editorLabel if set, otherwise falls back to label
    var displayLabel: String {
        return editorLabel ?? label
    }
    @Relationship(deleteRule: .noAction) var resume: Resume
    var status: LeafStatus
    var depth: Int = 0
    /// Presentation depth derived from `viewChildren` hierarchy.
    var viewDepth: Int = 0
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
    /// When true, the node is hidden in the editor but its children should be surfaced as if they belonged to the parent.
    var editorTransparent: Bool = false
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
    var orderedViewChildren: [TreeNode] {
        (viewChildren ?? []).sorted { $0.myIndex < $1.myIndex }
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
        viewDepth = parent.map { $0.viewDepth + 1 } ?? 0
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
        child.viewDepth = viewDepth + 1
        if editorTransparent {
            child.depth = depth
            child.viewDepth = viewDepth
        }
        children?.append(child)
        return child
    }
    static func traverseAndExportNodes(node: TreeNode, currentPath _: String = "")
        -> [[String: Any]] {
        var result: [[String: Any]] = []
        let newPath = node.buildTreePath() // Use the instance method
        // Export node if it's marked for AI replacement OR if it's a title node (even if not for replacement, LLM might need context)
        // For "Fix Overflow", we are specifically interested in nodes from the "Skills & Expertise" section,
        // which will be filtered by the caller (extractSkillsForLLM in ResumeReviewService).
        // This function is more general for AI updates.
        if node.status == .aiToReplace {
            // First, handle title node content if present (name field)
            if !node.name.isEmpty { // Always export name field as a title node if it's not empty
                let titleNodeData: [String: Any] = [
                    "id": node.id,
                    "value": node.name, // Exporting node.name as "value" for the LLM
                    "name": node.name, // Also include the actual name field for context
                    "tree_path": newPath, // Path to this node
                    "isTitleNode": true // Explicitly mark as title node
                ]
                result.append(titleNodeData)
            }
            // Then, handle value node content if present
            if !node.value.isEmpty { // Always export value field as a content node if it's not empty
                let valueNodeData: [String: Any] = [
                    "id": node.id,
                    "value": node.value, // Exporting node.value
                    "name": node.name, // Include name for context/reference
                    "tree_path": newPath,
                    "isTitleNode": false // Explicitly mark as not a title node
                ]
                result.append(valueNodeData)
            }
        }
        // Force load children to ensure SwiftData loads the relationship
        let childNodes = node.children ?? []
        for child in childNodes {
            // Pass the child's full path for its children's context
            result.append(contentsOf: traverseAndExportNodes(node: child, currentPath: newPath))
        }
        return result
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
        clone.editorTransparent = editorTransparent
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
// MARK: - Hierarchical Review Export (Two-Phase Skills Review)
extension TreeNode {
    /// Export skill categories for Phase 1 review (category structure)
    /// Returns category info without full keyword lists
    static func exportSkillCategories(from rootNode: TreeNode) -> [(id: String, name: String, keywordCount: Int)] {
        var categories: [(id: String, name: String, keywordCount: Int)] = []

        // Find the skills section
        guard let skillsNode = rootNode.findChildByName("skills") else {
            Logger.debug("⚠️ exportSkillCategories: No 'skills' node found")
            return categories
        }

        // Each direct child of skills is a category
        for category in skillsNode.orderedChildren {
            let categoryName = category.name.isEmpty ? category.value : category.name

            // Count keywords - look for a "keywords" child node
            var keywordCount = 0
            if let keywordsNode = category.findChildByName("keywords") {
                keywordCount = keywordsNode.children?.count ?? 0
            }

            categories.append((
                id: category.id,
                name: categoryName,
                keywordCount: keywordCount
            ))
        }

        Logger.debug("📊 Exported \(categories.count) skill categories for Phase 1 review")
        return categories
    }

    /// Export keywords array for a specific category (Phase 2 review)
    /// Returns the category info plus its full keywords list
    static func exportCategoryKeywords(categoryId: String, from rootNode: TreeNode) -> (categoryName: String, keywords: [String])? {
        guard let skillsNode = rootNode.findChildByName("skills") else {
            Logger.debug("⚠️ exportCategoryKeywords: No 'skills' node found")
            return nil
        }

        // Find the category by ID
        guard let category = skillsNode.children?.first(where: { $0.id == categoryId }) else {
            Logger.debug("⚠️ exportCategoryKeywords: Category with ID \(categoryId) not found")
            return nil
        }

        let categoryName = category.name.isEmpty ? category.value : category.name

        // Extract keywords from the "keywords" child
        var keywords: [String] = []
        if let keywordsNode = category.findChildByName("keywords") {
            keywords = keywordsNode.orderedChildren.compactMap { keyword in
                let value = keyword.value.isEmpty ? keyword.name : keyword.value
                return value.isEmpty ? nil : value
            }
        }

        Logger.debug("📊 Exported \(keywords.count) keywords for category '\(categoryName)'")
        return (categoryName: categoryName, keywords: keywords)
    }

    /// Find a child node by name (case-insensitive)
    func findChildByName(_ name: String) -> TreeNode? {
        let lowercasedName = name.lowercased()
        return children?.first { $0.name.lowercased() == lowercasedName }
    }

    /// Apply category structure changes from Phase 1 review
    /// Handles rename, remove, merge operations
    @MainActor
    static func applyCategoryStructureChanges(
        _ changes: [CategoryRevisionNode],
        to rootNode: TreeNode,
        context: ModelContext
    ) {
        guard let skillsNode = rootNode.findChildByName("skills") else {
            Logger.warning("⚠️ applyCategoryStructureChanges: No 'skills' node found")
            return
        }

        for change in changes {
            guard change.userDecision == .accepted else { continue }

            guard let category = skillsNode.children?.first(where: { $0.id == change.id }) else {
                if change.action == .add {
                    // Create new category
                    let newCategory = TreeNode(
                        name: change.newName ?? "New Category",
                        value: "",
                        children: nil,
                        parent: skillsNode,
                        inEditor: true,
                        status: .saved,
                        resume: rootNode.resume,
                        isTitleNode: false
                    )
                    skillsNode.addChild(newCategory)

                    // Add keywords container
                    let keywordsNode = TreeNode(
                        name: "keywords",
                        value: "",
                        children: nil,
                        parent: newCategory,
                        inEditor: true,
                        status: .saved,
                        resume: rootNode.resume,
                        isTitleNode: false
                    )
                    newCategory.addChild(keywordsNode)

                    Logger.info("✅ Added new category: \(change.newName ?? "New Category")")
                }
                continue
            }

            switch change.action {
            case .keep:
                break // No action needed

            case .rename:
                if let newName = change.newName {
                    category.name = newName
                    Logger.info("✅ Renamed category to: \(newName)")
                }

            case .remove:
                deleteTreeNode(node: category, context: context)
                Logger.info("✅ Removed category: \(change.name)")

            case .merge:
                if let targetId = change.mergeWith,
                   let targetCategory = skillsNode.children?.first(where: { $0.id == targetId }) {
                    // Move all keywords from source to target
                    if let sourceKeywords = category.findChildByName("keywords"),
                       let targetKeywords = targetCategory.findChildByName("keywords") {
                        for keyword in sourceKeywords.orderedChildren {
                            keyword.parent = targetKeywords
                            targetKeywords.children?.append(keyword)
                        }
                    }
                    // Delete the source category
                    deleteTreeNode(node: category, context: context)
                    Logger.info("✅ Merged category '\(change.name)' into '\(change.mergeWithName ?? targetId)'")
                }

            case .add:
                break // Handled above when category not found
            }
        }

        do {
            try context.save()
            Logger.debug("✅ Saved category structure changes")
        } catch {
            Logger.error("❌ Failed to save category structure changes: \(error)")
        }
    }

    /// Apply keywords array changes from Phase 2 review
    /// Syncs the keywords container with the approved array
    @MainActor
    static func applyKeywordsChanges(
        categoryId: String,
        newKeywords: [String],
        to rootNode: TreeNode,
        context: ModelContext
    ) {
        guard let skillsNode = rootNode.findChildByName("skills") else {
            Logger.warning("⚠️ applyKeywordsChanges: No 'skills' node found")
            return
        }

        guard let category = skillsNode.children?.first(where: { $0.id == categoryId }) else {
            Logger.warning("⚠️ applyKeywordsChanges: Category with ID \(categoryId) not found")
            return
        }

        guard let keywordsNode = category.findChildByName("keywords") else {
            Logger.warning("⚠️ applyKeywordsChanges: No 'keywords' node in category")
            return
        }

        // Remove all existing keywords
        for keyword in keywordsNode.orderedChildren {
            context.delete(keyword)
        }
        keywordsNode.children?.removeAll()

        // Add new keywords
        for (index, keywordValue) in newKeywords.enumerated() {
            let keywordNode = TreeNode(
                name: "",
                value: keywordValue,
                children: nil,
                parent: keywordsNode,
                inEditor: true,
                status: .saved,
                resume: rootNode.resume,
                isTitleNode: false
            )
            keywordNode.myIndex = index
            keywordsNode.addChild(keywordNode)
        }

        do {
            try context.save()
            Logger.info("✅ Applied \(newKeywords.count) keywords to category")
        } catch {
            Logger.error("❌ Failed to save keywords changes: \(error)")
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
